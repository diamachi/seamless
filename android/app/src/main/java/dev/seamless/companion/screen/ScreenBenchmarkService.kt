package dev.seamless.companion.screen

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.IBinder
import dev.seamless.companion.MainActivity
import dev.seamless.companion.connection.ConnectionRuntime

class ScreenBenchmarkService : Service() {
    private val workerThread = HandlerThread("SeamlessScreenEncoder")
    private lateinit var worker: Handler
    private var captureSession: ScreenCaptureSession? = null
    private var hasStarted = false
    private var activeTargetMacID: String? = null

    override fun onCreate() {
        super.onCreate()
        workerThread.start()
        worker = Handler(workerThread.looper)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }
        if (hasStarted) {
            return START_NOT_STICKY
        }
        if (intent == null) {
            stopSelf()
            return START_NOT_STICKY
        }
        hasStarted = true
        try {
            enterForeground()
            val projectionConsent = readProjectionConsent(intent)
                ?: error("Screen-sharing approval was missing. Start a new session from the app.")
            val requestedFramesPerSecond = intent.getIntExtra(EXTRA_FRAME_RATE, 60)
            val maximumDimension = intent.getIntExtra(EXTRA_MAXIMUM_DIMENSION, 1920)
            val targetMacID = intent.getStringExtra(EXTRA_TARGET_MAC)
            activeTargetMacID = targetMacID
            worker.post { startCapture(projectionConsent, requestedFramesPerSecond, maximumDimension, targetMacID) }
        } catch (exception: Exception) {
            finishWithFailure(exception)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        worker.post {
            try {
                captureSession?.close()
            } catch (exception: Exception) {
                BenchmarkState.publish(BenchmarkState.snapshot.value.copy(message = "Capture stopped: ${exception.message}"))
            } finally {
                captureSession = null
                activeTargetMacID?.let { ConnectionRuntime.server?.screenCaptureEnded(it) }
                val lastSnapshot = BenchmarkState.snapshot.value
                if (lastSnapshot.isRunning) {
                    BenchmarkState.publish(lastSnapshot.copy(isRunning = false, message = "Capture stopped. Results are retained until the next run."))
                } else {
                    BenchmarkState.publish(lastSnapshot.copy(isRunning = false))
                }
                workerThread.quitSafely()
            }
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun startCapture(consent: Intent, framesPerSecond: Int, maximumDimension: Int, targetMacID: String?) {
        try {
            val metrics = resources.displayMetrics
            val configuration = ScreenEncoderFactory.selectConfiguration(
                metrics.widthPixels, metrics.heightPixels, framesPerSecond, maximumDimension
            )
            val manager = getSystemService(MediaProjectionManager::class.java)
            val projection = manager.getMediaProjection(Activity.RESULT_OK, consent)
                ?: error("Android did not grant a screen capture session. Please approve a new session.")
            val session = ScreenCaptureSession(
                projection = projection,
                handler = worker,
                onProjectionStopped = { stopSelf() },
                onFailure = { finishWithFailure(it) },
                mediaSink = if (targetMacID != null) ConnectionRuntime.server?.prepareScreenStream(targetMacID)
                    ?: error("Mac connection is unavailable") else null
            )
            captureSession = session
            session.start(configuration, metrics.densityDpi)
        } catch (exception: Exception) {
            finishWithFailure(exception)
        }
    }

    private fun finishWithFailure(exception: Exception) {
        BenchmarkState.publish(BenchmarkState.snapshot.value.copy(
            isRunning = false, message = exception.message ?: "Screen capture failed"
        ))
        stopSelf()
    }

    private fun enterForeground() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "Screen performance test", NotificationManager.IMPORTANCE_LOW))
        }
        val stopIntent = Intent(this, ScreenBenchmarkService::class.java).setAction(ACTION_STOP)
        val stopAction = PendingIntent.getService(this, 1, stopIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val openIntent = PendingIntent.getActivity(this, 2, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }
        val notification = builder.setContentTitle("Seamless screen benchmark")
            .setContentText("Screen capture is active. Open Seamless to see whether this is a local benchmark or a Mac stream.")
            .setSmallIcon(android.R.drawable.ic_menu_view)
            .setContentIntent(openIntent)
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Stop", stopAction).build())
            .build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(1, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION)
        } else {
            startForeground(1, notification)
        }
    }

    @Suppress("DEPRECATION")
    private fun readProjectionConsent(intent: Intent): Intent? {
        if (Build.VERSION.SDK_INT >= 33) {
            return intent.getParcelableExtra(EXTRA_PROJECTION_CONSENT, Intent::class.java)
        }
        return intent.getParcelableExtra(EXTRA_PROJECTION_CONSENT)
    }

    companion object {
        const val EXTRA_PROJECTION_CONSENT = "projection_consent"
        const val EXTRA_FRAME_RATE = "frame_rate"
        const val EXTRA_MAXIMUM_DIMENSION = "maximum_dimension"
        const val EXTRA_TARGET_MAC = "target_mac"
        const val ACTION_STOP = "dev.seamless.companion.STOP_BENCHMARK"
        private const val CHANNEL_ID = "screen_benchmark"
    }
}
