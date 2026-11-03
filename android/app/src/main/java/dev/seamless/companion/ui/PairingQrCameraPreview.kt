package dev.seamless.companion.ui

import android.util.Size
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.zxing.BarcodeFormat
import com.google.zxing.BinaryBitmap
import com.google.zxing.DecodeHintType
import com.google.zxing.MultiFormatReader
import com.google.zxing.PlanarYUVLuminanceSource
import com.google.zxing.ReaderException
import com.google.zxing.common.HybridBinarizer
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

@Composable
internal fun PairingQrCameraPreview(modifier: Modifier, onCode: (String) -> Unit, onError: (String) -> Unit) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current
    val previewView = remember { PreviewView(context).apply { implementationMode = PreviewView.ImplementationMode.COMPATIBLE } }
    AndroidView(factory = { previewView }, modifier = modifier)
    DisposableEffect(previewView, lifecycle) {
        val disposed = AtomicBoolean(false)
        val worker = Executors.newSingleThreadExecutor()
        val main = ContextCompat.getMainExecutor(context)
        val future = ProcessCameraProvider.getInstance(context)
        var provider: ProcessCameraProvider? = null
        val preview = Preview.Builder().build()
        val resolution = ResolutionSelector.Builder().setResolutionStrategy(
            ResolutionStrategy(Size(1280, 720), ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER_THEN_HIGHER)).build()
        val analysis = ImageAnalysis.Builder().setResolutionSelector(resolution)
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
        val reader = PairingQrFrameReader { code -> main.execute { if (!disposed.get()) onCode(code) } }
        analysis.setAnalyzer(worker, reader)
        future.addListener({
            if (!disposed.get()) {
                try {
                    provider = future.get()
                    preview.setSurfaceProvider(previewView.surfaceProvider)
                    provider?.bindToLifecycle(lifecycle, CameraSelector.DEFAULT_BACK_CAMERA, preview, analysis)
                } catch (exception: Exception) {
                    onError("Could not open the camera. Close other camera sessions and try again.")
                }
            }
        }, main)
        onDispose {
            disposed.set(true)
            analysis.clearAnalyzer()
            provider?.unbind(preview, analysis)
            worker.shutdownNow()
        }
    }
}

private class PairingQrFrameReader(private val onCode: (String) -> Unit) : ImageAnalysis.Analyzer {
    private val reader = MultiFormatReader().apply {
        setHints(mapOf(DecodeHintType.POSSIBLE_FORMATS to listOf(BarcodeFormat.QR_CODE), DecodeHintType.TRY_HARDER to true))
    }
    private var lastScan = 0L
    private var found = false

    override fun analyze(image: ImageProxy) {
        try {
            val now = android.os.SystemClock.elapsedRealtime()
            if (found || now - lastScan < 250) return
            lastScan = now
            val plane = image.planes[0]
            val buffer = plane.buffer
            val origin = buffer.position()
            val luminance = ByteArray(image.width * image.height)
            for (row in 0 until image.height) {
                for (column in 0 until image.width) {
                    luminance[row * image.width + column] = buffer.get(origin + row * plane.rowStride + column * plane.pixelStride)
                }
            }
            val source = PlanarYUVLuminanceSource(luminance, image.width, image.height, 0, 0, image.width, image.height, false)
            val code = reader.decodeWithState(BinaryBitmap(HybridBinarizer(source))).text
            if (code.startsWith("seamlessmac1:") && code.length <= 16_384) {
                found = true
                onCode(code)
            }
        } catch (_: ReaderException) {
            // Most preview frames contain no complete QR; keep scanning quietly.
        } catch (_: IllegalArgumentException) {
            // A transient incomplete camera plane should not end the scan.
        } finally {
            reader.reset()
            image.close()
        }
    }
}
