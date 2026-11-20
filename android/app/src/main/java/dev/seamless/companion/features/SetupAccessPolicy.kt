// Android feature implementation for setup access policy.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

package dev.seamless.companion.features

object SetupAccessPolicy {
    const val stepCount = 4
    /** Finds the next setup permission that has not yet been granted. */
    fun nextMissingStep(access: CompanionPermissions, start: Int): Int {
        return (start.coerceAtLeast(0) until stepCount).firstOrNull { !isAllowed(access, it) } ?: stepCount
    }
    /** Evaluates is allowed against the current model or supplied input. */
    fun isAllowed(access: CompanionPermissions, step: Int): Boolean = when (step) {
        0 -> access.notificationSharing
        1 -> access.phoneControl
        2 -> access.storage
        3 -> access.battery
        else -> true
    }
}
