package dev.seamless.companion

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.enableEdgeToEdge
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import dev.seamless.companion.connection.ConnectionRuntime
import dev.seamless.companion.screen.BenchmarkState
import dev.seamless.companion.screen.ScreenBenchmarkService

class MainActivity : ComponentActivity() {
    private val preferences by lazy { getSharedPreferences("seamless_preferences", MODE_PRIVATE) }
    private var lastCameraRequestID: String? = null
    private var lastScreenRequestID: String? = null
    private val clipboardListener = android.content.ClipboardManager.OnPrimaryClipChangedListener {
        if (ConnectionRuntime.isActivityVisible && preferences.getBoolean("foreground_clipboard_sync", false) && ConnectionRuntime.state.value.connectedMacs.size == 1) {
            val manager = getSystemService(android.content.ClipboardManager::class.java)
            val text = manager.primaryClip?.getItemAt(0)?.coerceToText(this)?.toString().orEmpty()
            if (text.isNotEmpty() && text != ConnectionRuntime.state.value.incomingClipboard) ConnectionRuntime.server?.sendClipboard(text.take(32_000))
        }
    }
    private var targetScreenMacID: String? = null
    private var targetScreenFrameRate = 60
    private var pendingCameraRequest: dev.seamless.companion.connection.CompanionConnectionState? = null
    private val cameraPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        if (allowed) startCameraStream()
        else ConnectionRuntime.update { it.copy(message = "Camera permission is needed for live camera sharing") }
    }
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        launchScreenConsent()
    }
    private val screenConsent = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val consent = result.data
        if (result.resultCode == Activity.RESULT_OK && consent != null) {
            startScreenBenchmark(consent)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (savedInstanceState == null) receiveSharedText(intent)
        setContent {
            dev.seamless.companion.ui.CompanionAppRoot(
                initialFrameRate = preferences.getInt("screen_frame_rate", 60),
                initialMaximumDimension = preferences.getInt("screen_maximum_dimension", 1920),
                onProfileChanged = { frameRate, maximumDimension ->
                    preferences.edit().putInt("screen_frame_rate", frameRate)
                        .putInt("screen_maximum_dimension", maximumDimension).apply()
                    configureDisplayFrameRate(frameRate)
                },
                onStartBenchmark = { targetScreenMacID = null; requestScreenCapture() },
                onStopBenchmark = { stopService(Intent(this@MainActivity, ScreenBenchmarkService::class.java)) },
                onStartScreen = { approveRequestedScreen() },
                onStartCamera = { approveRequestedCamera() },
                onRemoteScreen = { maybeStartRemoteCapture() },
                onRemoteCamera = { maybeStartRemoteCamera() }
            )
        }
    }

    private fun approveRequestedScreen() {
        val connection = ConnectionRuntime.state.value
        targetScreenMacID = connection.screenRequestedBy
        targetScreenFrameRate = connection.screenRequestedFramesPerSecond
        requestScreenCapture()
    }

    private fun approveRequestedCamera() {
        pendingCameraRequest = ConnectionRuntime.state.value
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) startCameraStream()
        else cameraPermission.launch(Manifest.permission.CAMERA)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveSharedText(intent)
    }

    private fun receiveSharedText(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND || intent?.action == Intent.ACTION_SEND_MULTIPLE) {
            val uris = mutableListOf<android.net.Uri>()
            if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
                @Suppress("DEPRECATION")
                val shared = intent.getParcelableArrayListExtra<android.net.Uri>(Intent.EXTRA_STREAM)
                uris.addAll(shared.orEmpty())
            } else {
                @Suppress("DEPRECATION")
                val shared = intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
                if (shared != null) uris.add(shared)
            }
            val clipData = intent.clipData
            if (clipData != null) {
                for (index in 0 until clipData.itemCount) {
                    clipData.getItemAt(index).uri?.let { uris.add(it) }
                }
            }
            val files = uris.filter { it.scheme == "content" }.distinct().map { it.toString() }
            if (files.isNotEmpty()) ConnectionRuntime.update { it.copy(sharedFilesToSend = files) }
        }
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.take(32_000) ?: return
            ConnectionRuntime.update { it.copy(sharedTextToSend = text) }
        }
    }

    override fun onStart() {
        super.onStart()
        ConnectionRuntime.isActivityVisible = true
        getSystemService(android.content.ClipboardManager::class.java).addPrimaryClipChangedListener(clipboardListener)
        val hasSavedMac = getSharedPreferences("connection_identity", MODE_PRIVATE).all.keys.any { it.startsWith("peer.") }
        val reconnectOnLaunch = getSharedPreferences("connection_settings", MODE_PRIVATE).getBoolean("reconnect_on_launch", true)
        if (hasSavedMac && reconnectOnLaunch && ConnectionRuntime.server == null) {
            val service = Intent(this, dev.seamless.companion.connection.ConnectionService::class.java)
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(service) else startService(service)
        }
    }

    override fun onStop() {
        getSystemService(android.content.ClipboardManager::class.java).removePrimaryClipChangedListener(clipboardListener)
        ConnectionRuntime.isActivityVisible = false
        super.onStop()
    }

    override fun onResume() {
        super.onResume()
        maybeStartRemoteCapture()
        maybeStartRemoteCamera()
    }

    private fun maybeStartRemoteCamera() {
        if (!ConnectionRuntime.isActivityVisible) return
        val request = ConnectionRuntime.state.value
        val requestID = request.cameraRequestID ?: return
        val macID = request.cameraRequestedBy ?: return
        if (requestID == lastCameraRequestID) return
        if (!getSharedPreferences("phone_policies", MODE_PRIVATE).getBoolean("camera_auto.$macID", false)) return
        lastCameraRequestID = requestID
        pendingCameraRequest = request
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) startCameraStream()
        else cameraPermission.launch(Manifest.permission.CAMERA)
    }

    private fun maybeStartRemoteCapture() {
        if (!ConnectionRuntime.isActivityVisible) return
        val request = ConnectionRuntime.state.value
        val requestID = request.screenRequestID ?: return
        val macID = request.screenRequestedBy ?: return
        if (requestID == lastScreenRequestID) return
        lastScreenRequestID = requestID
        targetScreenMacID = macID
        targetScreenFrameRate = request.screenRequestedFramesPerSecond
        requestScreenCapture()
    }

    private fun requestScreenCapture() {
        configureDisplayFrameRate(targetScreenMacID?.let { targetScreenFrameRate } ?: preferences.getInt("screen_frame_rate", 60))
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            launchScreenConsent()
        }
    }

    @Suppress("DEPRECATION")
    private fun configureDisplayFrameRate(requestedFramesPerSecond: Int) {
        val activeDisplay = if (Build.VERSION.SDK_INT >= 30) display else windowManager.defaultDisplay
        val currentMode = activeDisplay?.mode ?: return
        val modes = activeDisplay.supportedModes.filter { it.physicalWidth == currentMode.physicalWidth && it.physicalHeight == currentMode.physicalHeight }
        val preferred = modes.filter { it.refreshRate + 0.5 >= requestedFramesPerSecond }.minByOrNull { it.refreshRate }
            ?: modes.maxByOrNull { it.refreshRate } ?: return
        val attributes = window.attributes
        attributes.preferredDisplayModeId = preferred.modeId
        window.attributes = attributes
    }

    private fun startCameraStream() {
        val request = pendingCameraRequest ?: return
        val macID = request.cameraRequestedBy ?: return
        val service = Intent(this, dev.seamless.companion.camera.CameraStreamService::class.java)
            .putExtra("macID", macID).putExtra("facing", request.cameraFacing)
            .putExtra("exposureEV", request.cameraExposureEV).putExtra("zoom", request.cameraZoom).putExtra("torch", request.cameraTorch).putExtra("whiteBalance", request.cameraWhiteBalance)
            .putExtra("resolutionHeight", request.cameraResolutionHeight).putExtra("framesPerSecond", request.cameraFramesPerSecond)
        try {
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(service) else startService(service)
        } catch (exception: Exception) { ConnectionRuntime.update { it.copy(message = exception.message ?: "Camera could not start") } }
    }

    private fun launchScreenConsent() {
        val manager = getSystemService(MediaProjectionManager::class.java)
        val requestEntireDisplay = targetScreenMacID != null && ConnectionRuntime.state.value.screenCaptureEntireDisplay
        if (Build.VERSION.SDK_INT >= 34 && requestEntireDisplay) {
            val configuration = android.media.projection.MediaProjectionConfig.createConfigForDefaultDisplay()
            screenConsent.launch(manager.createScreenCaptureIntent(configuration))
        } else {
            screenConsent.launch(manager.createScreenCaptureIntent())
        }
    }

    private fun startScreenBenchmark(consent: Intent) {
        val intent = Intent(this, ScreenBenchmarkService::class.java)
            .putExtra(ScreenBenchmarkService.EXTRA_PROJECTION_CONSENT, consent)
            .putExtra(ScreenBenchmarkService.EXTRA_FRAME_RATE, preferences.getInt("screen_frame_rate", 60))
            .putExtra(ScreenBenchmarkService.EXTRA_MAXIMUM_DIMENSION, preferences.getInt("screen_maximum_dimension", 1920))
        val targetMac = targetScreenMacID
        if (targetMac != null) {
            intent.putExtra(ScreenBenchmarkService.EXTRA_TARGET_MAC, targetMac)
            intent.putExtra(ScreenBenchmarkService.EXTRA_FRAME_RATE, targetScreenFrameRate)
        }
        try {
            if (Build.VERSION.SDK_INT >= 26) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } catch (exception: Exception) {
            BenchmarkState.publish(BenchmarkState.snapshot.value.copy(
                isRunning = false, message = exception.message ?: "Could not start screen capture"
            ))
        }
    }
}
