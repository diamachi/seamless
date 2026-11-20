// Android feature implementation for received text notification.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

package dev.seamless.companion.features

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.app.Activity
import dev.seamless.companion.connection.ConnectionRuntime

object ReceivedTextNotification {
    /** Performs show for received text notification. */
    fun show(context: Context, text: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        if (android.os.Build.VERSION.SDK_INT >= 26) {
            val channel = NotificationChannel("received_text", "Received text", NotificationManager.IMPORTANCE_HIGH)
            channel.setSound(AlertChannels.sound(context), android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION).build())
            manager.createNotificationChannel(channel)
        }
        val intent = Intent(context, CopyReceivedTextActivity::class.java).putExtra("text", text)
        val action = PendingIntent.getActivity(context, 410, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (android.os.Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(context, "received_text")
        } else {
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
        val notification = builder
            .setSmallIcon(android.R.drawable.ic_menu_edit)
            .setContentTitle("Text from your Mac")
            .setContentText(text.take(160))
            .setContentIntent(action)
            .addAction(Notification.Action.Builder(null, "Copy", action).build())
            .setAutoCancel(true)
            .build()
        manager.notify(410, notification)
    }
}

class CopyReceivedTextActivity : Activity() {
    /** Initializes Android-owned resources when this component is created. */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val text = intent.getStringExtra("text")
        if (text != null) {
            getSystemService(ClipboardManager::class.java).setPrimaryClip(ClipData.newPlainText("From Mac", text))
            getSystemService(NotificationManager::class.java).cancel(410)
        }
        finish()
    }
}
