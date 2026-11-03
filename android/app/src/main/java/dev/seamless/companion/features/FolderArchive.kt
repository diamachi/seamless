package dev.seamless.companion.features

import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import java.io.File
import java.util.UUID
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/** Archives only the tree explicitly selected through Android's document picker. */
internal object FolderArchive {
    fun create(context: Context, tree: Uri): File {
        val archive = File(context.cacheDir, "Shared-folder-${UUID.randomUUID()}.zip")
        val root = DocumentsContract.getTreeDocumentId(tree)
        try {
            ZipOutputStream(archive.outputStream().buffered()).use { output ->
                appendChildren(context, tree, root, "", output, mutableSetOf())
            }
            return archive
        } catch (exception: Exception) {
            archive.delete()
            throw exception
        }
    }

    private fun appendChildren(context: Context, tree: Uri, parent: String, prefix: String,
                               output: ZipOutputStream, visited: MutableSet<String>) {
        check(prefix.count { it == '/' } < 128) { "Folder nesting is too deep" }
        check(visited.add(parent)) { "Folder contains a document cycle" }
        check(visited.size <= 100_000) { "Folder contains too many directories" }
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent)
        val columns = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME, DocumentsContract.Document.COLUMN_MIME_TYPE)
        val cursor = context.contentResolver.query(children, columns, null, null, null)
            ?: error("Cannot read selected folder")
        cursor.use {
            while (it.moveToNext()) {
                check(!Thread.currentThread().isInterrupted) { "Folder preparation cancelled" }
                val identifier = it.getString(0)
                val name = it.getString(1)
                require(BulkExchange.validName(name)) { "Folder contains an unsupported file name" }
                val path = prefix + name
                if (it.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                    output.putNextEntry(ZipEntry("$path/"))
                    output.closeEntry()
                    appendChildren(context, tree, identifier, "$path/", output, visited)
                } else {
                    output.putNextEntry(ZipEntry(path))
                    val document = DocumentsContract.buildDocumentUriUsingTree(tree, identifier)
                    context.contentResolver.openInputStream(document).use { input ->
                        requireNotNull(input) { "Cannot read $name" }
                        input.copyTo(output, 262_144)
                    }
                    output.closeEntry()
                }
            }
        }
    }
}
