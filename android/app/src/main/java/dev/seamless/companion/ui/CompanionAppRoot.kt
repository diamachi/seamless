package dev.seamless.companion.ui

import android.content.Context
import androidx.compose.foundation.Image
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import dev.seamless.companion.R
import dev.seamless.companion.connection.ConnectionRuntime
import dev.seamless.companion.screen.BenchmarkState

@Composable
fun CompanionAppRoot(
    initialFrameRate: Int,
    initialMaximumDimension: Int,
    onProfileChanged: (Int, Int) -> Unit,
    onStartBenchmark: () -> Unit,
    onStopBenchmark: () -> Unit,
    onStartScreen: () -> Unit,
    onStartCamera: () -> Unit,
    onRemoteScreen: () -> Unit,
    onRemoteCamera: () -> Unit
) {
    val context = LocalContext.current
    val setupPreferences = context.getSharedPreferences("onboarding", Context.MODE_PRIVATE)
    val hasTrustedMac = context.getSharedPreferences("connection_identity", Context.MODE_PRIVATE).all.keys.any { it.startsWith("peer.") }
    var showSetup by rememberSaveable { mutableStateOf(false) }
    var showWelcome by rememberSaveable { mutableStateOf(!hasTrustedMac && !setupPreferences.getBoolean("seen", false)) }
    var showSettings by rememberSaveable { mutableStateOf(false) }
    var showBenchmark by rememberSaveable { mutableStateOf(false) }
    val connection by ConnectionRuntime.state.collectAsStateWithLifecycle()
    val benchmark by BenchmarkState.snapshot.collectAsStateWithLifecycle()
    LaunchedEffect(connection.screenRequestID) { onRemoteScreen() }
    LaunchedEffect(connection.cameraRequestID) { onRemoteCamera() }
    val colors = companionColors(isSystemInDarkTheme())
    MaterialTheme(colorScheme = colors) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                Row(Modifier.padding(horizontal = 20.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Image(painterResource(R.drawable.ic_seamless_foreground), contentDescription = null, modifier = Modifier.size(32.dp))
                    Text("Seamless", style = MaterialTheme.typography.titleLarge)
                }
                if (showSetup) {
                    CompanionSetupFlow(connection) { completed ->
                        setupPreferences.edit().putBoolean("seen", true).putBoolean("completed", completed).apply()
                        showSetup = false
                    }
                } else {
                    PrimaryTabRow(selectedTabIndex = if (showSettings || showBenchmark) 1 else 0) {
                        Tab(selected = !showSettings && !showBenchmark, onClick = { showSettings = false; showBenchmark = false }, text = { Text("Overview") })
                        Tab(selected = showSettings || showBenchmark, onClick = { showSettings = true; showBenchmark = false }, text = { Text("Settings") })
                    }
                    when {
                        showBenchmark -> CompanionScreen(benchmark, initialFrameRate, initialMaximumDimension, onProfileChanged, onStartBenchmark, onStopBenchmark)
                        showSettings -> CompanionSettingsPanel(onPerformance = { showBenchmark = true; showSettings = false }, onSetup = { showSetup = true })
                        else -> ConnectionPanel(connection, onStartScreen, onStartCamera, onSetup = { showSetup = true }, onSettings = { showSettings = true })
                    }
                }
                if (showWelcome) {
                    androidx.compose.material3.AlertDialog(
                        onDismissRequest = { showWelcome = false; setupPreferences.edit().putBoolean("seen", true).apply() },
                        title = { Text("Welcome to Seamless") },
                        text = { Text("Connect your Mac and walk through one-time permissions. You choose what to allow; nothing starts sharing during setup.") },
                        confirmButton = { TextButton(onClick = {
                            setupPreferences.edit().putBoolean("seen", true).apply()
                            showWelcome = false
                            showSetup = true
                        }) { Text("Start setup") } },
                        dismissButton = { TextButton(onClick = { showWelcome = false; setupPreferences.edit().putBoolean("seen", true).apply() }) { Text("Later") } }
                    )
                }
                PairingApproval(connection)
            }
        }
    }
}

@Composable
private fun companionColors(dark: Boolean) = if (dark) {
    darkColorScheme(primary = Color(0xFFE6BC7A), onPrimary = Color(0xFF29231B),
        background = Color(0xFF1D1C1A), onBackground = Color(0xFFEEE9DF),
        surface = Color(0xFF1D1C1A), onSurface = Color(0xFFEEE9DF), onSurfaceVariant = Color(0xFFB7B0A3),
        surfaceContainerLow = Color(0xFF2B2824), surfaceContainer = Color(0xFF342F28),
        outline = Color(0xFF71685C), outlineVariant = Color(0xFF423D35),
        secondaryContainer = Color(0xFF403529), onSecondaryContainer = Color(0xFFE6BC7A))
} else {
    lightColorScheme(primary = Color(0xFF8C5C25), onPrimary = Color.White,
        background = Color(0xFFF7F5EF), onBackground = Color(0xFF302D27),
        surface = Color(0xFFF7F5EF), onSurface = Color(0xFF302D27), onSurfaceVariant = Color(0xFF777166),
        surfaceContainerLow = Color(0xFFFFFDFA), surfaceContainer = Color(0xFFF4EDDE),
        outline = Color(0xFF938878), outlineVariant = Color(0xFFE4DED2),
        secondaryContainer = Color(0xFFF1E4CD), onSecondaryContainer = Color(0xFF8C5C25))
}
