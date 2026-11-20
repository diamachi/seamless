// Android Compose presentation and user actions for received text cards.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

package dev.seamless.companion.ui

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.seamless.companion.connection.CompanionConnectionState
import dev.seamless.companion.connection.ConnectionRuntime

/** Composes the received text cards interface from state and supplied callbacks. */
@Composable
/** Handles received text cards callback by translating the native window event into the owning app action. */
internal fun ReceivedTextCards(state: CompanionConnectionState) {
    val context = LocalContext.current
    CompanionCard("Received text") {
        TextButton(onClick = { ConnectionRuntime.update { it.copy(receivedTexts = emptyList(), incomingClipboard = "") } }) { Text("Clear all") }
        if (state.receivedTexts.isEmpty()) Text("Text sent from your Mac appears here.")
        LazyRow(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            items(state.receivedTexts, key = { it.id }) { item ->
                OutlinedCard(Modifier.width(250.dp)) {
                    Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(item.text, maxLines = 6, modifier = Modifier.heightIn(min = 80.dp))
                        Row {
                            TextButton(onClick = { copyText(context, "From Mac", item.text) }) { Text("Copy") }
                            TextButton(onClick = {
                                ConnectionRuntime.update { it.copy(receivedTexts = it.receivedTexts.filterNot { entry -> entry.id == item.id }) }
                            }) { Text("Delete") }
                        }
                    }
                }
            }
        }
    }
}

/** Composes the notification overview card interface from state and supplied callbacks. */
@Composable
/** Handles notification overview card callback by translating the native window event into the owning app action. */
internal fun NotificationOverviewCard() {
    val context = LocalContext.current
    CompanionCard("Notifications") {
        Text("Test phone → Mac after allowing Seamless in the Mac’s app filter.", style = MaterialTheme.typography.bodySmall)
        Row {
            TextButton(onClick = { dev.seamless.companion.features.TestNotification.post(context) }) { Text("Send test") }
            TextButton(onClick = {
                context.startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
            }) { Text("Allow phone notifications") }
        }
    }
}

/** Composes the send text composer interface from state and supplied callbacks. */

@Composable
/** Handles send text composer callback by translating the native window event into the owning app action. */
internal fun SendTextComposer(state: CompanionConnectionState) {
    var text by androidx.compose.runtime.remember { androidx.compose.runtime.mutableStateOf("") }
    CompanionCard("Send text to Mac") {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            OutlinedTextField(value = text, onValueChange = { text = it.take(32_000) },
                placeholder = { Text("Write text or paste a link") }, modifier = Modifier.weight(1f), maxLines = 4)
            TextButton(enabled = text.isNotBlank() && state.connectedMacIDs.size == 1, onClick = {
                if (ConnectionRuntime.server?.sendClipboard(text) == true) text = ""
            }) { Text("Send") }
        }
    }
}
