// Android feature implementation for phone ringer.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

package dev.seamless.companion.features

import android.content.Context
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Handler
import android.os.Looper

class PhoneRinger(private val context: Context) {
    private val handler = Handler(Looper.getMainLooper())
    private var ringtone: Ringtone? = null
    private val stopTask = Runnable { stop() }

    /** Plays a bounded alarm on the main thread and reports whether playback started. */
    fun ring(onResult: (Boolean) -> Unit) {
        handler.post {
            stop()
            try {
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
            ringtone = RingtoneManager.getRingtone(context, uri)
            ringtone?.audioAttributes = android.media.AudioAttributes.Builder()
                .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION).build()
            if (android.os.Build.VERSION.SDK_INT >= 28) ringtone?.isLooping = true
            if (android.os.Build.VERSION.SDK_INT >= 28) ringtone?.volume = 1.0f
            ringtone?.play()
            onResult(ringtone?.isPlaying == true)
            handler.postDelayed(stopTask, 15_000)
            } catch (_: Exception) {
                stop()
                onResult(false)
            }
        }
    }

    /** Stops the current operation and releases its active resources. */
    fun stop() {
        handler.removeCallbacks(stopTask)
        ringtone?.stop()
        ringtone = null
    }
}
