package dev.seamless.companion.features

import android.Manifest
import android.accessibilityservice.AccessibilityServiceInfo
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import android.view.accessibility.AccessibilityManager
import org.json.JSONObject

data class CompanionPermissions(
    val camera: Boolean,
    val notifications: Boolean,
    val notificationSharing: Boolean,
    val phoneControl: Boolean,
    val storage: Boolean,
    val battery: Boolean
) {
    fun toJson(): JSONObject = JSONObject().put("camera", camera).put("notifications", notifications)
        .put("notificationSharing", notificationSharing).put("phoneControl", phoneControl)
        .put("storage", storage).put("battery", battery)

    companion object {
        fun read(context: Context): CompanionPermissions {
            val listeners = Settings.Secure.getString(context.contentResolver, "enabled_notification_listeners").orEmpty()
                .split(":").mapNotNull { ComponentName.unflattenFromString(it) }
            val accessibility = context.getSystemService(AccessibilityManager::class.java)
            val control = accessibility.getEnabledAccessibilityServiceList(AccessibilityServiceInfo.FEEDBACK_ALL_MASK)
                .any { it.resolveInfo.serviceInfo.packageName == context.packageName && it.resolveInfo.serviceInfo.name == PhoneInputService::class.java.name }
            val fullStorage = if (Build.VERSION.SDK_INT >= 30) {
                Environment.isExternalStorageManager() && context.getSharedPreferences("shared_storage", Context.MODE_PRIVATE).getBoolean("full_access_enabled", false)
            } else {
                false
            }
            return CompanionPermissions(
                camera = context.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED,
                notifications = context.getSystemService(NotificationManager::class.java).areNotificationsEnabled(),
                notificationSharing = listeners.any { it.packageName == context.packageName },
                phoneControl = control,
                storage = fullStorage || context.contentResolver.persistedUriPermissions.any { it.isReadPermission },
                battery = context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)
            )
        }
    }
}
