package dev.seamless.companion.features

import android.content.Context
import android.net.Uri
import android.os.StatFs
import android.provider.OpenableColumns
import dev.seamless.companion.connection.ConnectionRuntime
import dev.seamless.companion.connection.ControlChannel
import dev.seamless.companion.connection.IncomingFileOffer
import dev.seamless.companion.connection.MacPeer
import dev.seamless.companion.connection.ReceivedFile
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

private data class BulkEntry(
    val peer: MacPeer, val name: String, val size: Long, val hash: String,
    val file: File, val outgoing: Boolean, val source: Uri? = null, val expiresAt: Long = System.currentTimeMillis() + 300_000,
    val claimed: AtomicBoolean = AtomicBoolean(false), @Volatile var accepted: Boolean = false,
    @Volatile var channel: ControlChannel? = null
)

class BulkExchange(private val context: Context) : AutoCloseable {
    private val notifications = TransferNotifications(context)
    private val entries = ConcurrentHashMap<String, BulkEntry>()

    private data class QueuedFile(val uri: Uri, val peer: MacPeer, val temporaryFile: File?)
    private val outgoingQueue = java.util.ArrayDeque<QueuedFile>()
    private val preparationExecutor = java.util.concurrent.Executors.newSingleThreadExecutor()
    private var preparing = false

    @Synchronized
    fun enqueue(uris: List<Uri>, peer: MacPeer, temporaryFile: File? = null) {
        for (uri in uris) outgoingQueue.add(QueuedFile(uri, peer, temporaryFile))
        advanceOutgoingQueue()
    }

    @Synchronized
    private fun advanceOutgoingQueue() {
        ConnectionRuntime.update { it.copy(outgoingFileCount = outgoingQueue.size + entries.values.count { entry -> entry.outgoing }) }
        if (preparationExecutor.isShutdown || preparing || entries.size >= 8 || entries.values.any { it.outgoing } || outgoingQueue.isEmpty()) return
        val next = outgoingQueue.removeFirst()
        preparing = true
        preparationExecutor.execute {
            try {
                if (next.temporaryFile != null) temporarySources[next.uri.toString()] = next.temporaryFile
                offer(next.uri, next.peer)
            } catch (exception: Exception) {
                temporarySources.remove(next.uri.toString())?.delete()
                ConnectionRuntime.update { it.copy(message = exception.message ?: "Could not prepare file") }
            } finally {
                synchronized(this) {
                    preparing = false
                    advanceOutgoingQueue()
                }
            }
        }
    }

    private val temporarySources = ConcurrentHashMap<String, File>()

