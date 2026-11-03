package dev.seamless.companion.connection

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Base64
import dev.seamless.companion.features.NotificationRelay
import dev.seamless.companion.features.PhoneRinger
import dev.seamless.companion.features.FileExchange
import dev.seamless.companion.features.PhoneInputService
import android.net.Uri
import dev.seamless.companion.BuildConfig
import org.json.JSONArray
import org.json.JSONObject
import java.net.Inet4Address
import java.net.NetworkInterface
import java.net.Socket
import java.util.Collections
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.Semaphore
import java.util.concurrent.TimeUnit
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import dev.seamless.companion.screen.MediaStreamSink
import dev.seamless.companion.screen.ScreenBenchmarkService
import android.content.Intent
import dev.seamless.companion.camera.CameraStreamService

data class MacPeer(val id: String, val name: String, val channel: ControlChannel, @Volatile var details: ConnectedMacDetails? = null)
private data class Invitation(val secret: String, val expiresAt: Long)
private data class PendingApproval(val requestID: String, val latch: CountDownLatch, var approved: Boolean = false)
private data class MediaGrant(val macID: String, val expiresAt: Long, val sink: MediaStreamSink)

class PhoneServer(private val context: Context) : AutoCloseable {
    private val identity = SecureIdentity(context)
    private val preferences = context.getSharedPreferences("phone_policies", Context.MODE_PRIVATE)
    private val executor = Executors.newFixedThreadPool(8)
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private val slots = Semaphore(8)
    private val sockets = ConcurrentHashMap.newKeySet<Socket>()
    private val peers = ConcurrentHashMap<String, MacPeer>()
    private val mediaGrants = ConcurrentHashMap<String, MediaGrant>()
    private val screenStreams = ConcurrentHashMap<String, MediaStreamSink>()
    private val cameraStreams = ConcurrentHashMap<String, MediaStreamSink>()
    private val advertisement = PhoneAdvertisement(context)
    private val ringer = PhoneRinger(context)
    private val files = FileExchange(context)
    private val bulk = dev.seamless.companion.features.BulkExchange(context)
    private val browserExecutor = java.util.concurrent.ThreadPoolExecutor(2, 2, 30, TimeUnit.SECONDS, java.util.concurrent.ArrayBlockingQueue(128))
    private val storage = dev.seamless.companion.features.StorageBrowser(context) { uri, peer, token -> bulk.offer(uri, peer, token) }
    private val mainHandler = Handler(Looper.getMainLooper())
    private val listener = (identity.createTLSContext().serverSocketFactory.createServerSocket() as SSLServerSocket).apply {
        // Reconnect replaces the listener immediately, while prior TCP sessions may be closing.
        reuseAddress = true
        bind(java.net.InetSocketAddress(PORT))
    }
    private val pausedMacs = context.getSharedPreferences("connection_settings", Context.MODE_PRIVATE)
        .getStringSet("paused_macs", emptySet()).orEmpty().toMutableSet()
    @Volatile private var closed = false
    private var invitation: Invitation? = null
    private var pendingApproval: PendingApproval? = null

    fun start(reconnectRequested: Boolean = false) {
        if (reconnectRequested) {
            synchronized(pausedMacs) {
                pausedMacs.clear()
                savePausedMacs()
            }
        }
        listener.enabledProtocols = listener.supportedProtocols.filter { it == "TLSv1.2" || it == "TLSv1.3" }.toTypedArray()
        ConnectionRuntime.update { it.copy(isListening = true, message = "Ready for a trusted Mac") }
        val reconnectRequest = if (reconnectRequested) java.util.UUID.randomUUID().toString() else null
        advertisement.start(identity.phoneID, PORT, reconnectRequest)
        Thread({ acceptConnections() }, "SeamlessTLSListener").start()
        scheduler.scheduleWithFixedDelay({ bulk.expire(); publishStatus() }, 0, 5, TimeUnit.SECONDS)
    }

