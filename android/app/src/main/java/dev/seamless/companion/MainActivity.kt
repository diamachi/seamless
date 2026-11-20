// Android Activity entry point for permissions, sharing intents and capture requests.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

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
    private var pendingContactsRequest: dev.seamless.companion.connection.ContactsRequest? = null
    private val contactsPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        pendingContactsRequest?.let { ConnectionRuntime.server?.shareContacts(it, allowed) }
        pendingContactsRequest = null
    }
    /** Performs approve contacts for main activity. */
    private fun approveContacts() {
        val request = ConnectionRuntime.state.value.contactsRequest ?: return
        if (checkSelfPermission(Manifest.permission.READ_CONTACTS) == PackageManager.PERMISSION_GRANTED) {
            ConnectionRuntime.server?.shareContacts(request, true)
        } else {
            pendingContactsRequest = request
            contactsPermission.launch(Manifest.permission.READ_CONTACTS)
        }
    }
    private var pendingRequestReview: String? = null
    private var lastCameraRequestID: String? = null
    private var lastScreenRequestID: String? = null
    private var targetScreenMacID: String? = null
    private var targetScreenFrameRate = 60
    private var pendingCameraRequest: dev.seamless.companion.connection.CompanionConnectionState? = null
    private val cameraPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
        if (allowed) startCameraStream()
        else ConnectionRuntime.update { it.copy(message = "Camera permission is needed for live camera sharing") }
    }
    private val setupNotificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }
    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {
        launchScreenConsent()
    }
    private val screenConsent = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val consent = result.data
        if (result.resultCode == Activity.RESULT_OK && consent != null) {
            startScreenBenchmark(consent)
        }
    }

    /** Initializes Android-owned resources when this component is created. */
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        preferences.edit().putInt("screen_frame_rate", 60).apply()
        enableEdgeToEdge()
        dev.seamless.companion.features.AlertChannels.registerAll(this)
        if (Build.VERSION.SDK_INT >= 33 && !preferences.getBoolean("notification_prompt_requested", false)) {
            preferences.edit().putBoolean("notification_prompt_requested", true).apply()
            setupNotificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
        pendingRequestReview = intent?.getStringExtra("sharing_request_kind")
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
                onRemoteCamera = { maybeStartRemoteCamera() },
                onReadContacts = { approveContacts() }
            )
        }
    }

    /** Performs approve requested screen for main activity. */
    private fun approveRequestedScreen() {
        val connection = ConnectionRuntime.state.value
        targetScreenMacID = connection.screenRequestedBy
        targetScreenFrameRate = connection.screenRequestedFramesPerSecond
        requestScreenCapture()
    }

    /** Performs approve requested camera for main activity. */
    private fun approveRequestedCamera() {
        pendingCameraRequest = ConnectionRuntime.state.value
        if (checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) startCameraStream()
        else cameraPermission.launch(Manifest.permission.CAMERA)
    }

    /** Processes a new intent delivered to the existing Activity instance. */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveSharedText(intent)
        pendingRequestReview = intent.getStringExtra("sharing_request_kind")
        if (lifecycle.currentState.isAtLeast(androidx.lifecycle.Lifecycle.State.RESUMED)) {
            reviewRequestedSharing()
        }
    }

    /** Performs receive shared text for main activity. */
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
        if (intent?.action == Intent.ACTION_SEND && intent.hasExtra(Intent.EXTRA_TEXT)) {
            val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.take(32_000) ?: return
            ConnectionRuntime.update { it.copy(sharedTextToSend = text) }
        }
    }

    /** Registers foreground Activity behavior when the screen becomes visible. */
    override fun onStart() {
        super.onStart()
        ConnectionRuntime.isActivityVisible = true
        val hasSavedMac = getSharedPreferences("connection_identity", MODE_PRIVATE).all.keys.any { it.startsWith("peer.") }
        val reconnectOnLaunch = getSharedPreferences("connection_settings", MODE_PRIVATE).getBoolean("reconnect_on_launch", true)
        if (hasSavedMac && reconnectOnLaunch && ConnectionRuntime.server == null) {
            val service = Intent(this, dev.seamless.companion.connection.ConnectionService::class.java)
            if (Build.VERSION.SDK_INT >= 26) startForegroundService(service) else startService(service)
        }
    }

    /** Unregisters foreground Activity behavior when the screen leaves view. */
    override fun onStop() {
        ConnectionRuntime.isActivityVisible = false
        super.onStop()
    }

    /** Refreshes state that may have changed in Android settings while the Activity was paused. */
    override fun onResume() {
        super.onResume()
        reviewRequestedSharing()
        maybeStartRemoteCapture()
        maybeStartRemoteCamera()
    }

    /** Performs review requested sharing for main activity. */
    private fun reviewRequestedSharing() {
        val kind = pendingRequestReview ?: return
        pendingRequestReview = null
        ConnectionRuntime.update { it.copy(requestReviewSequence = it.requestReviewSequence + 1) }
        val state = ConnectionRuntime.state.value
        if (kind == "screen" && state.screenRequestedBy != null) {
            lastScreenRequestID = state.screenRequestID
            approveRequestedScreen()
        }
    }

    /** Performs maybe start remote camera for main activity. */
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

    /** Performs maybe start remote capture for main activity. */
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

    /** Performs request screen capture for main activity. */
    private fun requestScreenCapture() {
        configureDisplayFrameRate(targetScreenMacID?.let { targetScreenFrameRate } ?: preferences.getInt("screen_frame_rate", 60))
        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            launchScreenConsent()
        }
    }

    /** Selects a compatible display mode while preserving the current physical resolution. */
    @Suppress("DEPRECATION")
    /** Handles configure display frame rate callback by translating the native window event into the owning app action. */
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

    /** Performs start camera stream for main activity. */
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

    /** Opens Android’s required screen-sharing consent with the requested capture scope. */
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

    /** Performs start screen benchmark for main activity. */
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
