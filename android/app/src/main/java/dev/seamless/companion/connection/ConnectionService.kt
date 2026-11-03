package dev.seamless.companion.connection

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import dev.seamless.companion.MainActivity
import java.util.concurrent.Executors
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class ConnectionService : Service() {
    private val worker = Executors.newSingleThreadExecutor()
    @Volatile private var isDestroyed = false
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var powerLease: ConnectionPowerLease

    override fun onCreate() {
        super.onCreate()
        powerLease = ConnectionPowerLease(this)
        serviceScope.launch {
            ConnectionRuntime.state.collect { state -> powerLease.setConnected(state.connectedMacIDs.isNotEmpty()) }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            getSharedPreferences("connection_settings", MODE_PRIVATE).edit().putBoolean("reconnect_on_launch", false).apply()
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent == null && !getSharedPreferences("connection_settings", MODE_PRIVATE).getBoolean("reconnect_on_launch", true)) {
            stopSelf()
            return START_NOT_STICKY
        }
        showForegroundNotification()
        worker.execute {
            try {
                if (isDestroyed) return@execute
                var server = ConnectionRuntime.server
                if (intent?.action == ACTION_RECONNECT && ConnectionRuntime.state.value.connectedMacIDs.isEmpty()) {
                    server?.close()
                    ConnectionRuntime.server = null
                    server = null
                }
                if (server == null) {
                    server = PhoneServer(applicationContext)
                    ConnectionRuntime.server = server
                    server.start(reconnectRequested = intent?.action == ACTION_RECONNECT)
                }
                if (intent?.action == ACTION_PAIR) {
                    try {
                        server.createInvitation()
                    } catch (exception: Exception) {
                        ConnectionRuntime.update { it.copy(isCreatingPairingCode = false, pairingError = exception.message ?: "Could not create pairing code") }
                    }
                }
            } catch (exception: Exception) {
                ConnectionRuntime.update { it.copy(isCreatingPairingCode = false, pairingError = exception.message ?: "Could not create pairing QR", message = exception.message ?: "Connection service could not start") }
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        isDestroyed = true
        serviceScope.cancel()
        powerLease.close()
        worker.execute {
            try {
                ConnectionRuntime.server?.close()
            } finally {
                ConnectionRuntime.server = null
                worker.shutdown()
            }
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun showForegroundNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Mac connection", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(this, 10, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 11, Intent(this, ConnectionService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val notification = builder.setSmallIcon(android.R.drawable.ic_menu_share).setContentTitle("Seamless is ready for your Mac")
            .setContentText("Only paired Macs can connect. Tap to manage.").setContentIntent(open).setOngoing(true)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build()).build()
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(2, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
        } else {
            startForeground(2, notification)
        }
    }

    companion object {
        const val ACTION_RECONNECT = "dev.seamless.companion.RECONNECT"
        const val ACTION_PAIR = "dev.seamless.companion.CREATE_INVITATION"
        const val ACTION_STOP = "dev.seamless.companion.STOP_CONNECTION"
        fun notifyCaptureRequest(context: android.content.Context, camera: Boolean = false) {
            notifyRequest(context, if (camera) "Your Mac requested the camera" else "Your Mac requested screen sharing",
                if (camera) "Tap to review and approve camera sharing." else "Tap to open Android’s screen-sharing consent.", 12)
        }

        fun notifyFileRequest(context: android.content.Context, name: String) {
            notifyRequest(context, "File from your Mac", "Tap to accept $name", 13)
        }

        private fun notifyRequest(context: android.content.Context, title: String, message: String, identifier: Int) {
            if (ConnectionRuntime.isActivityVisible) return
            val manager = context.getSystemService(NotificationManager::class.java)
            // A new channel keeps previously low-importance service notifications separate.
            val channel = "sharing_requests_v2"
            if (Build.VERSION.SDK_INT >= 26) {
                manager.createNotificationChannel(NotificationChannel(channel, "Sharing requests", NotificationManager.IMPORTANCE_HIGH))
            }
            val open = PendingIntent.getActivity(context, identifier, Intent(context, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel) else Notification.Builder(context)
            try {
                manager.notify(identifier, builder.setSmallIcon(android.R.drawable.ic_menu_share)
                    .setContentTitle(title).setContentText(message).setContentIntent(open)
                    .setCategory(Notification.CATEGORY_EVENT).setPriority(Notification.PRIORITY_HIGH)
                    .setDefaults(Notification.DEFAULT_ALL).setAutoCancel(true).build())
            } catch (_: SecurityException) {
                // Revoked display permission cannot interrupt the connection or transfer.
            }
        }
        private const val CHANNEL = "mac_connection"
    }
}
