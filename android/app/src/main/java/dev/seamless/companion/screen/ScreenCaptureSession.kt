package dev.seamless.companion.screen

import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaCodec
import android.media.projection.MediaProjection
import android.os.Handler
import android.os.SystemClock
import android.view.Surface
import android.util.Log
import dev.seamless.companion.BuildConfig
import android.os.Bundle
import android.util.Base64
import org.json.JSONObject

class ScreenCaptureSession(
    private val projection: MediaProjection,
    private val handler: Handler,
    private val onProjectionStopped: () -> Unit,
    private val onFailure: (Exception) -> Unit,
    private val mediaSink: MediaStreamSink? = null
) {
    private var encoder: MediaCodec? = null
    private var inputSurface: Surface? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var statistics: BenchmarkStatistics? = null
    private var isClosed = false
    private val outputInfo = MediaCodec.BufferInfo()
    private val projectionCallback = object : MediaProjection.Callback() {
        override fun onStop() {
            onProjectionStopped()
        }
    }
    private val drainTask = object : Runnable {
        override fun run() {
            if (isClosed) return
            try {
                drainEncoder()
                handler.postDelayed(this, 2)
            } catch (exception: Exception) {
                onFailure(exception)
            }
        }
    }

    fun start(configuration: ScreenEncodingConfiguration, densityDpi: Int) {
        projection.registerCallback(projectionCallback, handler)
        val activeEncoder = ScreenEncoderFactory.create(configuration)
        encoder = activeEncoder
        val surface = activeEncoder.createInputSurface()
        inputSurface = surface
        activeEncoder.start()
        mediaSink?.requestKeyFrame = {
            handler.post {
                if (!isClosed) activeEncoder.setParameters(Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) })
            }
        }
        virtualDisplay = projection.createVirtualDisplay(
            "Seamless screen benchmark", configuration.width, configuration.height, densityDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR, surface, null, handler
        )
        statistics = BenchmarkStatistics(SystemClock.elapsedRealtimeNanos())
        BenchmarkState.publish(BenchmarkSnapshot(
            isRunning = true,
            message = if (mediaSink == null) "Encoding locally. No screen content is saved or transmitted." else "Streaming the approved screen to your paired Mac.",
            encoderName = configuration.encoderName,
            resolution = "${configuration.width} × ${configuration.height}",
            requestedFramesPerSecond = configuration.framesPerSecond
        ))
        handler.post(drainTask)
    }

    fun close() {
        if (isClosed) return
        isClosed = true
        handler.removeCallbacks(drainTask)
        mediaSink?.close()
        virtualDisplay?.release()
        virtualDisplay = null
        val activeEncoder = encoder
        encoder = null
        try {
            activeEncoder?.stop()
        } finally {
            activeEncoder?.release()
            inputSurface?.release()
            inputSurface = null
            projection.unregisterCallback(projectionCallback)
            projection.stop()
        }
    }

    private fun drainEncoder() {
        val activeEncoder = encoder ?: return
        val activeStatistics = statistics ?: return
        // Bound each pass so a busy encoder cannot starve stop and projection callbacks.
        repeat(32) {
            val outputIndex = activeEncoder.dequeueOutputBuffer(outputInfo, 0)
            if (outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                return@repeat
            }
            if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val format = activeEncoder.outputFormat
                val description = JSONObject().put("width", format.getInteger("width")).put("height", format.getInteger("height"))
                for (key in listOf("csd-0", "csd-1")) {
                    val buffer = format.getByteBuffer(key)?.duplicate() ?: continue
                    val bytes = ByteArray(buffer.remaining())
                    buffer.get(bytes)
                    description.put(key, Base64.encodeToString(bytes, Base64.NO_WRAP))
                }
                mediaSink?.configure(description)
            }
            if (outputIndex >= 0) {
                val isConfiguration = outputInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                if (outputInfo.size > 0 && !isConfiguration) {
                    activeStatistics.recordFrame(outputInfo.size, SystemClock.elapsedRealtimeNanos())
                    val sink = mediaSink
                    if (sink != null) {
                        val buffer = activeEncoder.getOutputBuffer(outputIndex)?.duplicate()
                        if (buffer != null) {
                            buffer.position(outputInfo.offset)
                            buffer.limit(outputInfo.offset + outputInfo.size)
                            val bytes = ByteArray(outputInfo.size)
                            buffer.get(bytes)
                            sink.offer(bytes, outputInfo.presentationTimeUs, outputInfo.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0)
                        }
                    }
                }
                activeEncoder.releaseOutputBuffer(outputIndex, false)
            }
        }
        val updated = activeStatistics.sample(SystemClock.elapsedRealtimeNanos(), BenchmarkState.snapshot.value)
        if (updated != null) {
            BenchmarkState.publish(updated)
            if (BuildConfig.DEBUG) {
                Log.i("SeamlessBenchmark", "requested=${updated.requestedFramesPerSecond} size=${updated.resolution} encoder=${updated.encoderName} seconds=${updated.elapsedSeconds} frames=${updated.totalFrames} fps=${updated.encodedFramesPerSecond} average=${updated.averageEncodedFramesPerSecond}")
            }
        }
    }
}
