package dev.seamless.companion.features

import android.content.Context
import android.net.Uri
import android.os.SystemClock
import android.provider.OpenableColumns
import android.util.Base64
import dev.seamless.companion.connection.ConnectionRuntime
import dev.seamless.companion.connection.IncomingFileOffer
import dev.seamless.companion.connection.MacPeer
import dev.seamless.companion.connection.ReceivedFile
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.UUID

private data class OutgoingFile(val peerID: String, val bytes: ByteArray, val createdAt: Long)
private data class IncomingFile(
    val peer: MacPeer, val name: String, val size: Long, val expectedHash: String,
    val path: File, val createdAt: Long, var output: FileOutputStream? = null,
    var receivedBytes: Long = 0, val digest: MessageDigest = MessageDigest.getInstance("SHA-256")
)

class FileExchange(private val context: Context) : AutoCloseable {
    private val outgoing = mutableMapOf<String, OutgoingFile>()
    private val incoming = mutableMapOf<String, IncomingFile>()

    fun offer(uri: Uri, peer: MacPeer) {
        val bytes = readBounded(uri)
        val name = documentName(uri)
        val transferID = UUID.randomUUID().toString()
        synchronized(this) {
            require(outgoing.size < 2) { "Finish or cancel the current file transfers first" }
            outgoing[transferID] = OutgoingFile(peer.id, bytes, SystemClock.elapsedRealtime())
        }
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }
        peer.channel.send("fileOffer", JSONObject().put("transferID", transferID).put("name", name)
            .put("size", bytes.size).put("sha256", digest))
        ConnectionRuntime.update { it.copy(message = "Waiting for your Mac to accept $name") }
    }

    @Synchronized
    fun handle(peer: MacPeer, type: String, payload: JSONObject) {
        val transferID = payload.getString("transferID")
        require(transferID.matches(Regex("[a-zA-Z0-9-]{1,64}")))
        when (type) {
            "fileOffer" -> receiveOffer(peer, transferID, payload)
            "fileAccept" -> sendFile(peer, transferID)
            "fileChunk" -> receiveChunk(peer, transferID, payload)
            "fileFinish" -> finishReceiving(peer, transferID)
            "fileCancel" -> cancel(peer.id, transferID)
            "fileComplete" -> {
                require(outgoing[transferID]?.peerID == peer.id)
                outgoing.remove(transferID)
            }
        }
    }

    @Synchronized
    fun accept(transferID: String) {
        val transfer = incoming[transferID] ?: return
        require(SystemClock.elapsedRealtime() - transfer.createdAt < 120_000)
        transfer.output = FileOutputStream(transfer.path)
        transfer.peer.channel.send("fileAccept", JSONObject().put("transferID", transferID))
        ConnectionRuntime.update { it.copy(incomingFileOffer = null, message = "Receiving ${transfer.name}") }
    }

    @Synchronized
    fun reject(transferID: String) {
        val transfer = incoming[transferID] ?: return
        transfer.peer.channel.send("fileCancel", JSONObject().put("transferID", transferID))
        cancel(transfer.peer.id, transferID)
    }

    @Synchronized
    fun disconnect(peerID: String) {
        incoming.filterValues { it.peer.id == peerID }.keys.toList().forEach { cancel(peerID, it) }
        outgoing.entries.removeAll { it.value.peerID == peerID }
    }

    @Synchronized
    override fun close() {
        for (transfer in incoming.values) { transfer.output?.close(); transfer.path.delete() }
        incoming.clear()
        outgoing.clear()
    }

    private fun receiveOffer(peer: MacPeer, transferID: String, payload: JSONObject) {
        val name = payload.getString("name")
        val size = payload.getLong("size")
        val hash = payload.getString("sha256")
        require(name.isNotBlank() && name.length <= 255 && !name.contains('/') && !name.contains('\\') && !name.contains('\u0000'))
        require(name != "." && name != ".." && size in 0..MAXIMUM_FILE_BYTES && hash.matches(Regex("[a-f0-9]{64}")))
        require(incoming.isEmpty()) { "An incoming transfer is already waiting" }
        require(ConnectionRuntime.state.value.receivedFile == null) { "Save the previously received file first" }
        val path = File(context.cacheDir, "incoming-${UUID.randomUUID()}")
        incoming[transferID] = IncomingFile(peer, name, size, hash, path, SystemClock.elapsedRealtime())
        ConnectionRuntime.update { it.copy(incomingFileOffer = IncomingFileOffer(transferID, name, size)) }
        dev.seamless.companion.connection.ConnectionService.notifyFileRequest(context, name)
    }

    private fun receiveChunk(peer: MacPeer, transferID: String, payload: JSONObject) {
        val transfer = incoming[transferID] ?: error("Unknown transfer")
        require(transfer.peer.id == peer.id && transfer.output != null)
        require(SystemClock.elapsedRealtime() - transfer.createdAt < 120_000)
        val bytes = Base64.decode(payload.getString("data"), Base64.NO_WRAP)
        require(bytes.size <= CHUNK_BYTES && payload.getLong("offset") == transfer.receivedBytes)
        require(transfer.receivedBytes + bytes.size <= transfer.size)
        transfer.output!!.write(bytes)
        transfer.digest.update(bytes)
        transfer.receivedBytes += bytes.size
    }

    private fun finishReceiving(peer: MacPeer, transferID: String) {
        val transfer = incoming[transferID] ?: error("Unknown transfer")
        require(transfer.peer.id == peer.id && transfer.output != null && transfer.receivedBytes == transfer.size)
        val actualHash = transfer.digest.digest().joinToString("") { "%02x".format(it) }
        require(actualHash == transfer.expectedHash) { "File integrity check failed" }
        transfer.output!!.close()
        incoming.remove(transferID)
        ConnectionRuntime.state.value.receivedFile?.let { File(it.path).delete() }
        ConnectionRuntime.update { it.copy(receivedFile = ReceivedFile(transfer.path.path, transfer.name), message = "${transfer.name} is ready to save") }
        peer.channel.send("fileComplete", JSONObject().put("transferID", transferID))
    }

    private fun sendFile(peer: MacPeer, transferID: String) {
        val transfer = outgoing[transferID] ?: error("Unknown transfer")
        require(transfer.peerID == peer.id && SystemClock.elapsedRealtime() - transfer.createdAt < 120_000)
        var offset = 0
        while (offset < transfer.bytes.size) {
            val end = minOf(offset + CHUNK_BYTES, transfer.bytes.size)
            val chunk = Base64.encodeToString(transfer.bytes.copyOfRange(offset, end), Base64.NO_WRAP)
            peer.channel.send("fileChunk", JSONObject().put("transferID", transferID).put("offset", offset).put("data", chunk), waitForCapacity = true)
            offset = end
        }
        peer.channel.send("fileFinish", JSONObject().put("transferID", transferID), waitForCapacity = true)
    }

    private fun cancel(peerID: String, transferID: String) {
        val transfer = incoming[transferID]
        if (transfer != null && transfer.peer.id == peerID) {
            transfer.output?.close()
            transfer.path.delete()
            incoming.remove(transferID)
            ConnectionRuntime.update { it.copy(incomingFileOffer = null) }
        }
        if (outgoing[transferID]?.peerID == peerID) outgoing.remove(transferID)
    }

    private fun readBounded(uri: Uri): ByteArray {
        val output = ByteArrayOutputStream()
        context.contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input)
            val buffer = ByteArray(16_384)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                require(output.size().toLong() + count <= MAXIMUM_FILE_BYTES) { "This development build supports files up to 20 MiB" }
                output.write(buffer, 0, count)
            }
        }
        return output.toByteArray()
    }

    private fun documentName(uri: Uri): String {
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null).use { cursor ->
            if (cursor != null && cursor.moveToFirst()) return cursor.getString(0).replace('/', '_').replace('\\', '_').take(255)
        }
        return "Shared file"
    }

    companion object {
        const val MAXIMUM_FILE_BYTES = 20L * 1024 * 1024
        const val CHUNK_BYTES = 49_152
    }
}
