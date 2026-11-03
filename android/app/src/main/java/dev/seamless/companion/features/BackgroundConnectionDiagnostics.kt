package dev.seamless.companion.features

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build

internal object BackgroundConnectionDiagnostics {
    fun summary(context: Context): String {
        if (Build.VERSION.SDK_INT < 30) return "System exit diagnostics require Android 11 or newer."
        return try {
            val manager = context.getSystemService(ActivityManager::class.java)
            val lastExit = manager.getHistoricalProcessExitReasons(context.packageName, 0, 1).firstOrNull()
                ?: return "No previous process exit reported by Android."
            val reason = when (lastExit.reason) {
                ApplicationExitInfo.REASON_CRASH, ApplicationExitInfo.REASON_CRASH_NATIVE -> "app crash"
                ApplicationExitInfo.REASON_ANR -> "app stopped responding"
                ApplicationExitInfo.REASON_LOW_MEMORY -> "memory pressure"
                ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE -> "resource limit"
                ApplicationExitInfo.REASON_USER_REQUESTED -> "user or system app stop"
                ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "permission change"
                ApplicationExitInfo.REASON_SIGNALED -> "process terminated by the system"
                else -> "system reason ${lastExit.reason}"
            }
            "Previous process exit: $reason. This describes the previous run, not necessarily the current connection."
        } catch (_: Exception) {
            "Android did not provide process exit diagnostics."
        }
    }
}
