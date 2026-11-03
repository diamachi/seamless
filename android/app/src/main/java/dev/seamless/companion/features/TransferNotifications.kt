package dev.seamless.companion.features

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

/** Live progress stays in the app; OS notifications announce terminal results only. */
internal class TransferNotifications(private val context: Context) {
    private val manager = context.getSystemService(NotificationManager::class.java)

    init {
        if (Build.VERSION.SDK_INT >= 26) {
            manager.deleteNotificationChannel("transfer-progress")
            AlertChannels.register(context, AlertChannels.TRANSFER_RESULTS, "Transfer results", NotificationManager.IMPORTANCE_DEFAULT)
        }
    }

    fun finish(id: String, name: String, result: String) {
        manager.cancel(id, 1)
        post(id, name, result)
    }

    private fun post(id: String, name: String, text: String) {
        if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val notification = NotificationCompat.Builder(context, AlertChannels.TRANSFER_RESULTS)
            .setSmallIcon(android.R.drawable.stat_sys_upload_done)
            .setContentTitle(name).setContentText(text)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setSound(AlertChannels.sound(context))
            .setAutoCancel(true)
        try {
            manager.notify(id, 2, notification.build())
        } catch (_: SecurityException) {
            // A revoked notification grant must never interrupt a file transfer.
        }
    }
}
