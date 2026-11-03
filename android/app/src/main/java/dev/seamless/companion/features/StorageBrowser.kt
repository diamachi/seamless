package dev.seamless.companion.features

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import android.util.Base64
import android.util.Size
import dev.seamless.companion.connection.MacPeer
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

private data class BrowserDocument(val peerID: String, val uri: Uri, val directory: Boolean)

class StorageBrowser(private val context: Context, private val offer: (Uri, MacPeer, String) -> Unit) {
    private val documents = ConcurrentHashMap<String, BrowserDocument>()
    private val preferences = context.getSharedPreferences("shared_storage", Context.MODE_PRIVATE)

    fun handle(peer: MacPeer, type: String, payload: JSONObject, requestID: String) {
        try {
            when (type) {
                "browseList" -> list(peer, payload, requestID)
                "browseDownload" -> offer(document(peer, payload).uri, peer, payload.getString("entry"))
                "browseThumbnail" -> thumbnail(peer, payload, requestID)
            }
        } catch (_: Exception) {
            peer.channel.send("browseError", JSONObject().put("message", "Choose a shared folder or media on the phone, or refresh access.").put("requestID", requestID), requestID)
        }
    }

    fun revoke() { documents.clear() }

    fun disconnected(peerID: String) { documents.entries.removeAll { it.value.peerID == peerID } }