    @Synchronized
    fun createInvitation(): String {
        val secret = SecureIdentity.randomSecret()
        invitation = Invitation(secret, SystemClock.elapsedRealtime() + 300_000)
        val addresses = Collections.list(NetworkInterface.getNetworkInterfaces())
            .filter { it.isUp && !it.isLoopback }
            .flatMap { Collections.list(it.inetAddresses) }
            .filterIsInstance<Inet4Address>()
            .filter { !it.isLoopbackAddress && !it.isLinkLocalAddress }
            .mapNotNull { it.hostAddress }
            .distinct()
        require(addresses.isNotEmpty()) { "Connect your phone to Wi-Fi, then create a QR code again." }
        val code = JSONObject().put("version", 1).put("phoneID", identity.phoneID)
            .put("name", "${Build.MANUFACTURER} ${Build.MODEL}").put("addresses", JSONArray(addresses))
            .put("port", PORT).put("certificatePin", identity.certificatePin).put("secret", secret)
        val encoded = "seamless1:" + Base64.encodeToString(code.toString().toByteArray(), Base64.NO_WRAP)
        ConnectionRuntime.update { it.copy(pairingCode = encoded, pairingExpiresAt = SystemClock.elapsedRealtime() + 300_000, isCreatingPairingCode = false, pairingError = null, message = "Pairing code expires in five minutes. Share it only with your Mac.") }
        return encoded
    }

    fun pairUsingMacQr(text: String, onResult: (String?) -> Unit): dev.seamless.companion.features.MacQrPairingTask {
        val task = dev.seamless.companion.features.MacQrPairingTask()
        executor.execute {
            try {
                val offer = dev.seamless.companion.features.MacQrPairingOffer.parse(text)
                val invitation = createInvitation()
                task.send(offer, invitation)
                ConnectionRuntime.update { it.copy(message = "QR sent to ${offer.name}. Approve the trust request on this phone.") }
                mainHandler.post { onResult(null) }
            } catch (exception: Exception) {
                val error = exception.message ?: "Could not pair with this Mac"
                if (!task.isCancelled) {
                    ConnectionRuntime.update { it.copy(pairingError = error, message = error) }
                    mainHandler.post { onResult(error) }
                }
            }
        }
        return task
    }

    @Synchronized
    fun resolvePairing(requestID: String, approved: Boolean) {
        val pending = pendingApproval ?: return
        if (pending.requestID != requestID) return
        pending.approved = approved
        pending.latch.countDown()
    }

    fun sendClipboard(text: String): Boolean {
        val peer = peers.values.singleOrNull()
        if (peer == null || text.isEmpty() || text.length > 32_000) {
            ConnectionRuntime.update { it.copy(message = "Connect exactly one Mac and choose text up to 32,000 characters") }
            return false
        }
        return try {
            peer.channel.send("clipboard", JSONObject().put("text", text))
            ConnectionRuntime.update { it.copy(message = "Copied text sent to ${peer.name}") }
            true
        } catch (_: Exception) {
            peer.channel.close()
            ConnectionRuntime.update { it.copy(message = "Mac disconnected before text could be sent") }
            false
        }
    }

    fun forgetAllMacs() {
        identity.revokeAllPeers()
        preferences.edit().clear().commit()
        synchronized(this) { invitation = null; pendingApproval?.latch?.countDown() }
        for (peer in peers.values) peer.channel.close()
        ConnectionRuntime.update { it.copy(pairingCode = "", message = "Trusted Macs removed. Pair again to reconnect.") }
    }

    fun advanceFileQueue() { bulk.presentNextOffer() }

    fun revokeBrowserAccess() { storage.revoke() }

    fun offerFile(uri: Uri) { offerFiles(listOf(uri)) }

    fun revokeContacts(macID: String) {
        preferences.edit().putBoolean("contacts_allowed.$macID", false).apply()
        peers[macID]?.let { safeSend(it, "contactsRevoked", JSONObject()) }
    }

    fun shareContacts(request: ContactsRequest, allowed: Boolean, rememberConsent: Boolean = true) {
        if (allowed && rememberConsent) {
            preferences.edit().putBoolean("contacts_allowed.${request.macID}", true).apply()
        }
        executor.execute {
            val peer = peers[request.macID] ?: return@execute
            try {
                require(allowed) { "Contacts access was declined on the phone" }
                val contacts = dev.seamless.companion.features.PhoneContacts.read(context)
                val pages = contacts.chunked(100).ifEmpty { listOf(emptyList()) }
                for ((index, page) in pages.withIndex()) {
                    require(peers[peer.id] === peer) { "Mac disconnected" }
                    require(preferences.getBoolean("contacts_allowed.${peer.id}", false)) { "Contacts access was revoked" }
                    peer.channel.send("contactsPage", JSONObject().put("token", request.token)
                        .put("index", index).put("last", index == pages.lastIndex)
                        .put("contacts", JSONArray(page)), waitForCapacity = true)
                }
            } catch (exception: Exception) {
                safeSend(peer, "contactsError", JSONObject().put("token", request.token)
                    .put("message", exception.message ?: "Could not read contacts"))
            } finally {
                ConnectionRuntime.update {
                    if (it.contactsRequest?.token == request.token) it.copy(contactsRequest = null) else it
                }
            }
        }
    }

