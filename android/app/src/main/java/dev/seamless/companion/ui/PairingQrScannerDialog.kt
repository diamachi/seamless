package dev.seamless.companion.ui

import android.Manifest
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.ContextCompat
import dev.seamless.companion.connection.ConnectionRuntime
import dev.seamless.companion.features.MacQrPairingTask
import java.util.concurrent.atomic.AtomicBoolean

@Composable
internal fun PairingQrScannerDialog(onClose: () -> Unit) {
    val context = LocalContext.current
    var allowed by remember { mutableStateOf(ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) }
    var sending by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var request by remember { mutableStateOf<MacQrPairingTask?>(null) }
    val alive = remember { AtomicBoolean(true) }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { allowed = it }
    androidx.lifecycle.compose.LifecycleEventEffect(androidx.lifecycle.Lifecycle.Event.ON_RESUME) {
        allowed = ContextCompat.checkSelfPermission(context, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED
    }
    LaunchedEffect(Unit) { if (!allowed) permission.launch(Manifest.permission.CAMERA) }
    DisposableEffect(Unit) { onDispose { alive.set(false); request?.close() } }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.fillMaxSize().safeDrawingPadding().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Scan Mac QR", style = MaterialTheme.typography.titleLarge)
                    TextButton(onClick = onClose) { Text("Cancel") }
                }
                Text("On your Mac, open Connect new phone → Create pairing QR. Point this camera at that QR. Images are processed on this phone and are not saved or sent.")
                if (!allowed) {
                    Text("Camera permission is needed to scan. You can cancel and use the full-code fallback instead.")
                    Button(onClick = { permission.launch(Manifest.permission.CAMERA) }) { Text("Allow camera") }
                    TextButton(onClick = {
                        openSetupSettings(context, android.content.Intent(android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            android.net.Uri.parse("package:${context.packageName}")))
                    }) { Text("Open app permission settings") }
                } else if (sending) {
                    CircularProgressIndicator()
                    Text("Connecting to your Mac… Keep its QR page open.")
                } else if (error != null) {
                    Text(requireNotNull(error), color = MaterialTheme.colorScheme.error)
                    Button(onClick = { error = null }) { Text("Scan again") }
                } else {
                    PairingQrCameraPreview(Modifier.fillMaxWidth().weight(1f), onCode = { code ->
                        val server = ConnectionRuntime.server
                        if (server == null) {
                            error = "The connection service is still starting. Go back and try again."
                        } else {
                            sending = true
                            request = server.pairUsingMacQr(code) { result ->
                                if (alive.get()) {
                                    sending = false
                                    if (result == null) onClose()
                                    else error = result
                                }
                            }
                        }
                    }, onError = { error = it })
                }
            }
        }
    }
}
