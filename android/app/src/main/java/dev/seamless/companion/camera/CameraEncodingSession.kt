package dev.seamless.companion.camera

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CaptureRequest
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.util.Base64
import android.view.Surface
import dev.seamless.companion.screen.MediaStreamSink
import org.json.JSONObject

class CameraEncodingSession(
    private val context: Context,
    private val handler: Handler,
    private val sink: MediaStreamSink,
    private val onFailure: (Exception) -> Unit
) : AutoCloseable {
    private var camera: CameraDevice? = null
    private var cameraSession: CameraCaptureSession? = null
    private var encoder: MediaCodec? = null
    private var surface: Surface? = null
    private var closed = false
    private var exposureEV = 0.0
    private var zoom = 1.0
    private var torch = false
    private var whiteBalance = "auto"
    private var repeatingRequest: CaptureRequest.Builder? = null
    private var characteristics: CameraCharacteristics? = null
    private val bufferInfo = MediaCodec.BufferInfo()
    private val drainTask = object : Runnable {
        override fun run() {
            if (closed) return
            try {
                drain()
                handler.postDelayed(this, 2)
            } catch (exception: Exception) { onFailure(exception) }
        }
    }

    fun start(facing: String, resolutionHeight: Int, framesPerSecond: Int, exposureEV: Double = 0.0, zoom: Double = 1.0, torch: Boolean = false, whiteBalance: String = "auto") {
        require(context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED)
        this.exposureEV = exposureEV
        this.zoom = zoom
        this.torch = torch
        this.whiteBalance = whiteBalance
        val manager = context.getSystemService(CameraManager::class.java)
        val requestedFacing = if (facing == "front") CameraCharacteristics.LENS_FACING_FRONT else CameraCharacteristics.LENS_FACING_BACK
        val cameraID = manager.cameraIdList.firstOrNull {
            manager.getCameraCharacteristics(it).get(CameraCharacteristics.LENS_FACING) == requestedFacing
        } ?: error("Requested camera is unavailable")
        val characteristics = manager.getCameraCharacteristics(cameraID)
        this.characteristics = characteristics
        val sizes = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)?.getOutputSizes(MediaCodec::class.java)
            ?: error("Camera does not advertise encoder outputs")
        val size = sizes.filter { minOf(it.width, it.height) == resolutionHeight }
            .minByOrNull { kotlin.math.abs(it.width.toDouble() / it.height - 16.0 / 9) }
            ?: error("This camera does not support the requested resolution. Try 720p or 1080p.")
        val rates = characteristics.get(CameraCharacteristics.CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES) ?: error("Camera frame rates are unavailable")
        val rate = rates.filter { it.lower <= framesPerSecond && it.upper >= framesPerSecond }.minByOrNull { it.upper - it.lower }
            ?: error("This camera cannot use $framesPerSecond fps in a normal capture session. Try 30 fps.")
        val format = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, size.width, size.height)
        format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
        format.setInteger(MediaFormat.KEY_FRAME_RATE, framesPerSecond)
        format.setInteger(MediaFormat.KEY_BIT_RATE, minOf(30_000_000, size.width * size.height * framesPerSecond / 8))
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        // A live webcam must not trade latency for offline encoding efficiency.
        format.setInteger(MediaFormat.KEY_PRIORITY, 0)
        if (Build.VERSION.SDK_INT >= 26) format.setInteger(MediaFormat.KEY_LATENCY, 0)
        if (Build.VERSION.SDK_INT >= 29) format.setInteger(MediaFormat.KEY_MAX_B_FRAMES, 0)
        format.setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
        if (Build.VERSION.SDK_INT >= 29) format.setFloat(MediaFormat.KEY_MAX_FPS_TO_ENCODER, framesPerSecond.toFloat())
        val codecName = chooseEncoder(format)
        val codec = MediaCodec.createByCodecName(codecName)
        encoder = codec
        codec.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        val inputSurface = codec.createInputSurface()
        surface = inputSurface
        codec.start()
        sink.requestKeyFrame = {
            handler.post {
                if (!closed) {
                    try { codec.setParameters(android.os.Bundle().apply { putInt(MediaCodec.PARAMETER_KEY_REQUEST_SYNC_FRAME, 0) }) }
                    catch (exception: Exception) { onFailure(exception) }
                }
            }
        }
        manager.openCamera(cameraID, object : CameraDevice.StateCallback() {
            override fun onOpened(device: CameraDevice) {
                if (closed) { device.close(); return }
                camera = device
                try { createCaptureSession(device, inputSurface, rate) }
                catch (exception: Exception) { onFailure(exception) }
            }
            override fun onDisconnected(device: CameraDevice) { device.close(); onFailure(IllegalStateException("Camera disconnected")) }
            override fun onError(device: CameraDevice, error: Int) { device.close(); onFailure(IllegalStateException("Camera could not start ($error)")) }
        }, handler)
        handler.post(drainTask)
    }

    private fun chooseEncoder(format: MediaFormat): String {
        val codecs = MediaCodecList(MediaCodecList.REGULAR_CODECS)
        if (Build.VERSION.SDK_INT >= 29) {
            for (codec in codecs.codecInfos) {
                if (!codec.isEncoder || !codec.isHardwareAccelerated) continue
                if (!codec.supportedTypes.contains(MediaFormat.MIMETYPE_VIDEO_AVC)) continue
                val supportsProfile = try {
                    codec.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).isFormatSupported(format)
                } catch (_: IllegalArgumentException) {
                    false
                }
                if (supportsProfile) return codec.name
            }
        }
        return codecs.findEncoderForFormat(format) ?: error("No encoder supports this camera profile")
    }

    @Suppress("DEPRECATION")
    private fun createCaptureSession(device: CameraDevice, inputSurface: Surface, rate: android.util.Range<Int>) {
        device.createCaptureSession(listOf(inputSurface), object : CameraCaptureSession.StateCallback() {
            override fun onConfigured(session: CameraCaptureSession) {
                if (closed) { session.close(); return }
                cameraSession = session
                try {
                    val request = device.createCaptureRequest(CameraDevice.TEMPLATE_RECORD)
                    request.addTarget(inputSurface)
                    request.set(CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE, rate)
                    repeatingRequest = request
                    applyControls(request)
                    session.setRepeatingRequest(request.build(), null, handler)
                } catch (exception: Exception) { onFailure(exception) }
            }
            override fun onConfigureFailed(session: CameraCaptureSession) { onFailure(IllegalStateException("Camera profile was rejected")) }
        }, handler)
    }

    fun updateControls(exposureEV: Double, zoom: Double, torch: Boolean, whiteBalance: String) {
        if (closed) return
        this.exposureEV = exposureEV
        this.zoom = zoom
        this.torch = torch
        this.whiteBalance = whiteBalance
        val request = repeatingRequest ?: return
        val activeSession = cameraSession ?: return
        applyControls(request)
        activeSession.setRepeatingRequest(request.build(), null, handler)
    }

    private fun applyControls(request: CaptureRequest.Builder) {
        val info = characteristics ?: return
        // High-quality temporal processing can add multiple frames before encoding.
        if (info.get(CameraCharacteristics.NOISE_REDUCTION_AVAILABLE_NOISE_REDUCTION_MODES)?.contains(CaptureRequest.NOISE_REDUCTION_MODE_FAST) == true) {
            request.set(CaptureRequest.NOISE_REDUCTION_MODE, CaptureRequest.NOISE_REDUCTION_MODE_FAST)
        }
        if (info.get(CameraCharacteristics.EDGE_AVAILABLE_EDGE_MODES)?.contains(CaptureRequest.EDGE_MODE_FAST) == true) {
            request.set(CaptureRequest.EDGE_MODE, CaptureRequest.EDGE_MODE_FAST)
        }
        val exposureRange = info.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_RANGE)
        val step = info.get(CameraCharacteristics.CONTROL_AE_COMPENSATION_STEP)?.toDouble() ?: 0.0
        if (exposureRange != null && step > 0) request.set(CaptureRequest.CONTROL_AE_EXPOSURE_COMPENSATION, (exposureEV / step).toInt().coerceIn(exposureRange.lower, exposureRange.upper))
        if (info.get(CameraCharacteristics.FLASH_INFO_AVAILABLE) == true) request.set(CaptureRequest.FLASH_MODE, if (torch) CaptureRequest.FLASH_MODE_TORCH else CaptureRequest.FLASH_MODE_OFF)
        val modes = mapOf("auto" to CaptureRequest.CONTROL_AWB_MODE_AUTO, "daylight" to CaptureRequest.CONTROL_AWB_MODE_DAYLIGHT, "cloudy" to CaptureRequest.CONTROL_AWB_MODE_CLOUDY_DAYLIGHT,
            "incandescent" to CaptureRequest.CONTROL_AWB_MODE_INCANDESCENT, "fluorescent" to CaptureRequest.CONTROL_AWB_MODE_FLUORESCENT)
        val mode = modes[whiteBalance] ?: CaptureRequest.CONTROL_AWB_MODE_AUTO
        val supportedWhiteBalance = info.get(CameraCharacteristics.CONTROL_AWB_AVAILABLE_MODES)
        if (supportedWhiteBalance?.contains(mode) == true) {
            request.set(CaptureRequest.CONTROL_AWB_MODE, mode)
        } else {
            request.set(CaptureRequest.CONTROL_AWB_MODE, CaptureRequest.CONTROL_AWB_MODE_AUTO)
        }
        val sensor = info.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
        val maximumZoom = info.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM)?.toDouble() ?: 1.0
        if (sensor != null && maximumZoom > 1.0) {
            val ratio = zoom.coerceIn(1.0, maximumZoom)
            val width = (sensor.width() / ratio).toInt()
            val height = (sensor.height() / ratio).toInt()
            val left = sensor.left + (sensor.width() - width) / 2
            val top = sensor.top + (sensor.height() - height) / 2
            request.set(CaptureRequest.SCALER_CROP_REGION, android.graphics.Rect(left, top, left + width, top + height))
        }
    }

    override fun close() {
        if (closed) return
        closed = true
        handler.removeCallbacks(drainTask)
        cameraSession?.close()
        camera?.close()
        try { encoder?.stop() } finally {
            encoder?.release()
            surface?.release()
            sink.close()
        }
    }

    private fun drain() {
        val codec = encoder ?: return
        for (index in 0 until 32) {
            val output = codec.dequeueOutputBuffer(bufferInfo, 0)
            if (output == MediaCodec.INFO_TRY_AGAIN_LATER) break
            if (output == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                val format = codec.outputFormat
                val description = JSONObject().put("width", format.getInteger("width")).put("height", format.getInteger("height")).put("encoder", codec.name)
                for (key in listOf("csd-0", "csd-1")) {
                    val bytes = format.getByteBuffer(key)?.duplicate() ?: continue
                    val content = ByteArray(bytes.remaining())
                    bytes.get(content)
                    description.put(key, Base64.encodeToString(content, Base64.NO_WRAP))
                }
                sink.configure(description)
            }
            if (output >= 0) {
                if (bufferInfo.size > 0 && bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG == 0) {
                    val buffer = codec.getOutputBuffer(output)?.duplicate()
                    if (buffer != null) {
                        buffer.position(bufferInfo.offset)
                        buffer.limit(bufferInfo.offset + bufferInfo.size)
                        val bytes = ByteArray(bufferInfo.size)
                        buffer.get(bytes)
                        sink.offer(bytes, bufferInfo.presentationTimeUs, bufferInfo.flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0)
                    }
                }
                codec.releaseOutputBuffer(output, false)
            }
        }
    }
}