    fun requestReconnect() {
        synchronized(pausedMacs) {
            pausedMacs.clear()
            savePausedMacs()
        }
        advertisement.close()
        advertisement.start(identity.phoneID, PORT, UUID.randomUUID().toString())
    }

    fun disconnectMac(macID: String) {
        executor.execute {
            val peer = peers[macID] ?: return@execute
            synchronized(pausedMacs) {
                pausedMacs.add(macID)
                savePausedMacs()
            }
            try {
                peer.channel.sendAndWait("disconnectRequested")
            } finally {
                peer.channel.close()
            }
        }
    }

    private fun savePausedMacs() {
        context.getSharedPreferences("connection_settings", Context.MODE_PRIVATE).edit()
            .putStringSet("paused_macs", pausedMacs.toSet()).apply()
    }

    fun offerFiles(uris: List<Uri>, targetMacID: String? = null): Boolean {
        val peer = if (targetMacID == null) peers.values.singleOrNull() else peers[targetMacID]
        if (peer == null) {
            ConnectionRuntime.update { it.copy(message = "Connect exactly one Mac before sending files") }
            return false
        }
        bulk.enqueue(uris, peer)
        return true
    }

    fun offerFolder(tree: Uri) {
        val peer = peers.values.singleOrNull() ?: return
        ConnectionRuntime.update { it.copy(isPreparingFolder = true, message = "Preparing folder ZIP…") }
        executor.execute {
            try {
                val archive = dev.seamless.companion.features.FolderArchive.create(context, tree)
                if (peers[peer.id] !== peer) {
                    archive.delete()
                    error("Mac disconnected while preparing folder")
                }
                bulk.enqueue(listOf(Uri.fromFile(archive)), peer, archive)
            } catch (exception: Exception) {
                ConnectionRuntime.update { it.copy(message = exception.message ?: "Could not prepare folder") }
            } finally {
                ConnectionRuntime.update { it.copy(isPreparingFolder = false) }
            }
        }
    }

    fun prepareScreenStream(macID: String): MediaStreamSink {
        val peer = peers[macID] ?: error("The requesting Mac is disconnected")
        for (stream in screenStreams.values) stream.close()
        screenStreams.clear()
        val sink = MediaStreamSink()
        screenStreams[macID] = sink
        val token = SecureIdentity.randomSecret()
        mediaGrants[token] = MediaGrant(macID, SystemClock.elapsedRealtime() + 30_000, sink)
        peer.channel.send("mediaGrant", JSONObject().put("token", token).put("purpose", "screen"))
        ConnectionRuntime.update { it.copy(screenRequestedBy = null) }
        return sink
    }

    fun screenCaptureEnded(macID: String) {
        screenStreams.remove(macID)?.close()
        peers[macID]?.let { safeSend(it, "screenEnded", JSONObject()) }
    }

    fun prepareCameraStream(macID: String): MediaStreamSink {
        val peer = peers[macID] ?: error("The requesting Mac is disconnected")
        for (stream in cameraStreams.values) stream.close()
        cameraStreams.clear()
        val sink = MediaStreamSink()
        cameraStreams[macID] = sink
        val token = SecureIdentity.randomSecret()
        mediaGrants[token] = MediaGrant(macID, SystemClock.elapsedRealtime() + 30_000, sink)
        peer.channel.send("mediaGrant", JSONObject().put("token", token).put("purpose", "camera"))
        ConnectionRuntime.update { it.copy(cameraRequestedBy = null) }
        return sink
    }

    fun cameraCaptureEnded(macID: String) {
        cameraStreams.remove(macID)?.close()
        peers[macID]?.let { safeSend(it, "cameraEnded", JSONObject()) }
    }

    fun reportCameraError(macID: String, message: String) {
        peers[macID]?.let { safeSend(it, "cameraError", JSONObject().put("message", message.take(500))) }
    }

