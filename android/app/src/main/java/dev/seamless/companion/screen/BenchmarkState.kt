// Android screen-capture pipeline for benchmark state.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

package dev.seamless.companion.screen

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

object BenchmarkState {
    private val mutableSnapshot = MutableStateFlow(BenchmarkSnapshot())
    val snapshot = mutableSnapshot.asStateFlow()

    /** Performs publish for benchmark state. */
    fun publish(snapshot: BenchmarkSnapshot) {
        mutableSnapshot.value = snapshot
    }
}
