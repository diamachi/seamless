package dev.seamless.companion.features

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build

internal object AlertChannels {
    const val SHARING_REQUESTS = "sharing_requests_v3"
    const val TRANSFER_RESULTS = "transfer_results_v2"

    fun sound(context: Context): Uri {
        return Uri.parse("android.resource://${context.packageName}/raw/seamless_notification")
    }

    fun register(context: Context, identifier: String, title: String, importance: Int) {
        if (Build.VERSION.SDK_INT < 26) return
        val channel = NotificationChannel(identifier, title, importance)
        val audio = AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
        // A bundled tone does not depend on an unset device-wide default ringtone.
        channel.setSound(sound(context), audio)
        channel.enableVibration(true)
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }
}