    fun offer(uri: Uri, peer: MacPeer, requestToken: String? = null) {
        require(entries.size < 8) { "Finish current transfers first" }
        var size = 0L
        val digest = MessageDigest.getInstance("SHA-256")
        context.contentResolver.openInputStream(uri).use { input ->
            requireNotNull(input)
            val buffer = ByteArray(262_144)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                size += count
                require(size <= MAXIMUM_BYTES) { "File size exceeds protocol range" }
                digest.update(buffer, 0, count)
            }
        }
        val name = documentName(uri)
        val hash = digest.digest().hex()
        val id = UUID.randomUUID().toString()
        val unusedPath = File(context.cacheDir, "bulk-${UUID.randomUUID()}")
        entries[id] = BulkEntry(peer, name, size, hash, unusedPath, true, source = uri)
        peer.channel.send("bulkOffer", JSONObject().put("transferID", id).put("name", name).put("size", size).put("sha256", hash).put("requestToken", requestToken))
        ConnectionRuntime.update { it.copy(message = "Waiting for ${peer.name} to accept $name") }
    }

    fun handle(peer: MacPeer, type: String, payload: JSONObject) {
        val id = payload.getString("transferID")
        require(id.matches(Regex("[a-zA-Z0-9-]{1,64}")))
        if (type == "bulkCancel") { cancel(peer.id, id); return }
        require(type == "bulkOffer" && !entries.containsKey(id))
        if (entries.size >= 8) {
            peer.channel.send("bulkCancel", JSONObject().put("transferID", id))
            return
        }
        val name = payload.getString("name")
        val size = payload.getLong("size")
        require(payload.getDouble("size").isFinite() && payload.getDouble("size") == size.toDouble())
        val hash = payload.getString("sha256")
        require(validName(name) && size in 0..MAXIMUM_BYTES && hash.matches(Regex("[a-f0-9]{64}")))
        if (StatFs(context.cacheDir.path).availableBytes <= size + 16L * 1024 * 1024) {
            peer.channel.send("bulkCancel", JSONObject().put("transferID", id).put("reason", "Not enough storage on the phone"))
            ConnectionRuntime.update { it.copy(message = "Not enough storage for $name") }
            return
        }
        entries[id] = BulkEntry(peer, name, size, hash, File(context.cacheDir, "bulk-${UUID.randomUUID()}"), false)
        presentNextOffer()
    }

    @Synchronized
    fun presentNextOffer() {
        val state = ConnectionRuntime.state.value
        if (state.incomingFileOffer != null || state.receivedFile != null || entries.values.any { !it.outgoing && it.accepted }) return
        val next = entries.entries.filter { !it.value.outgoing && !it.value.accepted }.minByOrNull { it.value.expiresAt } ?: return
        val autoAccept = context.getSharedPreferences("phone_policies", Context.MODE_PRIVATE).getBoolean("file_auto.${next.value.peer.id}", false)
        if (autoAccept) accept(next.key, true)
        else ConnectionRuntime.update { it.copy(incomingFileOffer = IncomingFileOffer(next.key, next.value.name, next.value.size)) }
    }

    fun contains(id: String): Boolean = entries.containsKey(id)

    fun accept(id: String, accepted: Boolean) {
        val entry = entries[id] ?: return
        require(!entry.outgoing && entry.expiresAt > System.currentTimeMillis())
        if (!accepted) {
            entry.peer.channel.send("bulkCancel", JSONObject().put("transferID", id))
            cancel(entry.peer.id, id)
            return
        }
        entry.accepted = true
        entry.peer.channel.send("bulkAccepted", JSONObject().put("transferID", id))
        ConnectionRuntime.update { it.copy(incomingFileOffer = null, message = "Receiving ${entry.name}") }
    }

    fun stream(peerID: String, payload: JSONObject, channel: ControlChannel) {
        val id = payload.getString("transferID")
        val entry = entries[id] ?: error("Expired transfer")
        require(entry.peer.id == peerID && entry.expiresAt > System.currentTimeMillis() && entry.claimed.compareAndSet(false, true))
        val download = payload.getString("direction") == "download"
        require(download == entry.outgoing && (download || entry.accepted))
        entry.channel = channel
        try {
            reportProgress(id, entry, 0)
            channel.sendDirect("bulkReady")
            if (download) {
                context.contentResolver.openInputStream(requireNotNull(entry.source)).use { input ->
                    requireNotNull(input)
                    var remaining = entry.size
                    val buffer = ByteArray(262_144)
                    while (remaining > 0) {
                        val count = input.read(buffer, 0, minOf(remaining, buffer.size.toLong()).toInt())
                        require(count > 0) { "Source file changed or became unavailable" }
                        channel.bulkOutput().write(buffer, 0, count)
                        remaining -= count
                        reportProgress(id, entry, entry.size - remaining)
                    }
                }
                channel.bulkOutput().flush()
                notifications.finish(id, entry.name, "Sent to Mac")
            } else {
                val digest = MessageDigest.getInstance("SHA-256")
                var received = 0L
                val pendingDownload = PendingDownload.create(context, entry.name)
                try {
                (pendingDownload?.output ?: entry.file.outputStream()).use { output ->
                    val buffer = ByteArray(262_144)
                    while (received < entry.size) {
                        val count = channel.bulkInput().read(buffer, 0, minOf(buffer.size.toLong(), entry.size - received).toInt())
                        require(count > 0) { "Transfer interrupted" }
                        output.write(buffer, 0, count)
                        digest.update(buffer, 0, count)
                        received += count
                        reportProgress(id, entry, received)
                    }
                    output.fd.sync()
                }
                require(digest.digest().hex() == entry.hash) { "Integrity check failed" }
                if (pendingDownload != null) {
                    pendingDownload.publish()
                    ConnectionRuntime.update { it.copy(message = "Saved ${entry.name} to Downloads") }
                } else {
                    ConnectionRuntime.update { it.copy(receivedFile = ReceivedFile(entry.file.path, entry.name), message = "${entry.name} is ready to save") }
                }
                channel.sendDirect("bulkComplete")
                notifications.finish(id, entry.name, "Received and verified")
                } catch (exception: Exception) { pendingDownload?.abort(); throw exception }
            }
        } catch (exception: Exception) {
            notifications.finish(id, entry.name, "Transfer interrupted or failed")
            throw exception
        } finally {
            entries.remove(id, entry)
            ConnectionRuntime.update { it.copy(transferProgress = it.transferProgress - id) }
            entry.source?.let { temporarySources.remove(it.toString())?.delete() }
            advanceOutgoingQueue()
            if (download || ConnectionRuntime.state.value.receivedFile?.path != entry.file.path) entry.file.delete()
            presentNextOffer()
        }
    }

    private fun reportProgress(id: String, entry: BulkEntry, completed: Long) {
        val previous = ConnectionRuntime.state.value.transferProgress[id]
        // Publishing every network chunk would needlessly recompose the whole overview.
        if (previous == null || completed == entry.size || completed - previous.completed >= 1_048_576) {
            val progress = dev.seamless.companion.connection.TransferProgress(id, entry.name, completed, entry.size)
            ConnectionRuntime.update { it.copy(transferProgress = it.transferProgress + (id to progress)) }
        }
    }

    fun expire() {
        for ((id, entry) in entries) {
            if (entry.channel == null && entry.expiresAt < System.currentTimeMillis()) cancel(entry.peer.id, id)
        }
    }

    @Synchronized
    fun disconnect(peerID: String) {
        val discarded = outgoingQueue.filter { it.peer.id == peerID }
        outgoingQueue.removeAll(discarded.toSet())
        for (queued in discarded) queued.temporaryFile?.delete()
        for ((id, entry) in entries) { if (entry.peer.id == peerID) cancel(peerID, id) }
    }

    private fun cancel(peerID: String, id: String) {
        val entry = entries[id] ?: return
        if (entry.peer.id != peerID) return
        entries.remove(id, entry)
        ConnectionRuntime.update { it.copy(transferProgress = it.transferProgress - id) }
        entry.source?.let { temporarySources.remove(it.toString())?.delete() }
        entry.channel?.close()
        entry.file.delete()
        ConnectionRuntime.update { if (it.incomingFileOffer?.transferID == id) it.copy(incomingFileOffer = null) else it }
        presentNextOffer()
        advanceOutgoingQueue()
    }

    override fun close() {
        synchronized(this) {
            for (queued in outgoingQueue) queued.temporaryFile?.delete()
            outgoingQueue.clear()
        }
        preparationExecutor.shutdownNow()
        for ((id, entry) in entries) cancel(entry.peer.id, id)
    }

    private fun documentName(uri: Uri): String {
        if (uri.scheme == "file") return File(requireNotNull(uri.path)).name
        context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null).use { cursor ->
            if (cursor != null && cursor.moveToFirst()) {
                val name = cursor.getString(0).replace('/', '_').replace('\\', '_').take(255)
                if (validName(name)) return name
            }
        }
        return "Shared file"
    }

    private fun ByteArray.hex() = joinToString("") { "%02x".format(it) }
    companion object {
        const val MAXIMUM_BYTES = 9_007_199_254_740_991L
        fun validName(name: String) = name.isNotBlank() && name.length <= 255 && name != "." && name != ".." && !name.contains('/') && !name.contains('\\') && !name.contains('\u0000')
    }
}
