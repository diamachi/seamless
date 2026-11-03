package dev.seamless.companion.screen

data class BenchmarkSnapshot(
    val isRunning: Boolean = false,
    val message: String = "Ready to measure screen encoding",
    val encoderName: String = "Not selected",
    val resolution: String = "Not selected",
    val requestedFramesPerSecond: Int = 60,
    val encodedFramesPerSecond: Double = 0.0,
    val peakEncodedFramesPerSecond: Double = 0.0,
    val averageEncodedFramesPerSecond: Double = 0.0,
    val encodedMegabitsPerSecond: Double = 0.0,
    val totalFrames: Long = 0,
    val elapsedSeconds: Long = 0,
    val longestOutputGapMilliseconds: Double = 0.0
)

class BenchmarkStatistics(private val startedAtNanoseconds: Long) {
    private var totalFrames = 0L
    private var intervalFrames = 0L
    private var intervalBytes = 0L
    private var intervalStartedAt = startedAtNanoseconds
    private var previousFrameAt: Long? = null
    private var longestOutputGapNanoseconds = 0L

    fun recordFrame(sizeBytes: Int, nowNanoseconds: Long) {
        val previous = previousFrameAt
        if (previous != null) {
            longestOutputGapNanoseconds = maxOf(longestOutputGapNanoseconds, nowNanoseconds - previous)
        }
        previousFrameAt = nowNanoseconds
        totalFrames += 1
        intervalFrames += 1
        intervalBytes += sizeBytes
    }

    fun sample(nowNanoseconds: Long, previous: BenchmarkSnapshot): BenchmarkSnapshot? {
        val intervalNanoseconds = nowNanoseconds - intervalStartedAt
        if (intervalNanoseconds < 1_000_000_000L) {
            return null
        }
        val intervalSeconds = intervalNanoseconds / 1_000_000_000.0
        val snapshot = previous.copy(
            encodedFramesPerSecond = intervalFrames / intervalSeconds,
            peakEncodedFramesPerSecond = maxOf(previous.peakEncodedFramesPerSecond, intervalFrames / intervalSeconds),
            averageEncodedFramesPerSecond = totalFrames / ((nowNanoseconds - startedAtNanoseconds) / 1_000_000_000.0),
            encodedMegabitsPerSecond = intervalBytes * 8.0 / intervalSeconds / 1_000_000.0,
            totalFrames = totalFrames,
            elapsedSeconds = (nowNanoseconds - startedAtNanoseconds) / 1_000_000_000L,
            longestOutputGapMilliseconds = longestOutputGapNanoseconds / 1_000_000.0
        )
        intervalStartedAt = nowNanoseconds
        intervalFrames = 0
        intervalBytes = 0
        return snapshot
    }
}
