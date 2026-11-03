package dev.seamless.companion.ui

import android.content.Context
import android.os.Build
import android.text.format.Formatter
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.seamless.companion.connection.CompanionConnectionState

@Composable
internal fun ConnectionOverviewCards(state: CompanionConnectionState, onSetup: () -> Unit) {
    val context = LocalContext.current
    var showDetails by rememberSaveable { mutableStateOf(false) }
    val title = when {
        state.connectedMacs.isNotEmpty() -> "Your devices are together"
        state.isListening -> "Ready for your Mac"
        else -> "Connection paused"
    }
    CompanionCard(title) {
        Text("${Build.MANUFACTURER.replaceFirstChar { it.uppercase() }} ${Build.MODEL}", style = MaterialTheme.typography.headlineSmall)
        Text("Android ${Build.VERSION.RELEASE}", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(if (state.connectedMacs.isNotEmpty()) "${state.connectedMacs.size} Mac connected" else "Local connection", color = MaterialTheme.colorScheme.primary)
            TextButton(onClick = { showDetails = !showDetails }) { Text(if (showDetails) "Less" else "Details") }
        }
        if (showDetails) {
            Text(state.message, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text("Authenticated local connection · Wi-Fi or optional USB\nThe companion can stay connected in the background.", style = MaterialTheme.typography.bodySmall)
        }
        TextButton(onClick = { startConnection(context, pairing = false, reconnect = true) }) { Text("Reconnect Macs") }
    }
    for ((index, macID) in state.connectedMacIDs.withIndex()) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            MacDetailsCard(state.connectedMacs.getOrNull(index) ?: "Mac", state.macDetails[macID])
            TextButton(onClick = { dev.seamless.companion.connection.ConnectionRuntime.server?.disconnectMac(macID) }) {
                Text("Disconnect this Mac")
            }
        }
    }
    if (state.connectedMacIDs.isEmpty()) {
        CompanionCard("Connect your Mac") {
            Text("Pair once to bring your devices together.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            TextButton(onClick = onSetup) { Text("Open setup") }
        }
    }
}
