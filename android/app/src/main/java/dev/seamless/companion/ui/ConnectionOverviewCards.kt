// Android Compose presentation and user actions for connection overview cards.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

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

/** Composes the connection overview cards interface from state and supplied callbacks. */
@Composable
/** Handles connection overview cards callback by translating the native window event into the owning app action. */
internal fun ConnectionOverviewCards(state: CompanionConnectionState, onSetup: () -> Unit) {
    val context = LocalContext.current
    var showDetails by rememberSaveable { mutableStateOf(false) }
    val title = when {
        state.connectedMacs.isNotEmpty() -> "Your devices are together"
        state.isListening -> "Ready for your Mac"
        else -> "Connection paused"
    }

    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(title, style = MaterialTheme.typography.titleSmall)
        TextButton(onClick = { showDetails = !showDetails }) { Text(if (showDetails) "Less" else "Details") }
    }
    if (showDetails) {
        Text(Build.MODEL + " · Android " + Build.VERSION.RELEASE, style = MaterialTheme.typography.bodySmall)
        Text(dev.seamless.companion.features.BackgroundConnectionDiagnostics.summary(context), style = MaterialTheme.typography.bodySmall)
    }
    if (state.connectedMacIDs.isEmpty()) {
        CompanionCard("Connect your Mac") {
            TextButton(onClick = { startConnection(context, pairing = false, reconnect = true) }) { Text("Reconnect") }
            TextButton(onClick = onSetup) { Text("Pair a Mac") }
        }
    } else {
        androidx.compose.foundation.lazy.LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            items(state.connectedMacIDs.size) { index ->
                val macID = state.connectedMacIDs[index]
                androidx.compose.foundation.layout.Box(Modifier.fillParentMaxWidth(if (state.connectedMacIDs.size > 1) 0.9f else 1f)) {
                    CompanionCard(state.connectedMacs.getOrNull(index) ?: "Mac") {
                        MacDetailsContent("", state.macDetails[macID])
                        if (showDetails) TextButton(onClick = { dev.seamless.companion.connection.ConnectionRuntime.server?.disconnectMac(macID) }) { Text("Disconnect") }
                    }
                }
            }
        }
    }
}
