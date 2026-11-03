package dev.seamless.companion.screen

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BenchmarkStatisticsTest {
    @Test
    fun measuresElapsedTimeInsteadOfAssumingTimerAccuracy() {
        val statistics = BenchmarkStatistics(0)
        repeat(120) { index ->
            statistics.recordFrame(1_000, (index + 1) * 16_666_666L)
        }
        val snapshot = statistics.sample(2_000_000_000L, BenchmarkSnapshot())!!
        assertEquals(60.0, snapshot.encodedFramesPerSecond, 0.001)
        assertEquals(0.48, snapshot.encodedMegabitsPerSecond, 0.001)
        assertEquals(120, snapshot.totalFrames)
        assertEquals(2, snapshot.elapsedSeconds)
    }

    @Test
    fun idleIntervalsDoNotReusePreviousFrameRate() {
        val statistics = BenchmarkStatistics(0)
        statistics.recordFrame(100, 10_000_000)
        val first = statistics.sample(1_000_000_000, BenchmarkSnapshot())!!
        val idle = statistics.sample(2_000_000_000, first)!!
        assertEquals(0.0, idle.encodedFramesPerSecond, 0.0)
        assertEquals(1, idle.totalFrames)
    }

    @Test
    fun waitsForAFullMeasurementInterval() {
        val statistics = BenchmarkStatistics(500_000_000)
        assertNull(statistics.sample(700_000_000, BenchmarkSnapshot()))
    }
}
