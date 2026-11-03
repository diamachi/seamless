package dev.seamless.companion.ui

import android.os.SystemClock
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import dev.seamless.companion.connection.CompanionConnectionState

@Composable
internal fun PairingCard(state: CompanionConnectionState, onScanMac: () -> Unit) {
    val context = LocalContext.current
    var useFullCode by remember { mutableStateOf(false) }
    var now by remember { mutableLongStateOf(SystemClock.elapsedRealtime()) }
    LaunchedEffect(state.pairingCode) {
        while (state.pairingCode.isNotEmpty()) {
            now = SystemClock.elapsedRealtime()
            kotlinx.coroutines.delay(1_000)
        }
    }
    val remainingSeconds = ((state.pairingExpiresAt - now) / 1_000).coerceAtLeast(0)
    CompanionCard("Pair your Mac") {
        Text("On your Mac, choose Connect new phone → Create pairing QR. Then scan that QR here and approve your Mac.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        Button(onClick = onScanMac, modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp)) { Text("Scan Mac QR code") }
        TextButton(onClick = { useFullCode = !useFullCode }) { Text(if (useFullCode) "Hide full-code fallback" else "Use full code instead") }
        if (useFullCode) {
            OutlinedButton(enabled = !state.isCreatingPairingCode, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp),
                onClick = { startConnection(context, pairing = true) }) {
                Text(if (state.isCreatingPairingCode) "Creating code…" else "Create full pairing code")
            }
            if (state.isCreatingPairingCode) CircularProgressIndicator()
            if (state.pairingCode.isNotEmpty() && remainingSeconds > 0) {
                Text("Private · expires in ${remainingSeconds / 60}:${(remainingSeconds % 60).toString().padStart(2, '0')}", style = MaterialTheme.typography.labelLarge)
                SelectionContainer {
                    Text(state.pairingCode, fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall,
                        modifier = Modifier.heightIn(max = 140.dp).verticalScroll(rememberScrollState()))
                }
                Button(onClick = { copyText(context, "Seamless pairing", state.pairingCode) }) { Text("Copy full pairing code") }
            } else if (state.pairingCode.isNotEmpty()) {
                Text("This code expired. Create another one.", color = MaterialTheme.colorScheme.error)
            }
        }
        if (state.pairingError != null) Text(state.pairingError, color = MaterialTheme.colorScheme.error)
    }
}
