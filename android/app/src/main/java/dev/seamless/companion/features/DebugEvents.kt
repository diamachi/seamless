// Android feature implementation for debug events.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

package dev.seamless.companion.features

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Bounded in-memory diagnostics; record event names rather than private payloads. */
object DebugEvents {
    val enabled = MutableStateFlow(false)
    private val mutableLines = MutableStateFlow<List<String>>(emptyList())
    val lines = mutableLines.asStateFlow()

    /** Performs record for debug events. */
    @Synchronized
    /** Handles record callback by translating the native window event into the owning app action. */
    fun record(event: String) {
        if (!enabled.value) return
        val timestamp = java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.ROOT).format(java.util.Date())
        mutableLines.value = (mutableLines.value + (timestamp + "  " + event)).takeLast(500)
    }

    /** Clears the collection owned by this component. */
    @Synchronized
    /** Handles clear callback by translating the native window event into the owning app action. */
    fun clear() { mutableLines.value = emptyList() }
}
