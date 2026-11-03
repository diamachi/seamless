package dev.seamless.companion.connection

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

data class ConnectedMacDetails(
    val operatingSystem: String,
    val model: String,
    val architecture: String,
    val ramBytes: Long,
    val appVersion: String,
    val deviceFamily: String = "Mac",
    val processor: String = "",
    val storageTotalBytes: Long = 0,
    val storageUsedBytes: Long = 0
)

data class PairingRequest(val macName: String, val requestID: String)
data class IncomingFileOffer(val transferID: String, val name: String, val size: Long)
data class TransferProgress(val id: String, val name: String, val completed: Long, val total: Long)

data class ReceivedFile(val path: String, val name: String)

data class CompanionConnectionState(
    val transferProgress: Map<String, TransferProgress> = emptyMap(),
    val outgoingFileCount: Int = 0,
    val isPreparingFolder: Boolean = false,
    val isListening: Boolean = false,
    val message: String = "Connection service is stopped",
    val pairingCode: String = "",
    val pairingExpiresAt: Long = 0,
    val isCreatingPairingCode: Boolean = false,
    val pairingError: String? = null,
    val connectedMacIDs: List<String> = emptyList(),
    val connectedMacs: List<String> = emptyList(),
    val macDetails: Map<String, ConnectedMacDetails> = emptyMap(),
    val pairingRequest: PairingRequest? = null,
    val incomingClipboard: String = "",
    val incomingFileOffer: IncomingFileOffer? = null,
    val receivedFile: ReceivedFile? = null,
    val screenRequestID: String? = null,
    val screenRequestedApplication: String = "",
    val screenCaptureEntireDisplay: Boolean = false,
    val screenRequestedBy: String? = null,
    val screenRequestedFramesPerSecond: Int = 60,
    val sharedFilesToSend: List<String> = emptyList(),
    val sharedTextToSend: String = "",
    val cameraRequestID: String? = null,
    val cameraRequestedBy: String? = null,
    val cameraExposureEV: Double = 0.0,
    val cameraZoom: Double = 1.0,
    val cameraTorch: Boolean = false,
    val cameraWhiteBalance: String = "auto",
    val cameraFacing: String = "back",
    val cameraResolutionHeight: Int = 1080,
    val cameraFramesPerSecond: Int = 30
)

object ConnectionRuntime {
    private val mutableState = MutableStateFlow(CompanionConnectionState())
    val state = mutableState.asStateFlow()
    @Volatile var server: PhoneServer? = null
    @Volatile var isActivityVisible = false

    @Synchronized
    fun update(transform: (CompanionConnectionState) -> CompanionConnectionState) {
        mutableState.value = transform(mutableState.value)
    }
}
