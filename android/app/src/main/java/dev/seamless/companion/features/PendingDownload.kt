package dev.seamless.companion.features

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.ParcelFileDescriptor
import android.provider.MediaStore

internal class PendingDownload private constructor(private val context: Context, private val uri: Uri, val output: ParcelFileDescriptor.AutoCloseOutputStream) {
    fun publish() {
        if (Build.VERSION.SDK_INT >= 29) context.contentResolver.update(uri, ContentValues().apply { put(MediaStore.Downloads.IS_PENDING, 0) }, null, null)
    }
    fun abort() { context.contentResolver.delete(uri, null, null) }
    companion object {
        fun create(context: Context, name: String): PendingDownload? {
            if (Build.VERSION.SDK_INT < 29) return null
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, android.webkit.MimeTypeMap.getSingleton().getMimeTypeFromExtension(name.substringAfterLast('.', "").lowercase()) ?: "application/octet-stream")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = context.contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: error("Downloads is unavailable")
            try {
                val descriptor = context.contentResolver.openFileDescriptor(uri, "w") ?: error("Could not create download")
                return PendingDownload(context, uri, ParcelFileDescriptor.AutoCloseOutputStream(descriptor))
            } catch (exception: Exception) { context.contentResolver.delete(uri, null, null); throw exception }
        }
    }
}
