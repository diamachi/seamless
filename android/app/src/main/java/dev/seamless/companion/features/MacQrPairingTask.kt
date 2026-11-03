package dev.seamless.companion.features

import android.util.Base64
import org.json.JSONObject
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

class MacQrPairingTask : AutoCloseable {
    private val cancelled = AtomicBoolean(false)
    internal val isCancelled: Boolean get() = cancelled.get()
    private val activeSocket = AtomicReference<Socket?>()

    internal fun send(offer: MacQrPairingOffer, invitation: String) {
        val encrypted = PairingEnvelope.seal(invitation.toByteArray(Charsets.UTF_8), offer.key, offer.sessionID, "request")
        val packet = JSONObject().put("version", 1).put("sessionID", offer.sessionID)
            .put("sealedInvitation", Base64.encodeToString(encrypted, Base64.NO_WRAP))
        val bytes = (packet.toString() + "\n").toByteArray(Charsets.UTF_8)
        require(bytes.size <= 32_768)
        var lastError: Exception? = null
        for (host in offer.addresses) {
            checkActive()
            try {
                Socket().use { socket ->
                    activeSocket.set(socket)
                    checkActive()
                    socket.connect(InetSocketAddress(host, offer.port), 3_000)
                    socket.soTimeout = 5_000
                    socket.getOutputStream().write(bytes)
                    socket.getOutputStream().flush()
                    val response = readResponse(socket)
                    val combined = Base64.decode(response.getString("sealedAcknowledgement"), Base64.NO_WRAP)
                    val acknowledgement = PairingEnvelope.open(combined, offer.key, offer.sessionID, "ack")
                    require(String(acknowledgement, Charsets.UTF_8) == "accepted") { "The Mac did not accept this invitation" }
                    checkActive()
                    return
                }
            } catch (exception: Exception) {
                lastError = exception
            } finally {
                activeSocket.set(null)
            }
        }
        throw IllegalStateException("Could not reach the Mac. Keep its QR page open, use the same local network, and create a fresh QR.", lastError)
    }

    private fun readResponse(socket: Socket): JSONObject {
        val bytes = java.io.ByteArrayOutputStream()
        while (bytes.size() < 1_024) {
            checkActive()
            val next = socket.getInputStream().read()
            check(next >= 0) { "Mac closed the pairing request" }
            if (next == 10) return JSONObject(bytes.toString("UTF-8"))
            bytes.write(next)
        }
        error("Invalid Mac pairing reply")
    }

    private fun checkActive() { check(!cancelled.get()) { "Pairing cancelled" } }

    override fun close() {
        cancelled.set(true)
        try { activeSocket.getAndSet(null)?.close() } catch (_: java.io.IOException) { }
    }
}
