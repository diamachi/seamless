package dev.seamless.companion.connection

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import android.os.SystemClock
import org.json.JSONObject

object PhoneStatus {
    fun snapshot(context: Context, phoneID: String): JSONObject {
        val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = battery?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = battery?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val percentage = if (level >= 0 && scale > 0) level * 100 / scale else -1
        val chargingState = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1)
        val isCharging = chargingState == BatteryManager.BATTERY_STATUS_CHARGING || chargingState == BatteryManager.BATTERY_STATUS_FULL
        return JSONObject().put("phoneID", phoneID).put("model", Build.MODEL)
            .put("androidVersion", Build.VERSION.RELEASE).put("apiLevel", Build.VERSION.SDK_INT)
            .put("batteryPercent", percentage).put("isCharging", isCharging)
            .put("macDetailsVersion", 1).put("permissions", dev.seamless.companion.features.CompanionPermissions.read(context).toJson())
            .put("bulkVersion", 1).put("storageBrowserVersion", 1)
            .put("uptimeSeconds", SystemClock.elapsedRealtime() / 1000)
            .put("deviceDetails", DeviceDetails.snapshot(context))
    }
}
