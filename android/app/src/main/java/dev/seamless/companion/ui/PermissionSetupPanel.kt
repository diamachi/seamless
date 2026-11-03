package dev.seamless.companion.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.Button
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import dev.seamless.companion.connection.ConnectionRuntime
import dev.seamless.companion.features.CompanionPermissions

@Composable
internal fun PermissionSetupPanel() {
    val context = LocalContext.current
    var access by remember { mutableStateOf(CompanionPermissions.read(context)) }
    val refresh = { access = CompanionPermissions.read(context) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { refresh() }
    val requestCamera = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { refresh() }
    val requestNotifications = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { refresh() }
    CompanionCard("Choose your features") {
        Text("Set up once, then use your chosen features. Setup never starts your camera or screen sharing.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        RecommendedAccessFlow(onChanged = refresh)
        PermissionRow("Camera", "Live camera for your Mac", access.camera) {
            val requested = context.getSharedPreferences("onboarding", Context.MODE_PRIVATE).getBoolean("camera_requested", false)
            val canExplain = (context as? android.app.Activity)?.shouldShowRequestPermissionRationale(Manifest.permission.CAMERA) == true
            if (access.camera || (requested && !canExplain)) {
                openSetupSettings(context, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + context.packageName)))
            } else {
                context.getSharedPreferences("onboarding", Context.MODE_PRIVATE).edit().putBoolean("camera_requested", true).apply()
                requestCamera.launch(Manifest.permission.CAMERA)
            }
        }
        HorizontalDivider()
        PermissionRow("Notifications", "Connection and sharing alerts", access.notifications) {
            if (Build.VERSION.SDK_INT >= 33 && !access.notifications) {
                requestNotifications.launch(Manifest.permission.POST_NOTIFICATIONS)
            } else {
                openSetupSettings(context, Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName))
            }
        }
        HorizontalDivider()
        PermissionRow("Notification sharing", "Read and relay selected app notifications", access.notificationSharing) {
            openSetupSettings(context, Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
        }
        HorizontalDivider()
        PermissionRow("Phone control", "Optional taps and swipes during approved sharing", access.phoneControl) {
            openSetupSettings(context, Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS))
        }
        HorizontalDivider()
        PermissionRow("Background connection", "Allow background connection; active paired sessions keep the CPU and Wi-Fi awake", access.battery) {
            openSetupSettings(context, Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
        }
    }
    AutomaticDownloadsSetupCard()
    StorageSetupCard(access.storage, onChanged = refresh)
    CompanionCard("Screen sharing & calls") {
        Text("Android asks for screen-sharing consent for every new session. This cannot be pre-approved during setup.")
        Text("Bluetooth call pairing is done in the phone and Mac Bluetooth settings. Seamless does not need Android microphone or contacts access for its Mac HFP backend.", color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun PermissionRow(title: String, purpose: String, allowed: Boolean, action: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.titleSmall)
            Text(purpose, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(if (allowed) "Allowed" else "Not allowed", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.primary)
        }
        OutlinedButton(onClick = action) { Text(if (allowed) "Review" else "Set up") }
    }
}

@Composable
private fun StorageSetupCard(allowed: Boolean, onChanged: () -> Unit) {
    val context = LocalContext.current
    val chooseFolder = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        if (uri != null) {
            try {
                context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                context.getSharedPreferences("shared_storage", Context.MODE_PRIVATE).edit().putString("tree", uri.toString()).apply()
            } catch (_: SecurityException) {
                ConnectionRuntime.update { it.copy(message = "The selected folder could not be shared") }
            }
            onChanged()
        }
    }
    val chooseMedia = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        val selected = uris.take(1000)
        for (uri in selected) {
            try { context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
            catch (_: SecurityException) { }
        }
        context.getSharedPreferences("shared_storage", Context.MODE_PRIVATE).edit().putStringSet("media", selected.map { it.toString() }.toSet()).apply()
        onChanged()
    }
    CompanionCard("Storage & photos") {
        Text(if (allowed) "Shared access is available" else "No storage is shared yet", color = MaterialTheme.colorScheme.primary)
        Text("Share your phone's shared storage, or choose specific folders and media. Private app data remains protected.", style = MaterialTheme.typography.bodySmall)
        if (Build.VERSION.SDK_INT >= 30) {
            Button(onClick = {
                context.getSharedPreferences("shared_storage", Context.MODE_PRIVATE).edit().putBoolean("full_access_enabled", true).apply()
                openSetupSettings(context, Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:" + context.packageName)))
            }) { Text("Review all-files access") }
        }
        OutlinedButton(onClick = { chooseFolder.launch(null) }) { Text("Choose a shared folder") }
        OutlinedButton(onClick = { chooseMedia.launch(arrayOf("image/*", "video/*")) }) { Text("Choose photos and videos") }
        TextButton(onClick = {
            context.getSharedPreferences("shared_storage", Context.MODE_PRIVATE).edit().clear().apply()
            for (permission in context.contentResolver.persistedUriPermissions) {
                try { context.contentResolver.releasePersistableUriPermission(permission.uri, Intent.FLAG_GRANT_READ_URI_PERMISSION) }
                catch (_: SecurityException) { }
            }
            ConnectionRuntime.server?.revokeBrowserAccess()
            onChanged()
        }) { Text("Stop sharing storage") }
    }
}

internal fun openSetupSettings(context: Context, intent: Intent) {
    try { context.startActivity(intent) }
    catch (_: android.content.ActivityNotFoundException) {
        context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + context.packageName)))
    }
}

@Composable
private fun AutomaticDownloadsSetupCard() {
    val context = LocalContext.current
    val policies = context.getSharedPreferences("phone_policies", Context.MODE_PRIVATE)
    var enabled by remember { mutableStateOf(policies.getBoolean("automatic_downloads", false)) }
    CompanionCard("Automatic Downloads") {
        Text("Allow paired Macs to send files directly to this phone’s Downloads folder. Android 10+ needs no storage permission to save files created by Seamless. Older versions ask where to save.", style = MaterialTheme.typography.bodySmall)
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("Receive automatically")
            androidx.compose.material3.Switch(checked = enabled, onCheckedChange = { allowed ->
                enabled = allowed
                val editor = policies.edit().putBoolean("automatic_downloads", allowed)
                val identities = context.getSharedPreferences("connection_identity", Context.MODE_PRIVATE)
                for (key in identities.all.keys) {
                    if (key.startsWith("peer.")) editor.putBoolean("file_auto.${key.removePrefix("peer.")}", allowed)
                }
                for (macID in ConnectionRuntime.state.value.connectedMacIDs) editor.putBoolean("file_auto.$macID", allowed)
                editor.apply()
            })
        }
        Text("On the Mac, enable automatic Downloads in its setup guide too. You can change receiving choices later in Settings.", color = MaterialTheme.colorScheme.onSurfaceVariant, style = MaterialTheme.typography.bodySmall)
    }
}
