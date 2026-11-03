package dev.seamless.companion.connection

import org.json.JSONObject
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.ByteArrayOutputStream
import java.net.Socket
import java.util.UUID
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class ControlChannel(private val socket: Socket) : AutoCloseable {
    private val input = BufferedInputStream(socket.getInputStream())
    private val output = BufferedOutputStream(socket.getOutputStream())
    private val outgoing = ArrayBlockingQueue<ByteArray>(64)
    private val isClosed = AtomicBoolean(false)
    private val sender = Thread({ sendQueuedMessages() }, "SeamlessControlSender").apply { start() }

    fun read(): JSONObject? {
        val buffer = ByteArrayOutputStream()
        while (true) {
            val byte = input.read()
            if (byte == -1) {
                check(buffer.size() == 0) { "Truncated control message" }
                return null
            }
            if (byte == 10) break
            check(buffer.size() < MAXIMUM_FRAME_BYTES) { "Control message is too large" }
            buffer.write(byte)
        }
        val packet = JSONObject(buffer.toString("UTF-8"))
        check(packet.getInt("version") == 1) { "Unsupported protocol version" }
        return packet
    }

    fun send(type: String, payload: JSONObject = JSONObject(), requestID: String = UUID.randomUUID().toString(), waitForCapacity: Boolean = false) {
        val packet = JSONObject().put("version", 1).put("id", requestID).put("type", type).put("payload", payload)
        val bytes = (packet.toString() + "\n").toByteArray(Charsets.UTF_8)
        check(bytes.size <= MAXIMUM_FRAME_BYTES) { "Control message is too large" }
        check(!isClosed.get()) { "Connection is closed" }
        val enqueued = if (waitForCapacity) outgoing.offer(bytes, 5, TimeUnit.SECONDS) else outgoing.offer(bytes)
        check(enqueued) { "Connection is congested" }
    }

    fun bulkInput(): java.io.InputStream = input
    fun bulkOutput(): java.io.OutputStream = output

    fun sendDirect(type: String) {
        val packet = JSONObject().put("version", 1).put("id", UUID.randomUUID().toString()).put("type", type).put("payload", JSONObject())
        output.write((packet.toString() + "\n").toByteArray(Charsets.UTF_8))
        output.flush()
    }

    override fun close() {
        if (!isClosed.compareAndSet(false, true)) return
        socket.close()
        sender.interrupt()
        outgoing.clear()
    }

    private fun sendQueuedMessages() {
        try {
            while (!isClosed.get()) {
                val bytes = outgoing.poll(1, TimeUnit.SECONDS) ?: continue
                output.write(bytes)
                output.flush()
            }
        } catch (_: Exception) {
            close()
        }
    }

    companion object { const val MAXIMUM_FRAME_BYTES = 262_144 }
}