    fun acceptFile(transferID: String, accepted: Boolean) {
        executor.execute {
            try {
                if (bulk.contains(transferID)) bulk.accept(transferID, accepted)
                else if (accepted) files.accept(transferID) else files.reject(transferID)
            } catch (exception: Exception) {
                ConnectionRuntime.update { it.copy(message = exception.message ?: "Could not accept file") }
            }
        }
    }

    fun relayNotification(applicationID: String, profileID: String, payload: JSONObject) {
        for (peer in peers.values) {
            if (allowsNotification(peer.id, applicationID, profileID)) {
                safeSend(peer, "notification", payload)
            }
        }
    }

    fun relayNotificationRemoval(applicationID: String, profileID: String, payload: JSONObject) {
        for (peer in peers.values) {
            if (allowsNotification(peer.id, applicationID, profileID)) safeSend(peer, "notificationRemoved", payload)
        }
    }

    override fun close() {
        closed = true
        advertisement.close()
        synchronized(this) { pendingApproval?.latch?.countDown() }
        listener.close()
        for (socket in sockets) socket.close()
        peers.clear()
        if (screenStreams.isNotEmpty()) context.stopService(Intent(context, ScreenBenchmarkService::class.java))
        if (cameraStreams.isNotEmpty()) context.stopService(Intent(context, CameraStreamService::class.java))
        for (stream in cameraStreams.values) stream.close()
        cameraStreams.clear()
        for (stream in screenStreams.values) stream.close()
        screenStreams.clear()
        mediaGrants.clear()
        files.close()
        bulk.close()
        scheduler.shutdownNow()
        executor.shutdownNow()
        browserExecutor.shutdownNow()
        mainHandler.post { ringer.stop() }
        if (ConnectionRuntime.server === this) {
            ConnectionRuntime.update { CompanionConnectionState(message = "Connection service stopped") }
        }
    }

    private fun acceptConnections() {
        while (!closed) {
            try {
                val socket = listener.accept() as SSLSocket
                if (!slots.tryAcquire()) {
                    socket.close()
                    continue
                }
                sockets.add(socket)
                executor.execute {
                    try {
                        handleConnection(socket)
                    } finally {
                        sockets.remove(socket)
                        socket.close()
                        slots.release()
                    }
                }
            } catch (_: Exception) {
                if (!closed) ConnectionRuntime.update { it.copy(message = "Connection interrupted; restart the service if needed") }
            }
        }
    }

    private fun handleConnection(socket: SSLSocket) {
        var peer: MacPeer? = null
        try {
            socket.soTimeout = 15_000
            socket.startHandshake()
            ControlChannel(socket).use { channel ->
                val firstMessage = channel.read() ?: return
                val payload = firstMessage.getJSONObject("payload")
                val macID = payload.getString("macID")
                require(macID.length in 1..64 && macID.matches(Regex("[a-zA-Z0-9-]+")))
                val macName = payload.optString("macName", "Mac").take(80)
                if (firstMessage.getString("type") == "bulkAuthenticate") {
                    val expected = identity.peerCredential(macID) ?: error("Mac is not paired")
                    require(peers.containsKey(macID) && SecureIdentity.secretsMatch(expected, payload.getString("credential")))
                    socket.soTimeout = 60_000
                    bulk.stream(macID, payload, channel)
                    return
                }
                if (firstMessage.getString("type") == "mediaAuthenticate") {
                    handleMediaSocket(socket, macID, payload)
                    return
                }
                if (firstMessage.getString("type") == "pair") {
                    authorizeNewMac(payload, channel, macID, macName)
                } else {
                    require(firstMessage.getString("type") == "authenticate")
                    val expected = identity.peerCredential(macID) ?: error("Mac is not paired")
                    require(SecureIdentity.secretsMatch(expected, payload.getString("credential")))
                    if (synchronized(pausedMacs) { pausedMacs.contains(macID) }) {
                        channel.sendAndWait("connectionPaused")
                        return
                    }
                    channel.send("authenticated", JSONObject().put("phoneID", identity.phoneID))
                }
                socket.soTimeout = 90_000
                val authenticatedPeer = MacPeer(macID, macName, channel)
                peer = authenticatedPeer
                peers.put(macID, authenticatedPeer)?.channel?.close()
                updateConnectedMacs()
                channel.send("status", PhoneStatus.snapshot(context, identity.phoneID))
                channel.send("applications", NotificationRelay.applicationInventory(context))
                while (!closed) {
                    val packet = channel.read() ?: break
                    dispatch(authenticatedPeer, packet)
                }
            }
        } catch (exception: Exception) {
            // Peer-specific failures must not expose secrets or take down other sessions.
            if (BuildConfig.DEBUG) android.util.Log.w("SeamlessConnection", "Peer session ended: ${exception.javaClass.simpleName}")
        } finally {
            val finishedPeer = peer
            if (finishedPeer != null && peers.remove(finishedPeer.id, finishedPeer)) {
                files.disconnect(finishedPeer.id)
                bulk.disconnect(finishedPeer.id)
                storage.disconnected(finishedPeer.id)
                if (ConnectionRuntime.server === this) ConnectionRuntime.update { state ->
                    var updated = state
                    if (state.screenRequestedBy == finishedPeer.id) {
                        updated = updated.copy(screenRequestedBy = null, screenRequestID = null)
                    }
                    if (state.contactsRequest?.macID == finishedPeer.id) {
                        updated = updated.copy(contactsRequest = null)
                    }
                    if (state.cameraRequestedBy == finishedPeer.id) {
                        updated = updated.copy(cameraRequestedBy = null, cameraRequestID = null)
                    }
                    updated
                }
                if (screenStreams.remove(finishedPeer.id)?.also { it.close() } != null) {
                    context.stopService(Intent(context, ScreenBenchmarkService::class.java))
                }
                if (cameraStreams.remove(finishedPeer.id)?.also { it.close() } != null) {
                    context.stopService(Intent(context, CameraStreamService::class.java))
                }
            }
            updateConnectedMacs()
        }
    }

