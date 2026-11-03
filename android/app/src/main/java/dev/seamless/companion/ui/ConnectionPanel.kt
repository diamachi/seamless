package dev.seamless.companion.ui

import android.content.Intent
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.seamless.companion.connection.CompanionConnectionState
import dev.seamless.companion.connection.ConnectionRuntime

@Composable
fun ConnectionPanel(state: CompanionConnectionState, onStartScreen: () -> Unit, onStartCamera: () -> Unit, onSetup: () -> Unit, onSettings: () -> Unit, onScanMac: () -> Unit) {
    val context = LocalContext.current
    val chooseFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        ConnectionRuntime.server?.offerFiles(uris)
    }
    val chooseFolder = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) ConnectionRuntime.server?.offerFolder(uri)
    }
    val saveFile = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        if (uri != null) {
            saveReceivedFile(context, uri)
        }
    }
    Column(
        Modifier.verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text("Overview", style = MaterialTheme.typography.headlineMedium)
        ConnectionOverviewCards(state, onSetup)
        if (state.connectedMacs.isEmpty()) PairingCard(state, onScanMac)
        SharingRequests(state, onStartScreen, onStartCamera)
        CompanionCard("Share with your Mac") {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(enabled = state.connectedMacs.size == 1, onClick = { chooseFile.launch(arrayOf("*/*")) }) { Text("Send files") }
                OutlinedButton(enabled = state.connectedMacs.isNotEmpty(), onClick = { sendPhoneClipboard(context) }) { Text("Send clipboard") }
            }
        }
        OutlinedButton(enabled = state.connectedMacs.size == 1 && !state.isPreparingFolder,
            onClick = { chooseFolder.launch(null) }) { Text("Send folder as ZIP") }
        if (state.isPreparingFolder) {
            CompanionCard("Preparing folder") {
                Text("Creating a ZIP before sending. Free phone storage is required.")
                androidx.compose.material3.LinearProgressIndicator(Modifier.fillMaxWidth())
            }
        }
        if (state.transferProgress.isNotEmpty() || state.outgoingFileCount > 0) {
            CompanionCard("File transfers") {
                Text("${state.outgoingFileCount} outgoing files remaining")
                for (progress in state.transferProgress.values) {
                    Text(progress.name, style = MaterialTheme.typography.titleSmall)
                    val fraction = if (progress.total > 0) progress.completed.toFloat() / progress.total else 0f
                    androidx.compose.material3.LinearProgressIndicator(progress = { fraction.coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth())
                    Text("${android.text.format.Formatter.formatFileSize(context, progress.completed)} of ${android.text.format.Formatter.formatFileSize(context, progress.total)}")
                }
            }
        }
        if (state.incomingFileOffer != null || state.receivedFile != null || state.sharedFilesToSend.isNotEmpty()) {
            FileSharingCard(state, chooseFile = { chooseFile.launch(arrayOf("*/*")) }, saveFile = { name -> saveFile.launch(name) })
        }
        if (state.sharedTextToSend.isNotEmpty() || state.incomingClipboard.isNotEmpty()) ClipboardCard(state)
        if (state.connectedMacs.isNotEmpty() && state.pairingCode.isNotEmpty()) PairingCard(state, onScanMac)
        if (state.hotspotSetupRequested) {
            CompanionCard("Hotspot setup") {
                Text("Enable your phone's hotspot, then join it from the Mac.")
                OutlinedButton(onClick = { openSetupSettings(context, Intent(Settings.ACTION_WIRELESS_SETTINGS)) }) { Text("Open hotspot settings") }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            TextButton(onClick = onSetup) { Text("Pair a Mac") }
            TextButton(onClick = onSettings) { Text("Settings") }
        }
    }
}

@Composable
private fun SharingRequests(state: CompanionConnectionState, onStartScreen: () -> Unit, onStartCamera: () -> Unit) {
    if (state.screenRequestedBy != null) {
        CompanionCard("Screen sharing request") {
            Text("Your Mac requested ${state.screenRequestedFramesPerSecond} fps. Android will ask which screen to share.")
            Button(onClick = onStartScreen) { Text("Approve screen sharing…") }
        }
    }
    if (state.cameraRequestedBy != null) {
        CompanionCard("Camera request") {
            Text("${state.cameraFacing.replaceFirstChar { it.uppercase() }} camera · ${state.cameraResolutionHeight}p · ${state.cameraFramesPerSecond} fps")
            Button(onClick = onStartCamera) { Text("Approve camera sharing…") }
        }
    }
}

@Composable
private fun FileSharingCard(state: CompanionConnectionState, chooseFile: () -> Unit, saveFile: (String) -> Unit) {
    CompanionCard("Files") {
        Text("Send a file to your Mac, or accept one here. No fixed file-size cap; available storage applies.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        OutlinedButton(enabled = state.connectedMacs.size == 1, onClick = chooseFile) { Text("Choose files to send") }
        if (state.sharedFilesToSend.isNotEmpty()) {
            Button(enabled = state.connectedMacs.size == 1, onClick = {
                ConnectionRuntime.server?.offerFiles(state.sharedFilesToSend.map { android.net.Uri.parse(it) })
                ConnectionRuntime.update { it.copy(sharedFilesToSend = emptyList()) }
            }) { Text("Send ${state.sharedFilesToSend.size} shared files to Mac") }
        }
        val offer = state.incomingFileOffer
        if (offer != null) {
            Text(offer.name, style = MaterialTheme.typography.titleSmall)
            Text(android.text.format.Formatter.formatFileSize(LocalContext.current, offer.size))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = { ConnectionRuntime.server?.acceptFile(offer.transferID, true) }) { Text("Accept") }
                TextButton(onClick = { ConnectionRuntime.server?.acceptFile(offer.transferID, false) }) { Text("Decline") }
            }
        }
        val received = state.receivedFile
        if (received != null) {
            Button(onClick = { saveFile(received.name) }) { Text("Save ${received.name}") }
        }
    }
}

@Composable
private fun ClipboardCard(state: CompanionConnectionState) {
    val context = LocalContext.current
    CompanionCard("Clipboard") {
        Text("Send copied text while this app is open.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        OutlinedButton(enabled = state.connectedMacs.isNotEmpty(), onClick = { sendPhoneClipboard(context) }) {
            Text("Send phone clipboard")
        }
        if (state.sharedTextToSend.isNotEmpty()) {
            Button(enabled = state.connectedMacs.isNotEmpty(), onClick = {
                ConnectionRuntime.server?.sendClipboard(state.sharedTextToSend)
                ConnectionRuntime.update { it.copy(sharedTextToSend = "") }
            }) { Text("Send shared text") }
        }
        if (state.incomingClipboard.isNotEmpty()) {
            Text("Text from your Mac is ready.", style = MaterialTheme.typography.bodyMedium)
            OutlinedButton(onClick = { copyText(context, "From Mac", state.incomingClipboard) }) { Text("Copy received text") }
        }
    }
}

@Composable
internal fun PairingApproval(state: CompanionConnectionState) {
    val request = state.pairingRequest ?: return
    AlertDialog(
        onDismissRequest = { ConnectionRuntime.server?.resolvePairing(request.requestID, false) },
        title = { Text("Trust ${request.macName}?") },
        text = { Text("Approve only the Mac whose QR you scanned, or where you entered this phone’s full pairing code.") },
        confirmButton = { TextButton(onClick = { ConnectionRuntime.server?.resolvePairing(request.requestID, true) }) { Text("Allow") } },
        dismissButton = { TextButton(onClick = { ConnectionRuntime.server?.resolvePairing(request.requestID, false) }) { Text("Deny") } }
    )
}
