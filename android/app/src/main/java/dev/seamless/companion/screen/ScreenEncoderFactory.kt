package dev.seamless.companion.screen

import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaFormat
import android.os.Build
import kotlin.math.roundToInt

data class ScreenEncodingConfiguration(
    val encoderName: String,
    val width: Int,
    val height: Int,
    val framesPerSecond: Int,
    val bitrate: Int
)

object ScreenEncoderFactory {
    fun selectConfiguration(
        displayWidth: Int,
        displayHeight: Int,
        requestedFramesPerSecond: Int,
        maximumDimension: Int
    ): ScreenEncodingConfiguration {
        require(requestedFramesPerSecond == 60 || requestedFramesPerSecond == 120)
        require(maximumDimension == 1280 || maximumDimension == 1920)
        val scale = minOf(1.0, maximumDimension.toDouble() / maxOf(displayWidth, displayHeight))
        val requestedWidth = (displayWidth * scale).roundToInt()
        val requestedHeight = (displayHeight * scale).roundToInt()

        for (codec in MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos) {
            if (!codec.isEncoder || !codec.supportedTypes.contains(MediaFormat.MIMETYPE_VIDEO_AVC)) {
                continue
            }
            if (!isHardwareEncoder(codec)) {
                continue
            }
            val capabilities = codec.getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC)
            if (!capabilities.colorFormats.contains(MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)) {
                continue
            }
            val video = capabilities.videoCapabilities
                ?: continue
            val width = alignDown(requestedWidth, video.widthAlignment)
            val height = alignDown(requestedHeight, video.heightAlignment)
            if (!video.areSizeAndRateSupported(width, height, requestedFramesPerSecond.toDouble())) {
                continue
            }
            val preferredBitrate = width.toLong() * height * requestedFramesPerSecond / 8
            val bitrate = video.bitrateRange.clamp(preferredBitrate.coerceIn(2_000_000, 40_000_000).toInt())
            return ScreenEncodingConfiguration(codec.name, width, height, requestedFramesPerSecond, bitrate)
        }
        error("No hardware H.264 encoder advertises this resolution at $requestedFramesPerSecond fps. Try the smaller profile or 60 fps.")
    }

    fun create(configuration: ScreenEncodingConfiguration): MediaCodec {
        val format = MediaFormat.createVideoFormat(
            MediaFormat.MIMETYPE_VIDEO_AVC, configuration.width, configuration.height
        )
        format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
        format.setInteger(MediaFormat.KEY_BIT_RATE, configuration.bitrate)
        format.setInteger(MediaFormat.KEY_FRAME_RATE, configuration.framesPerSecond)
        if (Build.VERSION.SDK_INT >= 29) {
            // KEY_FRAME_RATE is a rate-control hint, not a limit on incoming Surface frames.
            format.setFloat(MediaFormat.KEY_MAX_FPS_TO_ENCODER, configuration.framesPerSecond.toFloat())
        }
        format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        // Reordered frames increase interactive delay, so use a profile without B frames.
        format.setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
        val encoder = MediaCodec.createByCodecName(configuration.encoderName)
        try {
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
        } catch (exception: Exception) {
            encoder.release()
            throw exception
        }
        return encoder
    }

    private fun alignDown(value: Int, alignment: Int): Int {
        return maxOf(alignment, value / alignment * alignment)
    }

    private fun isHardwareEncoder(codec: MediaCodecInfo): Boolean {
        if (Build.VERSION.SDK_INT >= 29) {
            return codec.isHardwareAccelerated
        }
        // Older Android lacks the hardware flag; exclude known software implementations.
        val name = codec.name.lowercase()
        return !name.startsWith("omx.google.") && !name.startsWith("c2.android.") && !name.startsWith("omx.ffmpeg.")
    }
}
