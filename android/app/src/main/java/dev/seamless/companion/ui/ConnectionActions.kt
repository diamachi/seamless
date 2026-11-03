package dev.seamless.companion.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import dev.seamless.companion.connection.ConnectionRuntime
import dev.seamless.companion.connection.ConnectionService
import java.io.File

internal fun startConnection(context: Context, pairing: Boolean, reconnect: Boolean = false) {
    context.getSharedPreferences("connection_settings", Context.MODE_PRIVATE)
        .edit().putBoolean("reconnect_on_launch", true).apply()
    val intent = Intent(context, ConnectionService::class.java)
    if (pairing) {
        ConnectionRuntime.update { it.copy(isCreatingPairingCode = true, pairingError = null) }
        intent.action = ConnectionService.ACTION_PAIR
    } else if (reconnect) {
        intent.action = ConnectionService.ACTION_RECONNECT
    }
    try {
        if (Build.VERSION.SDK_INT >= 26) {
            context.startForegroundService(intent)
        } else {
            context.startService(intent)
        }
    } catch (exception: RuntimeException) {
        ConnectionRuntime.update { it.copy(isCreatingPairingCode = false, pairingError = exception.message ?: "Could not start pairing") }
    }
}

internal fun stopConnection(context: Context) {
    context.getSharedPreferences("connection_settings", Context.MODE_PRIVATE)
        .edit().putBoolean("reconnect_on_launch", false).apply()
    context.stopService(Intent(context, ConnectionService::class.java))
}

internal fun copyText(context: Context, label: String, text: String) {
    val clipboard = context.getSystemService(ClipboardManager::class.java)
    clipboard.setPrimaryClip(ClipData.newPlainText(label, text))
}

internal fun sendPhoneClipboard(context: Context) {
    val clipboard = context.getSystemService(ClipboardManager::class.java)
    val text = clipboard.primaryClip?.getItemAt(0)?.coerceToText(context)?.toString().orEmpty()
    if (text.isNotEmpty()) {
        ConnectionRuntime.server?.sendClipboard(text.take(32_000))
    } else {
        ConnectionRuntime.update { it.copy(message = "Copy some text first, then send it here") }
    }
}

internal fun saveReceivedFile(context: Context, destination: Uri) {
    val received = ConnectionRuntime.state.value.receivedFile ?: return
    Thread({
        try {
            context.contentResolver.openOutputStream(destination).use { output ->
                requireNotNull(output)
                File(received.path).inputStream().use { input -> input.copyTo(output) }
            }
            File(received.path).delete()
            ConnectionRuntime.update { it.copy(message = "File saved", receivedFile = null) }
            ConnectionRuntime.server?.advanceFileQueue()
        } catch (exception: Exception) {
            ConnectionRuntime.update { it.copy(message = exception.message ?: "Could not save file") }
        }
    }, "SeamlessFileSave").start()
}