    private fun authorizeNewMac(payload: JSONObject, channel: ControlChannel, macID: String, macName: String) {
        val pending = synchronized(this) {
            val active = invitation ?: error("Create a new pairing invitation")
            require(SystemClock.elapsedRealtime() < active.expiresAt)
            require(SecureIdentity.secretsMatch(active.secret, payload.getString("secret")))
            require(pendingApproval == null) { "Another pairing request is awaiting approval" }
            invitation = null
            PendingApproval(UUID.randomUUID().toString(), CountDownLatch(1)).also { pendingApproval = it }
        }
        try {
            ConnectionRuntime.update { it.copy(pairingCode = "", pairingRequest = PairingRequest(macName, pending.requestID)) }
            if (BuildConfig.DEBUG) android.util.Log.i("SeamlessConnection", "Pairing approval requested")
            ConnectionService.notifyPairingRequest(context, macName)
            channel.send("pairingPending")
            require(pending.latch.await(180, TimeUnit.SECONDS) && pending.approved) { "Pairing was not approved" }
            val credential = SecureIdentity.randomSecret()
            identity.storePeer(macID, credential)
            channel.send("paired", JSONObject().put("phoneID", identity.phoneID).put("credential", credential))
        } finally {
            synchronized(this) { pendingApproval = null }
            ConnectionRuntime.update { it.copy(pairingRequest = null) }
        }
    }

