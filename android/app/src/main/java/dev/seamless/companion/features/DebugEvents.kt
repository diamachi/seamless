package dev.seamless.companion.features

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Bounded in-memory diagnostics; record event names rather than private payloads. */
object DebugEvents {
    val enabled = MutableStateFlow(false)
    private val mutableLines = MutableStateFlow<List<String>>(emptyList())
    val lines = mutableLines.asStateFlow()

    @Synchronized
    fun record(event: String) {
        if (!enabled.value) return
        val timestamp = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.ROOT).format(java.util.Date())
        mutableLines.value = (mutableLines.value + (timestamp + "  " + event)).takeLast(500)
    }

    @Synchronized
    fun clear() { mutableLines.value = emptyList() }
}