    private fun list(peer: MacPeer, payload: JSONObject, requestID: String) {
        val token = payload.optString("directory")
        val mediaOnly = payload.optBoolean("media")
        val offset = payload.optInt("offset").coerceIn(0, 100_000)
        val result = JSONArray()
        var total = 0
        var title = "Shared folder"
        val fullAccess = hasFullAccess()
        if (fullAccess && mediaOnly && token.isEmpty()) {
            title = "Photos and videos"
            val collection = MediaStore.Files.getContentUri("external")
            val projection = arrayOf(MediaStore.Files.FileColumns._ID, MediaStore.Files.FileColumns.DISPLAY_NAME,
                MediaStore.Files.FileColumns.MIME_TYPE, MediaStore.Files.FileColumns.SIZE)
            val selection = "${MediaStore.Files.FileColumns.MEDIA_TYPE} IN (?,?)"
            val arguments = arrayOf(MediaStore.Files.FileColumns.MEDIA_TYPE_IMAGE.toString(), MediaStore.Files.FileColumns.MEDIA_TYPE_VIDEO.toString())
            context.contentResolver.query(collection, projection, selection, arguments, "${MediaStore.Files.FileColumns.DATE_ADDED} DESC")?.use { cursor ->
                while (cursor.moveToNext()) {
                    if (total++ < offset || result.length() >= 100) continue
                    val uri = android.content.ContentUris.withAppendedId(collection, cursor.getLong(0))
                    result.put(entry(peer, uri, cursor.getString(1) ?: "Media", cursor.getString(2) ?: "", cursor.getLong(3)))
                }
            }
        } else if (fullAccess && !mediaOnly) {
            val root = Environment.getExternalStorageDirectory().canonicalFile
            val directory = if (token.isEmpty()) root else File(requireNotNull(document(peer, payload).uri.path)).canonicalFile
            require(directory == root || directory.path.startsWith(root.path + File.separator))
            val children = directory.listFiles()?.sortedWith(compareBy<File> { !it.isDirectory }.thenBy { it.name.lowercase() }).orEmpty()
            for (file in children) {
                val canonical = file.canonicalFile
                if (!canonical.path.startsWith(root.path + File.separator) || !file.canRead()) continue
                if (total++ < offset || result.length() >= 100) continue
                val mime = if (file.isDirectory) DocumentsContract.Document.MIME_TYPE_DIR else android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "application/octet-stream"
                result.put(entry(peer, Uri.fromFile(canonical), file.name, mime, file.length()))
            }
        } else if (token.isEmpty() && mediaOnly) {
            title = "Selected photos and videos"
            val selected = preferences.getStringSet("media", emptySet()).orEmpty().sorted()
            for (uriString in selected) {
                if (total++ < offset) continue
                if (result.length() >= 100) continue
                val uri = Uri.parse(uriString)
                context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE), null, null, null)?.use { cursor ->
                    if (cursor.moveToFirst()) result.put(entry(peer, uri, cursor.getString(0) ?: "Media", context.contentResolver.getType(uri) ?: "application/octet-stream", cursor.getLong(1)))
                }
            }
        } else {
            val root = preferences.getString("tree", null)?.let(Uri::parse) ?: error("Choose a folder on the phone")
            val directory = if (token.isEmpty()) {
                DocumentsContract.buildDocumentUriUsingTree(root, DocumentsContract.getTreeDocumentId(root))
            } else {
                val stored = document(peer, payload)
                require(stored.directory)
                stored.uri
            }
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(root, DocumentsContract.getDocumentId(directory))
            val columns = arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_SIZE)
            context.contentResolver.query(children, columns, null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    if (total++ < offset) continue
                    if (result.length() >= 100) continue
                    val uri = DocumentsContract.buildDocumentUriUsingTree(root, cursor.getString(0))
                    result.put(entry(peer, uri, cursor.getString(1), cursor.getString(2), cursor.getLong(3)))
                }
            }
        }
        peer.channel.send("browseResult", JSONObject().put("requestID", requestID).put("directory", token).put("title", title)
            .put("entries", result).put("nextOffset", if (total > offset + 100) offset + 100 else -1), requestID)
    }

    private fun hasFullAccess(): Boolean {
        return Build.VERSION.SDK_INT >= 30 && Environment.isExternalStorageManager() && preferences.getBoolean("full_access_enabled", false)
    }

    private fun entry(peer: MacPeer, uri: Uri, name: String, mime: String, size: Long): JSONObject {
        require(documents.size < 100_000) { "Reconnect to refresh browser" }
        val directory = mime == DocumentsContract.Document.MIME_TYPE_DIR
        val token = UUID.randomUUID().toString()
        documents[token] = BrowserDocument(peer.id, uri, directory)
        return JSONObject().put("id", token).put("name", name.take(255)).put("mime", mime.take(120))
            .put("directory", directory).put("size", maxOf(0, size))
    }

    private fun document(peer: MacPeer, payload: JSONObject): BrowserDocument {
        val token = payload.optString("entry", payload.optString("directory"))
        val document = documents[token] ?: error("Refresh browser")
        require(document.peerID == peer.id)
        if (document.uri.scheme == "file") require(hasFullAccess())
        return document
    }

    private fun thumbnail(peer: MacPeer, payload: JSONObject, requestID: String) {
        val document = document(peer, payload)
        require(!document.directory)
        val resolver = context.contentResolver
        val mime = if (document.uri.scheme == "file") android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(File(requireNotNull(document.uri.path)).extension.lowercase()).orEmpty() else resolver.getType(document.uri).orEmpty()
        require(mime.startsWith("image/") || mime.startsWith("video/"))
        val bitmap: Bitmap = if (Build.VERSION.SDK_INT >= 29 && document.uri.scheme != "file") {
            resolver.loadThumbnail(document.uri, Size(240, 240), null)
        } else if (mime.startsWith("video/")) {
            val retriever = MediaMetadataRetriever()
            try { retriever.setDataSource(context, document.uri); requireNotNull(retriever.frameAtTime) }
            finally { retriever.release() }
        } else {
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            resolver.openInputStream(document.uri).use { BitmapFactory.decodeStream(it, null, bounds) }
            val options = BitmapFactory.Options().apply { inSampleSize = maxOf(1, maxOf(bounds.outWidth, bounds.outHeight) / 240) }
            resolver.openInputStream(document.uri).use { requireNotNull(BitmapFactory.decodeStream(it, null, options)) }
        }
        val scale = minOf(1f, 240f / maxOf(bitmap.width, bitmap.height))
        val small = Bitmap.createScaledBitmap(bitmap, maxOf(1, (bitmap.width * scale).toInt()), maxOf(1, (bitmap.height * scale).toInt()), true)
        val output = ByteArrayOutputStream()
        small.compress(Bitmap.CompressFormat.JPEG, 65, output)
        if (small !== bitmap) small.recycle()
        bitmap.recycle()
        require(output.size() < 60_000)
        peer.channel.send("browseThumbnail", JSONObject().put("entry", payload.getString("entry"))
            .put("image", Base64.encodeToString(output.toByteArray(), Base64.NO_WRAP)), requestID)
    }
}