    private fun dispatch(peer: MacPeer, packet: JSONObject) {
        require(identity.hasPeer(peer.id)) { "Mac trust has been revoked" }
        val payload = packet.optJSONObject("payload") ?: JSONObject()
        val requestID = packet.getString("id")
        when (packet.getString("type")) {
            "macDetails" -> {
                peer.details = ConnectedMacDetails(
                    operatingSystem = payload.optString("operatingSystem").take(80),
                    model = payload.optString("model").take(80),
                    architecture = payload.optString("architecture").take(40),
                    ramBytes = payload.optLong("ramBytes").coerceIn(0, 16L * 1024 * 1024 * 1024 * 1024),
                    appVersion = payload.optString("appVersion").take(40),
                    deviceFamily = payload.optString("deviceFamily", "Mac").take(40),
                    processor = payload.optString("processor").take(120),
                    storageTotalBytes = payload.optLong("storageTotalBytes").coerceIn(0, 1L shl 55),
                    storageUsedBytes = payload.optLong("storageUsedBytes").coerceIn(0, 1L shl 55)
                )
                updateConnectedMacs()
            }
            "unpair" -> {
                identity.revokePeer(peer.id)
                preferences.edit().remove("policy.${peer.id}").remove("file_auto.${peer.id}").remove("camera_auto.${peer.id}").remove("contacts_allowed.${peer.id}").commit()
                peers.remove(peer.id, peer)
                if (screenStreams.remove(peer.id)?.also { it.close() } != null) context.stopService(Intent(context, ScreenBenchmarkService::class.java))
                if (cameraStreams.remove(peer.id)?.also { it.close() } != null) context.stopService(Intent(context, CameraStreamService::class.java))
                files.disconnect(peer.id)
                bulk.disconnect(peer.id)
                storage.disconnected(peer.id)
                peer.channel.send("unpaired", requestID = requestID)
                updateConnectedMacs()
            }
            "cameraRequest" -> {
                val facing = payload.getString("facing")
                val height = payload.getInt("resolutionHeight")
                val framesPerSecond = payload.getInt("framesPerSecond")
                require(facing == "front" || facing == "back")
                require(height in listOf(720, 1080, 1440, 2160) && framesPerSecond in listOf(24, 30, 60))
                ConnectionRuntime.update { it.copy(cameraRequestedBy = peer.id, cameraRequestID = requestID, cameraExposureEV = payload.optDouble("exposureEV", 0.0).takeIf { value -> value.isFinite() }?.coerceIn(-3.0, 3.0) ?: 0.0,
                    cameraZoom = payload.optDouble("zoom", 1.0).takeIf { value -> value.isFinite() }?.coerceIn(1.0, 4.0) ?: 1.0,
                    cameraTorch = payload.optBoolean("torch"), cameraWhiteBalance = payload.optString("whiteBalance", "auto").take(30), cameraFacing = facing,
                    cameraResolutionHeight = height, cameraFramesPerSecond = framesPerSecond) }
                ConnectionService.notifyCaptureRequest(context, camera = true)
            }
            "mediaKeyFrameRequest" -> {
                val stream = if (payload.optString("purpose") == "camera") cameraStreams[peer.id] else screenStreams[peer.id]
                stream?.requestKeyFrame?.invoke()
            }
            "cameraControls" -> {
                if (cameraStreams.containsKey(peer.id)) CameraStreamService.updateControls(peer.id, payload)
            }
            "cameraStop" -> {
                if (cameraStreams.remove(peer.id)?.also { it.close() } != null) context.stopService(Intent(context, CameraStreamService::class.java))
            }
            "input" -> {
                require(screenStreams[peer.id]?.isAvailable == true) { "Start an approved screen-sharing session first" }
                val expiresAt = payload.getLong("expiresAt")
                require(expiresAt >= System.currentTimeMillis() && expiresAt <= System.currentTimeMillis() + 60_000)
                if (!PhoneInputService.submit(payload)) peer.channel.send("error", JSONObject().put("message", "Enable the optional Seamless phone-control accessibility service first."), requestID)
            }
            "screenRequest" -> {
                val frameRate = payload.getInt("framesPerSecond")
                require(frameRate == 60 || frameRate == 120)
                ConnectionRuntime.update { it.copy(screenRequestedBy = peer.id, screenRequestID = requestID, screenRequestedApplication = payload.optString("applicationName").take(120), screenCaptureEntireDisplay = payload.optBoolean("captureEntireDisplay", false), screenRequestedFramesPerSecond = 60) }
                ConnectionService.notifyCaptureRequest(context)
            }
            "screenStop" -> {
                if (screenStreams.remove(peer.id)?.also { it.close() } != null) {
                    context.stopService(Intent(context, ScreenBenchmarkService::class.java))
                }
            }
            "browseList", "browseDownload", "browseThumbnail" -> {
                try {
                    browserExecutor.execute {
                        if (peers[peer.id] === peer) storage.handle(peer, packet.getString("type"), payload, requestID)
                    }
                } catch (_: java.util.concurrent.RejectedExecutionException) {
                    peer.channel.send("browseError", JSONObject().put("message", "Browser busy. Refresh to retry."), requestID)
                }
            }
            "bulkOffer", "bulkCancel" -> bulk.handle(peer, packet.getString("type"), payload)
            "fileOffer", "fileAccept", "fileChunk", "fileFinish", "fileCancel", "fileComplete" -> files.handle(peer, packet.getString("type"), payload)
            "ping" -> peer.channel.send("pong", requestID = requestID)
            "statusRequest" -> peer.channel.send("status", PhoneStatus.snapshot(context, identity.phoneID), requestID)
            "applicationsRequest" -> peer.channel.send("applications", NotificationRelay.applicationInventory(context), requestID)
            "ring" -> {
                val expiresAt = payload.getLong("expiresAt")
                require(expiresAt >= System.currentTimeMillis() && expiresAt <= System.currentTimeMillis() + 60_000)
                ringer.ring()
                peer.channel.send("ack", requestID = requestID)
            }
            "stopRing" -> mainHandler.post { ringer.stop() }
            "notificationPolicy" -> {
                require(payload.toString().length <= 64_000)
                check(preferences.edit().putString("policy.${peer.id}", payload.toString()).commit())
                peer.channel.send("ack", requestID = requestID)
            }
            "contactsRequest" -> {
                val token = payload.getString("token")
                require(token.length == 36)
                val request = ContactsRequest(peer.id, token, peer.name)
                val hasPermission = context.checkSelfPermission(android.Manifest.permission.READ_CONTACTS) == android.content.pm.PackageManager.PERMISSION_GRANTED
                if (hasPermission && preferences.getBoolean("contacts_allowed.${peer.id}", false)) {
                    shareContacts(request, true, rememberConsent = false)
                } else {
                    ConnectionRuntime.update { it.copy(contactsRequest = request) }
                    ConnectionService.notifyContactsRequest(context, peer.name)
                }
            }
            "clipboard" -> receiveClipboard(peer, payload, requestID)
            "notificationAction" -> {
                val packageName = payload.getString("packageName")
                val profileID = payload.getString("profileIdentifier")
                require(allowsNotification(peer.id, packageName, profileID))
                NotificationRelay.performAction(context, payload)
            }
            else -> peer.channel.send("error", JSONObject().put("message", "Unsupported operation"), requestID)
        }
    }

