package dev.seamless.companion.features

object SetupAccessPolicy {
    const val stepCount = 4
    fun nextMissingStep(access: CompanionPermissions, start: Int): Int {
        return (start.coerceAtLeast(0) until stepCount).firstOrNull { !isAllowed(access, it) } ?: stepCount
    }
    fun isAllowed(access: CompanionPermissions, step: Int): Boolean = when (step) {
        0 -> access.notificationSharing
        1 -> access.phoneControl
        2 -> access.storage
        3 -> access.battery
        else -> true
    }
}
