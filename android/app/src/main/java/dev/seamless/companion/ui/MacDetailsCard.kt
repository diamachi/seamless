package dev.seamless.companion.ui

import android.text.format.Formatter
import kotlin.math.roundToInt
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import dev.seamless.companion.connection.ConnectedMacDetails

@Composable
internal fun MacDetailsCard(name: String, details: ConnectedMacDetails?) {
    val context = LocalContext.current
    CompanionCard(name) {
        Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            MacBookIllustration()
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(details?.deviceFamily ?: "Mac", style = MaterialTheme.typography.titleLarge)
                Text(details?.operatingSystem ?: "Trusted Mac connected", color = MaterialTheme.colorScheme.onSurfaceVariant)
                if (details != null) {
                    Text(details.processor.ifBlank { details.architecture }, style = MaterialTheme.typography.bodyMedium)
                    if (details.ramBytes > 0) Text("${(details.ramBytes / 1073741824.0).roundToInt()} GB RAM", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
        if (details != null && details.storageTotalBytes > 0) {
            val used = details.storageUsedBytes.coerceIn(0, details.storageTotalBytes)
            Text("Storage · ${Formatter.formatFileSize(context, used)} of ${Formatter.formatFileSize(context, details.storageTotalBytes)} used",
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            LinearProgressIndicator(progress = { used.toFloat() / details.storageTotalBytes.toFloat() }, modifier = Modifier.fillMaxWidth().height(4.dp))
        }
    }
}

@Composable
private fun MacBookIllustration() {
    val frame = MaterialTheme.colorScheme.outline
    val screen = MaterialTheme.colorScheme.primary
    val screenLight = MaterialTheme.colorScheme.secondaryContainer
    Canvas(Modifier.size(width = 96.dp, height = 76.dp)) {
        val left = size.width * 0.12f
        val top = size.height * 0.10f
        val width = size.width * 0.76f
        val height = size.height * 0.68f
        drawRoundRect(frame, Offset(left, top), Size(width, height), CornerRadius(5.dp.toPx()))
        drawRoundRect(Brush.linearGradient(listOf(screenLight, screen)), Offset(left + 3.dp.toPx(), top + 3.dp.toPx()),
            Size(width - 6.dp.toPx(), height - 6.dp.toPx()), CornerRadius(3.dp.toPx()))
        drawRoundRect(frame, Offset(size.width * 0.03f, size.height * 0.81f), Size(size.width * 0.94f, size.height * 0.07f), CornerRadius(3.dp.toPx()))
    }
}
