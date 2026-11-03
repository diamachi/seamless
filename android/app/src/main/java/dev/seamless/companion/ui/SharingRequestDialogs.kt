package dev.seamless.companion.ui

import android.net.Uri
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.dp
import dev.seamless.companion.connection.CompanionConnectionState
import dev.seamless.companion.connection.ConnectionRuntime

@Composable
internal fun SharingRequestDialogs(state: CompanionConnectionState, onStartCamera: () -> Unit) {
    val offer = state.incomingFileOffer
    var dismissedFile by rememberSaveable(offer?.transferID) { mutableStateOf(false) }
    var dismissedCamera by rememberSaveable(state.cameraRequestID) { mutableStateOf(false) }
    if (offer != null && !dismissedFile) {
        AlertDialog(
            onDismissRequest = { dismissedFile = true },
            title = { Text("Receive file from your Mac?") },
            text = { Text("${offer.name}\nAccepted files save to Downloads on Android 10 and newer.") },
            confirmButton = { TextButton(onClick = { ConnectionRuntime.server?.acceptFile(offer.transferID, true) }) { Text("Accept & download") } },
            dismissButton = { TextButton(onClick = { ConnectionRuntime.server?.acceptFile(offer.transferID, false) }) { Text("Decline") } }
        )
    } else if (state.cameraRequestedBy != null && !dismissedCamera) {
        AlertDialog(
            onDismissRequest = { dismissedCamera = true },
            title = { Text("Share your phone camera?") },
            text = { Text("Your paired Mac requested the ${state.cameraFacing} camera at ${state.cameraResolutionHeight}p. You can stop sharing from the camera notification.") },
            confirmButton = { TextButton(onClick = { dismissedCamera = true; onStartCamera() }) { Text("Start camera") } },
            dismissButton = { TextButton(onClick = { dismissedCamera = true }) { Text("Later") } }
        )
    }
}

@Composable
internal fun SharedFilesDestinationDialog(state: CompanionConnectionState) {
    val context = androidx.compose.ui.platform.LocalContext.current
    if (state.sharedFilesToSend.isEmpty() || state.connectedMacIDs.size == 1) return
    AlertDialog(
        onDismissRequest = { ConnectionRuntime.update { it.copy(sharedFilesToSend = emptyList()) } },
        title = { Text(if (state.connectedMacIDs.isEmpty()) "Waiting for your Mac" else "Send to which Mac?") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("${state.sharedFilesToSend.size} shared files. ${if (state.connectedMacIDs.isEmpty()) "Reconnect to send automatically, or cancel and try again later." else "Choose the destination."}")
                state.connectedMacIDs.forEachIndexed { index, macID ->
                    TextButton(onClick = {
                        val accepted = ConnectionRuntime.server?.offerFiles(state.sharedFilesToSend.map { Uri.parse(it) }, macID) == true
                        if (accepted) ConnectionRuntime.update { it.copy(sharedFilesToSend = emptyList()) }
                    }) { Text(state.connectedMacs.getOrElse(index) { "Mac" }) }
                }
                if (state.connectedMacIDs.isEmpty()) {
                    TextButton(onClick = { startConnection(context, pairing = false, reconnect = true) }) { Text("Reconnect") }
                }
            }
        },
        confirmButton = { TextButton(onClick = { ConnectionRuntime.update { it.copy(sharedFilesToSend = emptyList()) } }) { Text("Cancel") } }
    )
}
