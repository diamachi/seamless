// Android Compose presentation and user actions for debug console.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

package dev.seamless.companion.ui

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.seamless.companion.features.DebugEvents

/** Composes the debug console interface from state and supplied callbacks. */
@Composable
/** Handles debug console callback by translating the native window event into the owning app action. */
internal fun DebugConsole() {
    val enabled by DebugEvents.enabled.collectAsStateWithLifecycle()
    val lines by DebugEvents.lines.collectAsStateWithLifecycle()
    val context = LocalContext.current
    CompanionCard("Debug mode") {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Record diagnostics")
            Switch(checked = enabled, onCheckedChange = { DebugEvents.enabled.value = it })
        }
        Text("Enable, reproduce the issue, then copy the report. Up to 500 events stay in memory. Private payloads are excluded.", style = MaterialTheme.typography.bodySmall)
        Row {
            TextButton(onClick = {
                copyText(context, "Seamless diagnostics", "Seamless · Android " + android.os.Build.VERSION.RELEASE + "\n" + lines.joinToString("\n"))
            }) { Text("Copy report") }
            TextButton(onClick = { DebugEvents.clear() }) { Text("Clear") }
        }
        if (enabled || lines.isNotEmpty()) {
            Text(lines.joinToString("\n").ifEmpty { "Waiting for activity…" },
                fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.fillMaxWidth().height(220.dp).verticalScroll(rememberScrollState()))
        }
    }
}
