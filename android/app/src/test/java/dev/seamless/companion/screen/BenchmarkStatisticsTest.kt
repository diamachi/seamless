// Tests for BenchmarkStatisticsTest and the behavior owned by its target module.
// Keep assertions focused on externally visible results and failure boundaries.

package dev.seamless.companion.screen

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BenchmarkStatisticsTest {
    /** Checks measures elapsed time instead of assuming timer accuracy by exercising its expected result and a relevant invalid or boundary input. */
    @Test
    /** Builds measures elapsed time instead of assuming timer accuracy from deterministic test inputs and returns the protocol response. */
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
    /** Checks idle intervals do not reuse previous frame rate by exercising its expected result and a relevant invalid or boundary input. */
    @Test
    /** Builds idle intervals do not reuse previous frame rate from deterministic test inputs and returns the protocol response. */
    fun idleIntervalsDoNotReusePreviousFrameRate() {
        val statistics = BenchmarkStatistics(0)
        statistics.recordFrame(100, 10_000_000)
        val first = statistics.sample(1_000_000_000, BenchmarkSnapshot())!!
        val idle = statistics.sample(2_000_000_000, first)!!
        assertEquals(0.0, idle.encodedFramesPerSecond, 0.0)
        assertEquals(1, idle.totalFrames)
    }
    /** Checks waits for afull measurement interval by exercising its expected result and a relevant invalid or boundary input. */
    @Test
    /** Builds waits for afull measurement interval from deterministic test inputs and returns the protocol response. */
    fun waitsForAFullMeasurementInterval() {
        val statistics = BenchmarkStatistics(500_000_000)
        assertNull(statistics.sample(700_000_000, BenchmarkSnapshot()))
    }
}
