package dev.seamless.companion.ui

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

@Composable
fun BenchmarkAnimation() {
    val transition = rememberInfiniteTransition(label = "Controlled capture workload")
    val progress by transition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(tween(2000, easing = LinearEasing), RepeatMode.Restart),
        label = "Moving pattern"
    )
    Canvas(Modifier.fillMaxWidth().height(200.dp)) {
        drawRect(Color(0xFF102D40))
        for (index in 0 until 16) {
            val horizontalPosition = ((index / 16f + progress) % 1f) * size.width
            drawLine(
                color = Color(0xFF5CDBD3),
                start = Offset(horizontalPosition, 0f),
                end = Offset(size.width - horizontalPosition, size.height),
                strokeWidth = 4f
            )
        }
        drawCircle(Color(0xFFFFD166), radius = 20.dp.toPx(), center = Offset(progress * size.width, size.height / 2))
    }
}
