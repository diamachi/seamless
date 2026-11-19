package dev.seamless.companion.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.seamless.companion.connection.CompanionConnectionState

@Composable
fun CompanionSetupFlow(state: CompanionConnectionState, onScanMac: () -> Unit, onFinish: (Boolean) -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val saved = context.getSharedPreferences("onboarding", android.content.Context.MODE_PRIVATE)
    var step by rememberSaveable { mutableIntStateOf(saved.getInt("setup_step", 0).coerceIn(0, 4)) }
    androidx.compose.runtime.LaunchedEffect(step) { saved.edit().putInt("setup_step", step).apply() }

    val titles = listOf("Welcome", "Pair your Mac", "Choose permissions", "Check both devices", "Ready")
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Set up Seamless", style = MaterialTheme.typography.titleLarge)
            TextButton(onClick = { onFinish(false) }) { Text("Later") }
        }
        Text(titles[step], style = MaterialTheme.typography.headlineSmall)
        Text(when (step) {
            0 -> "Bring your devices together."
            1 -> "One scan, then approve your Mac."
            2 -> "Choose what your trusted Mac can do."
            3 -> "Confirm alerts and sharing before you finish."
            else -> "Your devices are ready."
        }, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        LinearProgressIndicator(progress = { (step + 1) / 5f }, modifier = Modifier.fillMaxWidth())
        Text("Step ${step + 1} of 5", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            when (step) {
                0 -> CompanionCard("Your phone, connected.") {
                    Text("Files, clipboard, notifications and live sharing—together with your Mac.", style = MaterialTheme.typography.headlineSmall)
                    Text("Pair once, choose your features and keep using your phone. Wi-Fi does not require debugging.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Nothing starts sharing just because you finish setup.", style = MaterialTheme.typography.bodySmall)
                }
                1 -> {
                    PairingCard(state, onScanMac)
                    CompanionCard("On the Mac") {
                        Text("On the Mac, choose Connect new phone → Create pairing QR. Scan that Mac QR with this phone, then approve the trust request here.")
                        Text(if (state.connectedMacs.isNotEmpty()) "Connected to ${state.connectedMacs.joinToString()}" else "Waiting for your Mac", color = MaterialTheme.colorScheme.primary)
                    }
                }
                2 -> {
                    PermissionSetupPanel()
                    for ((index, macID) in state.connectedMacIDs.withIndex()) {
                        TrustedMacSettings(macID, state.connectedMacs.getOrNull(index) ?: "Mac")
                    }
                }
                3 -> {
                    NotificationSoundSetup()
                    CompanionCard("Finish on your Mac") {
                        Text("In Mac setup, review notification and Downloads access. Choose Android apps to mirror in Overview → Choose apps.")
                        Text("Send text from Mac to phone, then Share text → Seamless on Android. Send a small file in each direction and confirm the destination.")
                        Text("Screen sharing needs approval for each session. Calls and the optional webcam driver have their own setup.")
                    }
                }
                else -> CompanionCard("Make yourself at home") {
                    Text("Overview keeps connection details and your Macs in one place. Requests appear only when something needs your attention.")
                    Text("You can close the companion screen while its connection service runs. Battery restrictions, force stop and reboot can interrupt it.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Reopen this guide from Settings at any time. Optional permissions can stay off.", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(bottom = 16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            if (step > 0) OutlinedButton(shape = androidx.compose.foundation.shape.RoundedCornerShape(10.dp), onClick = { step -= 1 }) { Text("Back") }
            else Text("")
            Button(shape = androidx.compose.foundation.shape.RoundedCornerShape(10.dp), enabled = step != 1 || state.connectedMacIDs.isNotEmpty(), onClick = {
                if (step < 4) step += 1
                else onFinish(true)
            }) { Text(if (step < 4) "Continue" else "Go to overview") }
        }
    }
}
