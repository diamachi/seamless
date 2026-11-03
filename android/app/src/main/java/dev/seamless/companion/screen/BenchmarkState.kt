package dev.seamless.companion.screen

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

object BenchmarkState {
    private val mutableSnapshot = MutableStateFlow(BenchmarkSnapshot())
    val snapshot = mutableSnapshot.asStateFlow()

    fun publish(snapshot: BenchmarkSnapshot) {
        mutableSnapshot.value = snapshot
    }
}
