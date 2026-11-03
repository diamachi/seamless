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
    var showQrScanner by rememberSaveable { mutableStateOf(false) }
    val scanMac = {
        startConnection(context, pairing = false)
        showQrScanner = true
    }
    var showSetup by rememberSaveable { mutableStateOf(false) }
    var showWelcome by rememberSaveable { mutableStateOf(!hasTrustedMac && !setupPreferences.getBoolean("seen", false)) }
    var showSettings by rememberSaveable { mutableStateOf(false) }
    var showBenchmark by rememberSaveable { mutableStateOf(false) }
    val connection by ConnectionRuntime.state.collectAsStateWithLifecycle()
    val benchmark by BenchmarkState.snapshot.collectAsStateWithLifecycle()
    LaunchedEffect(connection.screenRequestID) { onRemoteScreen() }
    LaunchedEffect(connection.cameraRequestID) { onRemoteCamera() }
    LaunchedEffect(connection.connectedMacIDs, connection.sharedFilesToSend) {
        if (connection.connectedMacIDs.size == 1 && connection.sharedFilesToSend.isNotEmpty()) {
            val files = connection.sharedFilesToSend
            val accepted = ConnectionRuntime.server?.offerFiles(files.map { android.net.Uri.parse(it) }) == true
            if (accepted) ConnectionRuntime.update { it.copy(sharedFilesToSend = emptyList()) }
        }
    }
    val colors = companionColors(isSystemInDarkTheme())
    MaterialTheme(colorScheme = colors) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().safeDrawingPadding()) {
                Row(Modifier.padding(horizontal = 20.dp, vertical = 12.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    Image(painterResource(R.drawable.ic_seamless_foreground), contentDescription = null, modifier = Modifier.size(32.dp))
                    Text("Seamless", style = MaterialTheme.typography.titleLarge)
                }
                if (showSetup) {
                    CompanionSetupFlow(connection, onScanMac = scanMac) { completed ->
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
                        else -> ConnectionPanel(connection, onStartScreen, onStartCamera, onSetup = { showSetup = true }, onSettings = { showSettings = true }, onScanMac = scanMac)
                    }
                }
                if (showQrScanner) PairingQrScannerDialog(onClose = { showQrScanner = false })
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
                SharingRequestDialogs(connection, onStartCamera)
                SharedFilesDestinationDialog(connection)
                PairingApproval(connection)
            }
        }
    }
}

@Composable
private fun companionColors(dark: Boolean) = if (dark) {
    darkColorScheme(primary = Color(0xFFFED7B8), onPrimary = Color(0xFF391D22),
        background = Color(0xFF231719), onBackground = Color(0xFFFFF1E7),
        surface = Color(0xFF231719), onSurface = Color(0xFFFFF1E7), onSurfaceVariant = Color(0xFFD0ACAB),
        surfaceContainerLow = Color(0xFF342125), surfaceContainer = Color(0xFF432A2E),
        outline = Color(0xFFAD8585), outlineVariant = Color(0xFF604047),
        secondaryContainer = Color(0xFF512E33), onSecondaryContainer = Color(0xFFFED7B8))
} else {
    lightColorScheme(primary = Color(0xFF59171B), onPrimary = Color.White,
        background = Color(0xFFFFF5EC), onBackground = Color(0xFF391D22),
        surface = Color(0xFFFFF5EC), onSurface = Color(0xFF391D22), onSurfaceVariant = Color(0xFF795C5D),
        surfaceContainerLow = Color(0xFFFFFAF5), surfaceContainer = Color(0xFFFED7B8),
        outline = Color(0xFF947071), outlineVariant = Color(0xFFE8C7BD),
        secondaryContainer = Color(0xFFF5DCD0), onSecondaryContainer = Color(0xFF59171B))
}
