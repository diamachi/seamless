package dev.seamless.companion.screen

import org.json.JSONObject
import java.io.BufferedOutputStream
import java.io.DataOutputStream
import java.net.Socket
import java.util.concurrent.ArrayBlockingQueue
import java.util.concurrent.TimeUnit

private data class EncodedFrame(val bytes: ByteArray, val presentationTimeMicroseconds: Long, val isKeyFrame: Boolean)

class MediaStreamSink : AutoCloseable {
    private val frames = ArrayBlockingQueue<EncodedFrame>(4)
    @Volatile private var format: ByteArray? = null
    @Volatile private var socket: Socket? = null
    @Volatile private var closed = false
    @Volatile private var awaitingKeyFrame = true
    @Volatile var requestKeyFrame: (() -> Unit)? = null
    val isAvailable: Boolean get() = !closed && socket?.isClosed == false

    fun configure(payload: JSONObject) {
        format = payload.toString().toByteArray(Charsets.UTF_8)
    }

    @Synchronized
    fun attach(connection: Socket) {
        check(!closed)
        socket?.close()
        socket = connection
        frames.clear()
        awaitingKeyFrame = true
        val hello = "{\"version\":1,\"id\":\"media\",\"type\":\"mediaReady\",\"payload\":{}}\n"
        connection.getOutputStream().write(hello.toByteArray())
        connection.getOutputStream().flush()
        Thread({ writeFrames(connection) }, "SeamlessMediaWriter").start()
        requestKeyFrame?.invoke()
    }

    @Synchronized
    fun offer(bytes: ByteArray, presentationTimeMicroseconds: Long, isKeyFrame: Boolean) {
        if (closed || socket == null || format == null || bytes.size > 4 * 1024 * 1024) return
        if (awaitingKeyFrame && !isKeyFrame) return
        if (frames.offer(EncodedFrame(bytes, presentationTimeMicroseconds, isKeyFrame))) {
            if (isKeyFrame) awaitingKeyFrame = false
        } else {
            frames.clear()
            awaitingKeyFrame = true
            requestKeyFrame?.invoke()
        }
    }

    override fun close() {
        closed = true
        requestKeyFrame = null
        socket?.close()
        socket = null
        frames.clear()
    }

    private fun writeFrames(connection: Socket) {
        try {
            val output = DataOutputStream(BufferedOutputStream(connection.getOutputStream()))
            while (!closed && socket === connection && !connection.isClosed) {
                val frame = frames.poll(1, TimeUnit.SECONDS) ?: continue
                if (frame.isKeyFrame) {
                    val description = format ?: continue
                    writeRecord(output, 0, 0, description)
                }
                writeRecord(output, if (frame.isKeyFrame) 2 else 1, frame.presentationTimeMicroseconds, frame.bytes)
                output.flush()
            }
        } catch (_: Exception) {
            connection.close()
        }
    }

    private fun writeRecord(output: DataOutputStream, kind: Int, presentationTime: Long, bytes: ByteArray) {
        output.writeByte(kind)
        output.writeInt(bytes.size)
        output.writeLong(presentationTime)
        output.write(bytes)
    }
}
