package dev.seamless.companion.camera

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import dev.seamless.companion.MainActivity
import dev.seamless.companion.connection.ConnectionRuntime

class CameraStreamService : Service() {
    private val thread = HandlerThread("SeamlessCamera")
    private lateinit var worker: Handler
    private var session: CameraEncodingSession? = null
    private var macID: String? = null

    override fun onCreate() {
        super.onCreate()
        thread.start()
        worker = Handler(thread.looper)
        activeService = this
    }

    private fun applyLiveControls(requestingMacID: String, controls: org.json.JSONObject) {
        worker.post {
            if (macID != requestingMacID) return@post
            try {
                val exposure = controls.optDouble("exposureEV", 0.0)
                val zoom = controls.optDouble("zoom", 1.0)
                require(exposure.isFinite() && zoom.isFinite())
                session?.updateControls(exposure.coerceIn(-3.0, 3.0), zoom.coerceIn(1.0, 4.0),
                    controls.optBoolean("torch"), controls.optString("whiteBalance", "auto").take(30))
            } catch (exception: Exception) {
                ConnectionRuntime.server?.reportCameraError(requestingMacID, exception.message ?: "Camera control failed")
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) { stopSelf(); return START_NOT_STICKY }
        if (session != null || macID != null) return START_NOT_STICKY
        try {
            showNotification()
            val target = intent?.getStringExtra("macID") ?: error("Camera request is missing")
            macID = target
            val facing = intent.getStringExtra("facing") ?: "back"
            val height = intent.getIntExtra("resolutionHeight", 1080)
            val rate = intent.getIntExtra("framesPerSecond", 30)
            worker.post {
                try {
                    val sink = ConnectionRuntime.server?.prepareCameraStream(target) ?: error("Mac is disconnected")
                    val cameraSession = CameraEncodingSession(this, worker, sink) { fail(it) }
                    session = cameraSession
                    cameraSession.start(facing, height, rate, intent.getDoubleExtra("exposureEV", 0.0), intent.getDoubleExtra("zoom", 1.0), intent.getBooleanExtra("torch", false), intent.getStringExtra("whiteBalance") ?: "auto")
                } catch (exception: Exception) { fail(exception) }
            }
        } catch (exception: Exception) { fail(exception) }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null
    override fun onDestroy() {
        if (activeService === this) activeService = null
        worker.post {
            try { session?.close() } catch (_: Exception) { } finally {
                macID?.let { ConnectionRuntime.server?.cameraCaptureEnded(it) }
                session = null
                thread.quitSafely()
            }
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun fail(exception: Exception) {
        ConnectionRuntime.update { it.copy(message = exception.message ?: "Camera capture failed") }
        macID?.let { ConnectionRuntime.server?.reportCameraError(it, exception.message ?: "Camera capture failed") }
        stopSelf()
    }

    @Suppress("DEPRECATION")
    private fun showNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        val channel = "camera_stream"
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(channel, "Camera sharing", NotificationManager.IMPORTANCE_LOW))
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, channel) else Notification.Builder(this)
        val open = PendingIntent.getActivity(this, 20, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 21, Intent(this, CameraStreamService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
        val notification = builder.setSmallIcon(android.R.drawable.ic_menu_camera).setContentTitle("Seamless camera sharing")
            .setContentText("Your paired Mac is receiving live camera video.").setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Stop camera", stop).build()).build()
        if (Build.VERSION.SDK_INT >= 30) {
            startForeground(3, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA)
        } else {
            startForeground(3, notification)
        }
    }

    companion object {
        const val ACTION_STOP = "dev.seamless.companion.STOP_CAMERA"
        @Volatile private var activeService: CameraStreamService? = null

        fun updateControls(macID: String, controls: org.json.JSONObject) {
            // A control packet may only affect an already approved, running service.
            activeService?.applyLiveControls(macID, controls)
        }
    }
}
