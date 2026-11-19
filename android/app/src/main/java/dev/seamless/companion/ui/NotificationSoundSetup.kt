package dev.seamless.companion.ui

import android.app.Notification
import android.app.NotificationManager
import android.content.Intent
import android.os.Build
import android.provider.Settings
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import dev.seamless.companion.features.AlertChannels

@Composable
internal fun NotificationSoundSetup() {
    val context = LocalContext.current
    val manager = context.getSystemService(NotificationManager::class.java)
    var feedback by remember { mutableStateOf("") }
    val permission = androidx.activity.compose.rememberLauncherForActivityResult(
        androidx.activity.result.contract.ActivityResultContracts.RequestPermission()
    ) { allowed -> feedback = if (allowed) "Notifications allowed. Tap a test again." else "Notifications blocked. Open app notification settings to allow alerts." }
    var revision by remember { mutableIntStateOf(0) }
    LifecycleEventEffect(Lifecycle.Event.ON_RESUME) { revision += 1 }
    val channels = listOf(
        "received_text" to "Received text",
        AlertChannels.SHARING_REQUESTS to "Sharing requests",
        AlertChannels.TRANSFER_RESULTS to "Transfer results",
        "sharing_test" to "Notification test"
    )
    LaunchedEffect(Unit) { AlertChannels.registerAll(context); revision += 1 }
    CompanionCard("Check alert sounds") {
        Text("These tests appear on this phone. Use Test phone → Mac below to check mirroring.", style = androidx.compose.material3.MaterialTheme.typography.bodySmall)
        if (!manager.areNotificationsEnabled()) {
            TextButton(onClick = {
                if (Build.VERSION.SDK_INT >= 33) permission.launch(android.Manifest.permission.POST_NOTIFICATIONS)
                else context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:" + context.packageName)))
            }) { Text("Allow notifications") }
        }
        if (feedback.isNotEmpty()) Text(feedback)

        for ((identifier, title) in channels) {
            val channel = remember(revision, identifier) {
                if (Build.VERSION.SDK_INT >= 26) manager.getNotificationChannel(identifier) else null
            }
            val state = if (!manager.areNotificationsEnabled()) "App notifications blocked"
                else if (Build.VERSION.SDK_INT >= 26 && channel?.importance == NotificationManager.IMPORTANCE_NONE) "Blocked"
                else if (Build.VERSION.SDK_INT >= 26 && (channel?.sound == null || (channel?.importance ?: 0) < NotificationManager.IMPORTANCE_DEFAULT)) "Silent"
                else "Sound configured"
            Text(title + " · " + state)
            TextButton(onClick = {
                if (Build.VERSION.SDK_INT >= 26) {
                    context.startActivity(Intent(Settings.ACTION_CHANNEL_NOTIFICATION_SETTINGS)
                        .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        .putExtra(Settings.EXTRA_CHANNEL_ID, identifier))
                } else {
                    context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, android.net.Uri.parse("package:" + context.packageName)))
                }
            }) { Text("Review sound") }
            TextButton(onClick = {
                if (!manager.areNotificationsEnabled()) {
                    feedback = "Notifications are blocked. Allow notifications first."
                    return@TextButton
                }
                val current = if (Build.VERSION.SDK_INT >= 26) manager.getNotificationChannel(identifier) else null
                if (Build.VERSION.SDK_INT >= 26 && current?.importance == NotificationManager.IMPORTANCE_NONE) {
                    feedback = title + " is blocked. Tap Review sound."
                    return@TextButton
                }
                val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, identifier)
                    else Notification.Builder(context).setSound(AlertChannels.sound(context))
                manager.cancel(identifier.hashCode())
                manager.notify(identifier.hashCode(), builder.setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle(title + " test").setContentText("Check that you heard this alert.").setAutoCancel(true).build())
                feedback = "Posted " + title + ". Check this phone’s notification shade. If silent, review sound, volume and Do Not Disturb."
            }) { Text("Play test notification") }
        }
        TextButton(onClick = {
            if (!manager.areNotificationsEnabled()) feedback = "Allow notifications first."
            else {
                dev.seamless.companion.features.TestNotification.post(context)
                feedback = "Posted mirroring test. On Mac, allow Seamless in Choose apps and ensure Android notification access is enabled."
            }
        }) { Text("Test phone → Mac") }
        Text("Connection, camera and screen-in-use indicators stay quiet. Sound also depends on notification volume and Do Not Disturb.")
    }
}
