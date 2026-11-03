package dev.seamless.companion.connection

import android.app.ActivityManager
import android.app.usage.StorageStatsManager
import android.content.Context
import android.os.Build
import android.os.Environment
import android.os.StatFs
import android.os.SystemClock
import android.os.storage.StorageManager
import org.json.JSONObject

internal object DeviceDetails {
    private var cached: JSONObject? = null
    private var sampledAt = 0L

    @Synchronized
    fun snapshot(context: Context): JSONObject {
        val now = SystemClock.elapsedRealtime()
        val previous = cached
        if (previous != null && now - sampledAt < 60_000) {
            return JSONObject(previous.toString())
        }
        val result = JSONObject()
            .put("processorName", processorName())
            .put("operatingSystemName", operatingSystemName())
            .put("buildName", Build.DISPLAY.take(120))
        addMemory(context, result)
        addStorage(context, result)
        cached = result
        sampledAt = now
        return JSONObject(result.toString())
    }

    private fun processorName(): String {
        if (Build.VERSION.SDK_INT >= 31) {
            val model = reportedName(Build.SOC_MODEL)
            val manufacturer = reportedName(Build.SOC_MANUFACTURER)
            if (model != null && manufacturer != null && !model.startsWith(manufacturer, ignoreCase = true)) {
                return "$manufacturer $model"
            }
            if (model != null) {
                return model
            }
        }
        return reportedName(Build.HARDWARE) ?: "Unknown"
    }

    private fun reportedName(value: String): String? {
        val name = value.trim().take(120)
        if (name.isEmpty() || name.equals(Build.UNKNOWN, ignoreCase = true)) {
            return null
        }
        return name
    }

    private fun operatingSystemName(): String {
        val display = Build.DISPLAY.lowercase()
        // A manufacturer name alone cannot identify the OS installed on a custom-ROM phone.
        val buildNames = mapOf(
            "lineage" to "LineageOS", "crdroid" to "crDroid",
            "oxygenos" to "OxygenOS", "nothingos" to "Nothing OS", "nothing os" to "Nothing OS"
        )
        for ((identifier, name) in buildNames) {
            if (display.contains(identifier)) {
                return name
            }
        }
        return "Android"
    }

    private fun addMemory(context: Context, result: JSONObject) {
        try {
            val information = ActivityManager.MemoryInfo()
            context.getSystemService(ActivityManager::class.java).getMemoryInfo(information)
            var total = information.totalMem
            if (Build.VERSION.SDK_INT >= 34 && information.advertisedMem > 0) {
                total = information.advertisedMem
            }
            result.put("ramTotalBytes", total)
        } catch (_: RuntimeException) {
            // Missing details must never interrupt status or pairing.
        }
    }

    private fun addStorage(context: Context, result: JSONObject) {
        if (Build.VERSION.SDK_INT >= 26) {
            try {
                val storage = context.getSystemService(StorageStatsManager::class.java)
                val total = storage.getTotalBytes(StorageManager.UUID_DEFAULT)
                val free = storage.getFreeBytes(StorageManager.UUID_DEFAULT)
                if (total > 0) {
                    result.put("storageTotalBytes", total)
                    result.put("storageUsedBytes", (total - free).coerceIn(0, total))
                    result.put("storageLabel", "Internal storage")
                    return
                }
            } catch (_: Exception) {
                // Older devices and OEM services may only expose filesystem capacity.
            }
        }
        try {
            val storage = StatFs(Environment.getDataDirectory().absolutePath)
            result.put("storageTotalBytes", storage.totalBytes)
            result.put("storageUsedBytes", (storage.totalBytes - storage.availableBytes).coerceAtLeast(0))
            result.put("storageLabel", "Data volume")
        } catch (_: RuntimeException) {
            // The Mac will show an unavailable value until a later successful sample.
        }
    }
}
