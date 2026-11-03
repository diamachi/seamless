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

    fun ring() {
        handler.post {
            stop()
            val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
            ringtone = RingtoneManager.getRingtone(context, uri)
            ringtone?.play()
            handler.postDelayed(stopTask, 15_000)
        }
    }

    fun stop() {
        handler.removeCallbacks(stopTask)
        ringtone?.stop()
        ringtone = null
    }
}
