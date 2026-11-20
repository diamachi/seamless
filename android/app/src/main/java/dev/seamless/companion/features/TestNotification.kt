// Android feature implementation for test notification.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

package dev.seamless.companion.features

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

object TestNotification {
    /** Performs post for test notification. */
    @Suppress("DEPRECATION")
    /** Handles post callback by translating the native window event into the owning app action. */
    fun post(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        val channelID = "sharing_test"
        if (Build.VERSION.SDK_INT >= 26) {
            AlertChannels.register(context, channelID, "Notification test", NotificationManager.IMPORTANCE_DEFAULT)
        }
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channelID) else Notification.Builder(context)
        manager.notify(100, builder.setSmallIcon(android.R.drawable.ic_dialog_info).setContentTitle("Seamless test notification")
            .setSound(AlertChannels.sound(context)).setContentText("This notification tests your selected-app filter. No message was sent to anyone.").build())
    }
}
