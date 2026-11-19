// Handles Android share-sheet intents without opening the main app. File URI contents are staged before this Activity finishes because source-app read grants can expire with its lifecycle.

package dev.seamless.companion

import android.app.AlertDialog
import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.lifecycle.lifecycleScope
import dev.seamless.companion.connection.ConnectionRuntime
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class ShareActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        val files = mutableListOf<android.net.Uri>()
        @Suppress("DEPRECATION")
        if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            files.addAll(intent.getParcelableArrayListExtra<android.net.Uri>(Intent.EXTRA_STREAM).orEmpty())
        } else {
            @Suppress("DEPRECATION")
            val file = intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
            if (file != null) files.add(file)
        }
        intent.clipData?.let { clip ->
            for (index in 0 until clip.itemCount) clip.getItemAt(index).uri?.let { files.add(it) }
        }
        if (text == null && files.isEmpty()) { finish(); return }
        if (text != null && text.length > 32_000) {
            Toast.makeText(this, "Select text up to 32,000 characters", Toast.LENGTH_LONG).show()
            finish()
            return
        }
        val service = Intent(this, dev.seamless.companion.connection.ConnectionService::class.java)
        if (android.os.Build.VERSION.SDK_INT >= 26) startForegroundService(service) else startService(service)
        lifecycleScope.launch {
            repeat(20) {
                val state = ConnectionRuntime.state.value
                if (state.connectedMacIDs.size == 1) {
                    send(text, files.distinct(), state.connectedMacIDs.first())
                    return@launch
                }
                if (state.connectedMacIDs.size > 1) {
                    AlertDialog.Builder(this@ShareActivity).setTitle("Send to Mac")
                        .setItems(state.connectedMacs.toTypedArray()) { _, index -> send(text, files.distinct(), state.connectedMacIDs[index]) }
                        .setOnCancelListener { finish() }.show()
                    return@launch
                }
                delay(500)
            }
            Toast.makeText(this@ShareActivity, "Mac unavailable. Connect your Mac and share again.", Toast.LENGTH_LONG).show()
            finish()
        }
    }


    /// Hands shared content to a selected authenticated peer, staging file bytes before releasing Activity-scoped URI access.
    private fun send(text: String?, files: List<android.net.Uri>, macID: String) {
        lifecycleScope.launch {
            try {
                val sent = if (files.isEmpty()) {
                    ConnectionRuntime.server?.sendClipboard(text.orEmpty(), macID) == true
                } else {
                    // Copy before finishing because source URI grants belong to this share activity.
                    val staged = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                        files.map { uri ->
                            require(uri.scheme == "content")
                            val name = contentResolver.query(uri, arrayOf(android.provider.OpenableColumns.DISPLAY_NAME), null, null, null)?.use {
                                if (it.moveToFirst()) it.getString(0) else null
                            } ?: "Shared file"
                            val directory = java.io.File(cacheDir, "share-" + java.util.UUID.randomUUID()).apply { mkdirs() }
                            val destination = java.io.File(directory, name.replace("/", "_").replace("\\", "_").take(200))
                            contentResolver.openInputStream(uri).use { input ->
                                requireNotNull(input)
                                destination.outputStream().use { output -> input.copyTo(output) }
                            }
                            android.net.Uri.fromFile(destination)
                        }
                    }
                    val accepted = ConnectionRuntime.server?.offerFiles(staged, macID, temporary = true) == true
                    if (!accepted) staged.forEach { java.io.File(requireNotNull(it.path)).delete() }
                    accepted
                }
                Toast.makeText(this@ShareActivity, if (sent) "Sent to your Mac" else "Could not send. Try again.", Toast.LENGTH_SHORT).show()
            } catch (_: Exception) {
                Toast.makeText(this@ShareActivity, "Could not read shared files", Toast.LENGTH_LONG).show()
            }
            finish()
        }
    }
}
