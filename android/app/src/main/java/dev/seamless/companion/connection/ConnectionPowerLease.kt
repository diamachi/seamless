// Android connection infrastructure for connection power lease.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

package dev.seamless.companion.connection

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager

/** Screen-off continuity is needed only while a paired Mac has an active session. */
internal class ConnectionPowerLease(context: Context) : AutoCloseable {
    private val handler = Handler(Looper.getMainLooper())
    private val wakeLock = context.getSystemService(PowerManager::class.java)
        .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Seamless:PairedConnection")
    @Suppress("DEPRECATION")
    private val wifiLock = context.applicationContext.getSystemService(WifiManager::class.java)
        .createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "Seamless:PairedConnection")
    private var connected = false
    private val renewal = object : Runnable {
        /** Runs the supplied work through this component’s execution or process interface. */
        override fun run() {
            if (!connected) return
            // A bounded lease prevents a stuck owner from holding the CPU indefinitely.
            wakeLock.acquire(10 * 60 * 1000L)
            handler.postDelayed(this, 5 * 60 * 1000L)
        }
    }

    init {
        wakeLock.setReferenceCounted(false)
        wifiLock.setReferenceCounted(false)
    }

    /** Performs set connected for connection power lease. */
    fun setConnected(value: Boolean) {
        if (connected == value) return
        connected = value
        if (value) {
            wifiLock.acquire()
            renewal.run()
        } else {
            release()
        }
    }

    /** Performs release for connection power lease. */
    private fun release() {
        handler.removeCallbacks(renewal)
        if (wakeLock.isHeld) wakeLock.release()
        if (wifiLock.isHeld) wifiLock.release()
    }

    /** Closes owned resources so sockets, buffers and pending work do not outlive their session. */
    override fun close() {
        connected = false
        release()
    }
}
