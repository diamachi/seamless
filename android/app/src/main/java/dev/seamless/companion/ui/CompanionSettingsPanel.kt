package dev.seamless.companion.ui

import android.content.Intent
import android.provider.Settings
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.seamless.companion.connection.ConnectionRuntime
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp

@Composable
fun CompanionSettingsPanel(onPerformance: () -> Unit, onSetup: () -> Unit) {
    val context = LocalContext.current
    val connection by ConnectionRuntime.state.collectAsStateWithLifecycle()
    val preferences = context.getSharedPreferences("seamless_preferences", android.content.Context.MODE_PRIVATE)
    var syncClipboard by remember { mutableStateOf(preferences.getBoolean("foreground_clipboard_sync", false)) }
    var confirmForget by remember { mutableStateOf(false) }
    Column(Modifier.verticalScroll(rememberScrollState()).padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text("Settings", style = MaterialTheme.typography.headlineMedium)
        CompanionCard("Setup & permissions") {
            Text("Review access, pair another Mac and choose which features to use.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            Button(onClick = onSetup) { Text("Open setup guide") }
        }
        CompanionCard("Connection") {
            Text("The background service keeps your trusted Macs within reach. Force stop, reboot and battery restrictions can interrupt it.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            if (connection.isListening) {
                TextButton(onClick = { stopConnection(context) }) { Text("Pause connection") }
            } else {
                Button(onClick = { startConnection(context, pairing = false) }) { Text("Reconnect saved Macs") }
            }
            TextButton(onClick = { openSetupSettings(context, Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)) }) { Text("Battery settings") }
            TextButton(onClick = { confirmForget = true }) { Text("Forget trusted Macs…") }
        }
        CompanionCard("Phone clipboard") {
            Text("Automatically send copied text while Seamless is visible. When another app is in front, use Share → Seamless.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            androidx.compose.foundation.layout.Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("Sync while visible", style = MaterialTheme.typography.bodyMedium)
                Switch(checked = syncClipboard, onCheckedChange = {
                    syncClipboard = it
                    preferences.edit().putBoolean("foreground_clipboard_sync", it).apply()
                })
            }
        }
        for ((index, macID) in connection.connectedMacIDs.withIndex()) {
            TrustedMacSettings(macID, connection.connectedMacs.getOrNull(index) ?: "Mac")
        }
        CompanionCard("Developer tools") {
            TextButton(onClick = { dev.seamless.companion.features.TestNotification.post(context) }) { Text("Post a test notification") }
            TextButton(onClick = onPerformance) { Text("Performance lab") }
        }
    }
    if (confirmForget) {
        androidx.compose.material3.AlertDialog(
            onDismissRequest = { confirmForget = false }, title = { Text("Forget trusted Macs?") },
            text = { Text("This revokes access. You will need to pair again.") },
            confirmButton = { TextButton(onClick = { ConnectionRuntime.server?.forgetAllMacs(); confirmForget = false }) { Text("Forget") } },
            dismissButton = { TextButton(onClick = { confirmForget = false }) { Text("Cancel") } }
        )
    }
}

@Composable
private fun TrustedMacSettings(macID: String, name: String) {
    val context = LocalContext.current
    val preferences = context.getSharedPreferences("phone_policies", android.content.Context.MODE_PRIVATE)
    var automaticFiles by remember(macID) { mutableStateOf(preferences.getBoolean("file_auto.$macID", preferences.getBoolean("automatic_downloads", false))) }
    var contactsAllowed by remember(macID) { mutableStateOf(preferences.getBoolean("contacts_allowed.$macID", false)) }
    var automaticCamera by remember(macID) { mutableStateOf(preferences.getBoolean("camera_auto.$macID", false)) }
    CompanionCard(name) {
            Text("Automatically accept files from this Mac into Downloads")
            Switch(checked = automaticFiles, onCheckedChange = { automaticFiles = it; preferences.edit().putBoolean("file_auto.$macID", it).apply() })
            Text("Allow this Mac to start the camera while Seamless is visible")
            Switch(checked = automaticCamera, onCheckedChange = { automaticCamera = it; preferences.edit().putBoolean("camera_auto.$macID", it).apply() })
            Text("Allow this Mac to refresh phone contacts for calling")
            Switch(checked = contactsAllowed, onCheckedChange = { allowed ->
                contactsAllowed = allowed
                preferences.edit().putBoolean("contacts_allowed.$macID", allowed).apply()
                if (!allowed) dev.seamless.companion.connection.ConnectionRuntime.server?.revokeContacts(macID)
            })
            Text("Android camera permission is requested once. Background startup still follows Android’s restrictions. Turn these off at any time.", style = MaterialTheme.typography.bodySmall)
    }
}