    private fun handleMediaSocket(socket: SSLSocket, macID: String, payload: JSONObject) {
        val expected = identity.peerCredential(macID) ?: error("Mac is not paired")
        require(SecureIdentity.secretsMatch(expected, payload.getString("credential")) && peers.containsKey(macID))
        val grant = mediaGrants.remove(payload.getString("token")) ?: error("Media grant is unavailable")
        require(grant.macID == macID && grant.expiresAt > SystemClock.elapsedRealtime())
        socket.soTimeout = 0
        socket.tcpNoDelay = true
        grant.sink.attach(socket)
        while (socket.getInputStream().read() != -1) { /* Channel lifetime follows the authenticated receiver. */ }
    }

    private fun receiveClipboard(peer: MacPeer, payload: JSONObject, requestID: String) {
        val text = payload.getString("text")
        require(text.length <= 32_000)
        ConnectionRuntime.update { it.copy(incomingClipboard = text) }
        mainHandler.post {
            try {
                context.getSystemService(ClipboardManager::class.java)
                    .setPrimaryClip(ClipData.newPlainText("From your Mac", text))
                peer.channel.send("clipboardResult", JSONObject().put("copied", true), requestID)
                ConnectionRuntime.update { it.copy(message = "Copied from Mac · paste in any app") }
            } catch (_: Exception) {
                try { peer.channel.send("clipboardResult", JSONObject().put("copied", false), requestID) }
                catch (_: Exception) { peer.channel.close() }
            }
        }
    }

    private fun allowsNotification(macID: String, packageName: String, profileID: String): Boolean {
        val stored = preferences.getString("policy.$macID", null) ?: return false
        val policy = JSONObject(stored)
        if (policy.optBoolean("isPaused", true)) return false
        val applications = policy.optJSONArray("allowedApplications") ?: return false
        for (index in 0 until applications.length()) {
            val application = applications.getJSONObject(index)
            if (application.optString("packageName") == packageName && application.optString("profileIdentifier") == profileID) return true
        }
        return false
    }

    private fun publishStatus() {
        if (closed) return
        mediaGrants.entries.removeAll { it.value.expiresAt <= SystemClock.elapsedRealtime() }
        for (peer in peers.values) safeSend(peer, "status", PhoneStatus.snapshot(context, identity.phoneID))
    }

    private fun safeSend(peer: MacPeer, type: String, payload: JSONObject) {
        try {
            peer.channel.send(type, payload)
        } catch (_: Exception) {
            peer.channel.close()
        }
    }

    private fun updateConnectedMacs() {
        if (ConnectionRuntime.server !== this) return
        val connected = peers.values.sortedBy { it.id }
        ConnectionRuntime.update { it.copy(connectedMacs = connected.map { peer -> peer.name }, connectedMacIDs = connected.map { peer -> peer.id },
            macDetails = connected.mapNotNull { peer -> peer.details?.let { peer.id to it } }.toMap()) }
    }

    companion object { const val PORT = 48763 }
}
