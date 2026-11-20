// Keeps the phone connection alive independently of the Activity task. The service owns its server instance, foreground notification and connection power lease.

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
    @Volatile private var ownedServer: PhoneServer? = null
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var powerLease: ConnectionPowerLease

    /** Initializes Android-owned resources when this component is created. */
    override fun onCreate() {
        super.onCreate()
        powerLease = ConnectionPowerLease(this)
        serviceScope.launch {
            var previousNames: List<String>? = null
            ConnectionRuntime.state.collect { state ->
                powerLease.setConnected(state.connectedMacIDs.isNotEmpty())
                if (previousNames != state.connectedMacs) {
                    previousNames = state.connectedMacs
                    if (ownedServer != null && !isDestroyed) showForegroundNotification()
                }
            }
        }
    }

    /** Handles foreground-service commands and selects the service restart policy. */
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
                var server = ownedServer
                if (intent?.action == ACTION_RECONNECT && ConnectionRuntime.state.value.connectedMacIDs.isEmpty()) {
                    server?.close()
                    if (ConnectionRuntime.server === server) ConnectionRuntime.server = null
                    ownedServer = null
                    server = null
                }
                if (server == null) {
                    server = PhoneServer(applicationContext)
                    ownedServer = server
                    ConnectionRuntime.server = server
                    server.start(reconnectRequested = intent?.action == ACTION_RECONNECT)
                } else if (intent?.action == ACTION_RECONNECT) {
                    server.requestReconnect()
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

    /** Implements the Android binding contract for this service. */
    override fun onBind(intent: Intent?): IBinder? = null

    /// Retains service-owned sessions when the recent-app task is dismissed; manufacturer process killing remains outside this callback’s control.
    override fun onTaskRemoved(rootIntent: Intent?) {
        // Dismissing the UI task must not close the service-owned authenticated sockets.
        dev.seamless.companion.features.DebugEvents.record("Android task removed; connection service retained")
        if (!isDestroyed && ownedServer != null) showForegroundNotification()
        super.onTaskRemoved(rootIntent)
    }

    /** Releases this component’s resources when Android destroys it; ownership checks protect replacement sessions. */
    override fun onDestroy() {
        dev.seamless.companion.features.DebugEvents.record("Android connection service destroyed")
        isDestroyed = true
        serviceScope.cancel()
        powerLease.close()
        worker.execute {
            try {
                val server = ownedServer
                server?.close()
                if (ConnectionRuntime.server === server) ConnectionRuntime.server = null
            } finally {
                ownedServer = null
                worker.shutdown()
            }
        }
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    /** Updates the persistent connection notification with current peer names and a stop action. */
    @Suppress("DEPRECATION")
    /** Handles show foreground notification callback by translating the native window event into the owning app action. */
    private fun showForegroundNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(CHANNEL, "Mac connection", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(this, 10, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        val stop = PendingIntent.getService(this, 11, Intent(this, ConnectionService::class.java).setAction(ACTION_STOP), PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        val names = ConnectionRuntime.state.value.connectedMacs
        val title = if (names.isEmpty()) "Waiting for your Mac" else if (names.size == 1) "Connected to " + names.first() else "Connected to " + names.size + " Macs"
        val detail = if (names.isEmpty()) "Open Seamless on your paired Mac to connect." else names.joinToString(", ") + " · Tap to manage"
        val notification = builder.setSmallIcon(android.R.drawable.ic_menu_share).setContentTitle(title)
            .setContentText(detail).setOnlyAlertOnce(true).setContentIntent(open).setOngoing(true)
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
        /** Posts the phone-side approval alert for a pending screen or camera request. */
        fun notifyCaptureRequest(context: android.content.Context, camera: Boolean = false) {
            notifyRequest(context, if (camera) "Your Mac requested the camera" else "Your Mac requested screen sharing",
                if (camera) "Tap to review and approve camera sharing." else "Tap to open Android’s screen-sharing consent.", 12, if (camera) "camera" else "screen")
        }

        /** Performs notify file request for connection service. */
        fun notifyFileRequest(context: android.content.Context, name: String) {
            notifyRequest(context, "File from your Mac", "Tap to accept $name", 13, "file")
        }

        /** Performs notify contacts request for connection service. */
        fun notifyContactsRequest(context: android.content.Context, macName: String) {
            notifyRequest(context, "Share phone contacts?", "$macName requested contacts for the call picker", 15, "contacts")
        }

        /** Performs notify pairing request for connection service. */
        fun notifyPairingRequest(context: android.content.Context, macName: String) {
            notifyRequest(context, "Trust this Mac?", "Review the pairing request from $macName", 14, "pairing")
        }

        /** Posts an actionable sharing request using the registered notification channel. */
        private fun notifyRequest(context: android.content.Context, title: String, message: String, identifier: Int, kind: String) {
            val manager = context.getSystemService(NotificationManager::class.java)
            // A new channel keeps previously low-importance service notifications separate.
            val channel = dev.seamless.companion.features.AlertChannels.SHARING_REQUESTS
            if (Build.VERSION.SDK_INT >= 26) {
                dev.seamless.companion.features.AlertChannels.register(context, channel, "Sharing requests", NotificationManager.IMPORTANCE_HIGH)
            }
            val open = PendingIntent.getActivity(context, identifier, Intent(context, MainActivity::class.java).putExtra("sharing_request_kind", kind), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
            val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(context, channel) else Notification.Builder(context)
            try {
                manager.notify(identifier, builder.setSmallIcon(android.R.drawable.ic_menu_share)
                    .setContentTitle(title).setContentText(message).setContentIntent(open)
                    .setCategory(Notification.CATEGORY_EVENT).setPriority(Notification.PRIORITY_HIGH)
                    .setSound(dev.seamless.companion.features.AlertChannels.sound(context))
                    .setDefaults(Notification.DEFAULT_VIBRATE).setVisibility(Notification.VISIBILITY_PRIVATE)
                    .addAction(Notification.Action.Builder(null, "Review & approve", open).build())
                    .setAutoCancel(true).build())
            } catch (_: SecurityException) {
                // Revoked display permission cannot interrupt the connection or transfer.
            }
        }
        private const val CHANNEL = "mac_connection"
    }
}
