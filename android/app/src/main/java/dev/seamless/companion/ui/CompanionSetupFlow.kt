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
fun CompanionSetupFlow(state: CompanionConnectionState, onFinish: (Boolean) -> Unit) {
    var step by rememberSaveable { mutableIntStateOf(0) }
    val titles = listOf("Welcome", "Pair your Mac", "Choose permissions", "You're ready")
    Column(Modifier.fillMaxSize().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Set up Seamless", style = MaterialTheme.typography.titleLarge)
            TextButton(onClick = { onFinish(false) }) { Text("Later") }
        }
        LinearProgressIndicator(progress = { (step + 1) / 4f }, modifier = Modifier.fillMaxWidth())
        Text("${step + 1} of 4 · ${titles[step]}", style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            when (step) {
                0 -> CompanionCard("Your phone, connected.") {
                    Text("Files, clipboard, notifications and live sharing—together with your Mac.", style = MaterialTheme.typography.headlineSmall)
                    Text("Pair once, choose your features and keep using your phone. Wi-Fi does not require debugging.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Nothing starts sharing just because you finish setup.", style = MaterialTheme.typography.bodySmall)
                }
                1 -> {
                    PairingCard(state)
                    CompanionCard("On the Mac") {
                        Text("Open Seamless → Devices, paste this phone's code and confirm the trust request here.")
                        Text(if (state.connectedMacs.isNotEmpty()) "Connected to ${state.connectedMacs.joinToString()}" else "Waiting for your Mac", color = MaterialTheme.colorScheme.primary)
                    }
                }
                2 -> PermissionSetupPanel()
                else -> CompanionCard("Make yourself at home") {
                    Text("Overview keeps connection details and your Macs in one place. Requests appear only when something needs your attention.")
                    Text("You can close the companion screen while its connection service runs. Battery restrictions, force stop and reboot can interrupt it.", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text("Reopen this guide from Settings at any time. Optional permissions can stay off.", style = MaterialTheme.typography.bodySmall)
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(bottom = 16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            if (step > 0) OutlinedButton(onClick = { step -= 1 }) { Text("Back") }
            else Text("")
            Button(onClick = {
                if (step < 3) step += 1
                else onFinish(true)
            }) { Text(if (step < 3) "Continue" else "Go to overview") }
        }
    }
}
