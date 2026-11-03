package dev.seamless.companion.ui

import android.os.Build
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.Checkbox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import dev.seamless.companion.screen.BenchmarkSnapshot
import java.util.Locale

@Composable
fun CompanionScreen(
    benchmark: BenchmarkSnapshot,
    initialFrameRate: Int,
    initialMaximumDimension: Int,
    onProfileChanged: (Int, Int) -> Unit,
    onStartBenchmark: () -> Unit,
    onStopBenchmark: () -> Unit
) {
    var frameRate by rememberSaveable { mutableIntStateOf(initialFrameRate) }
    var maximumDimension by rememberSaveable { mutableIntStateOf(initialMaximumDimension) }
    var controlledAnimation by rememberSaveable { mutableStateOf(true) }
    Scaffold { insets ->
        Column(
            modifier = Modifier.fillMaxSize().padding(insets).verticalScroll(rememberScrollState()).padding(24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Text("Seamless", style = MaterialTheme.typography.headlineLarge)
            Text("Your Android, connected to your Mac.", style = MaterialTheme.typography.bodyLarge)
            Text("${Build.MANUFACTURER} ${Build.MODEL} · Android ${Build.VERSION.RELEASE} · API ${Build.VERSION.SDK_INT}")
            Text("Screen performance lab", style = MaterialTheme.typography.titleLarge)
            Row {
                Checkbox(checked = controlledAnimation, onCheckedChange = { controlledAnimation = it })
                Text("Show controlled animation during capture")
            }
            if (controlledAnimation && benchmark.isRunning) {
                BenchmarkAnimation()
                Text("Keep this animation visible for comparable results. Whole-session averages include startup and idle time.")
            }
            Text("Measure local encoding or inspect an approved Mac screen-sharing session. Developer Options can stay off.")
            Text("Requested frame rate")
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                for (option in listOf(60, 120)) {
                    FilterChip(
                        selected = if (benchmark.isRunning) {
                            benchmark.requestedFramesPerSecond == option
                        } else {
                            frameRate == option
                        },
                        enabled = !benchmark.isRunning,
                        onClick = {
                            frameRate = option
                            onProfileChanged(frameRate, maximumDimension)
                        },
                        label = { Text("$option fps") }
                    )
                }
            }
            Text("Maximum screen dimension · aspect ratio preserved")
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                for (option in listOf(1280, 1920)) {
                    FilterChip(
                        selected = maximumDimension == option,
                        enabled = !benchmark.isRunning,
                        onClick = {
                            maximumDimension = option
                            onProfileChanged(frameRate, maximumDimension)
                        },
                        label = { Text("$option px") }
                    )
                }
            }
            if (benchmark.isRunning) {
                OutlinedButton(onClick = onStopBenchmark) { Text("Stop benchmark") }
            } else {
                Button(onClick = onStartBenchmark) { Text("Start screen benchmark") }
            }
            BenchmarkResults(benchmark)
            Text("For a useful result, approve sharing your entire screen, then scroll or play an animation in another app. Static screens naturally produce fewer frames. Return here to inspect results; stop from the notification or Android sharing indicator.")
            Text("These numbers measure encoder output, not Mac presentation or end-to-end latency. 120 fps is experimental and depends on real capture and hardware support.", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
private fun BenchmarkResults(benchmark: BenchmarkSnapshot) {
    Card(modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(benchmark.message, style = MaterialTheme.typography.titleSmall)
            Text("Encoder: ${benchmark.encoderName}")
            Text("Resolution: ${benchmark.resolution}")
            Text("Requested: ${benchmark.requestedFramesPerSecond} fps")
            if (Build.VERSION.SDK_INT < 29) {
                Text("On this Android version, the requested rate is a hint; input-rate limiting is unavailable in this prototype.")
            }
            Text(String.format(Locale.US, "Encoder output: %.1f fps · %.2f Mbps", benchmark.encodedFramesPerSecond, benchmark.encodedMegabitsPerSecond))
            Text(String.format(Locale.US, "Peak interval: %.1f fps · session average: %.1f fps", benchmark.peakEncodedFramesPerSecond, benchmark.averageEncodedFramesPerSecond))
            Text("${benchmark.totalFrames} encoded frames · ${benchmark.elapsedSeconds} seconds")
            Text(String.format(Locale.US, "Longest output gap (includes static content): %.1f ms", benchmark.longestOutputGapMilliseconds))
        }
    }
}
