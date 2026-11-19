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
    onRemoteCamera: () -> Unit,
    onReadContacts: () -> Unit
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
    LaunchedEffect(connection.connectedMacIDs, connection.sharedTextToSend) {
        if (connection.connectedMacIDs.size == 1 && connection.sharedTextToSend.isNotEmpty()) {
            val sent = ConnectionRuntime.server?.sendClipboard(connection.sharedTextToSend) == true
            if (sent) ConnectionRuntime.update { it.copy(sharedTextToSend = "", message = "Shared text sent to your Mac") }
        }
    }
    val colors = companionColors(isSystemInDarkTheme())
    MaterialTheme(colorScheme = colors, shapes = androidx.compose.material3.Shapes(
        extraSmall = androidx.compose.foundation.shape.RoundedCornerShape(6.dp),
        small = androidx.compose.foundation.shape.RoundedCornerShape(10.dp),
        medium = androidx.compose.foundation.shape.RoundedCornerShape(12.dp),
        large = androidx.compose.foundation.shape.RoundedCornerShape(14.dp),
        extraLarge = androidx.compose.foundation.shape.RoundedCornerShape(18.dp)
    )) {
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
                        if (completed) setupPreferences.edit().putInt("setup_step", 0).apply()
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
                SharedTextDestinationDialog(connection)
                connection.contactsRequest?.let { request ->
                    androidx.compose.material3.AlertDialog(
                        onDismissRequest = { ConnectionRuntime.server?.shareContacts(request, false) },
                        title = { Text("Share contacts with ${request.macName}?") },
                        text = { Text("Allow this paired Mac to read names and phone numbers for its call picker. Contacts stay in memory on the Mac and are cleared on disconnect. You can revoke access in Settings.") },
                        confirmButton = { TextButton(onClick = onReadContacts) { Text("Allow contacts") } },
                        dismissButton = { TextButton(onClick = { ConnectionRuntime.server?.shareContacts(request, false) }) { Text("Decline") } }
                    )
                }
                PairingApproval(connection)
            }
        }
    }
}

@Composable
private fun companionColors(dark: Boolean) = if (dark) {
    darkColorScheme(primary = Color(0xFFABDCC9), onPrimary = Color(0xFF20252B),
        background = Color(0xFF18221F), onBackground = Color(0xFFF1F3F5),
        surface = Color(0xFF18221F), onSurface = Color(0xFFF1F3F5), onSurfaceVariant = Color(0xFFB9C0C8),
        surfaceContainerLow = Color(0xFF22312B), surfaceContainer = Color(0xFF2C3E35),
        outline = Color(0xFFB9C0C8), outlineVariant = Color(0xFF41464D),
        secondaryContainer = Color(0xFF314B3E), onSecondaryContainer = Color(0xFFABDCC9))
} else {
    lightColorScheme(primary = Color(0xFF32624F), onPrimary = Color.White,
        background = Color(0xFFF3F7F2), onBackground = Color(0xFF20252B),
        surface = Color(0xFFF3F7F2), onSurface = Color(0xFF20252B), onSurfaceVariant = Color(0xFF58616B),
        surfaceContainerLow = Color(0xFFFFFFFF), surfaceContainer = Color(0xFFABDCC9),
        outline = Color(0xFF68737D), outlineVariant = Color(0xFFD7DCE1),
        secondaryContainer = Color(0xFFE2EDE3), onSecondaryContainer = Color(0xFF32624F))
}
