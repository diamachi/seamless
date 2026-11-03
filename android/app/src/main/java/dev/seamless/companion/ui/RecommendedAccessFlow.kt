package dev.seamless.companion.ui

import android.Manifest
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import dev.seamless.companion.features.CompanionPermissions
import dev.seamless.companion.features.SetupAccessPolicy

private data class AccessStep(val title: String, val purpose: String)
private val accessSteps = listOf(
    AccessStep("Notification sharing", "Allow Seamless to read and relay the app notifications you select on your Mac."),
    AccessStep("Phone control", "Enable Seamless in Accessibility only if you want Mac taps and swipes during an approved screen session."),
    AccessStep("Shared storage", "Enable shared-storage access for Mac browsing. Private app data remains protected. You can skip and choose individual folders instead."),
    AccessStep("Background connection", "Review battery restrictions for Seamless so Android can keep the connection available. This step is optional.")
)

@Composable
internal fun RecommendedAccessFlow(onChanged: () -> Unit) {
    val context = LocalContext.current
    var stage by rememberSaveable { mutableIntStateOf(-1) }
    val next = { start: Int -> nextMissingStep(context, start) }
    val settings = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        onChanged()
        if (stage in accessSteps.indices && SetupAccessPolicy.isAllowed(CompanionPermissions.read(context), stage)) stage = next(stage + 1)
    }
    val runtime = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { onChanged(); stage = next(0) }
    Button(onClick = {
        val access = CompanionPermissions.read(context)
        val permissions = mutableListOf<String>()
        if (!access.camera) permissions.add(Manifest.permission.CAMERA)
        if (Build.VERSION.SDK_INT >= 33 && !access.notifications) permissions.add(Manifest.permission.POST_NOTIFICATIONS)
        if (permissions.isEmpty()) stage = next(0)
        else runtime.launch(permissions.toTypedArray())
    }) { Text("Set up recommended access") }
    Text("Requests camera and notification prompts, then guides you through remaining special access. Already allowed steps are skipped. You can skip any optional feature.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    if (stage in accessSteps.indices) {
        val step = accessSteps[stage]
        AlertDialog(onDismissRequest = { stage = -1 }, title = { Text(step.title) },
            text = { Text(step.purpose + "\n\nAndroid requires you to confirm this in system settings. Return here afterward. If you leave it off, choose Skip.") },
            confirmButton = { TextButton(onClick = {
                val intent = accessIntent(context, stage)
                if (intent != null) {
                    if (stage == 2) context.getSharedPreferences("shared_storage", Context.MODE_PRIVATE).edit().putBoolean("full_access_enabled", true).apply()
                    try { settings.launch(intent) }
                    catch (_: android.content.ActivityNotFoundException) { openSetupSettings(context, Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:" + context.packageName))) }
                } else stage = next(stage + 1)
            }) { Text("Open settings") } },
            dismissButton = { TextButton(onClick = { stage = next(stage + 1) }) { Text("Skip") } })
    }
    if (stage == accessSteps.size) {
        AlertDialog(onDismissRequest = { stage = -1 }, title = { Text("Access review finished") },
            text = { Text("The list below reflects what Android actually allowed. Skipped features can be configured here later. Screen sharing still needs consent for each new session.") },
            confirmButton = { TextButton(onClick = { stage = -1 }) { Text("Done") } })
    }
}

private fun nextMissingStep(context: Context, start: Int): Int {
    return SetupAccessPolicy.nextMissingStep(CompanionPermissions.read(context), start)
}

private fun accessIntent(context: Context, step: Int): Intent? = when (step) {
    0 -> Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
    1 -> Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
    2 -> if (Build.VERSION.SDK_INT >= 30) Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION, Uri.parse("package:" + context.packageName)) else null
    3 -> Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
    else -> null
}
