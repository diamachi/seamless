package dev.seamless.companion.features

import android.graphics.Bitmap
import android.graphics.Canvas
import android.util.Base64
import java.io.ByteArrayOutputStream
import android.app.Notification
import android.app.RemoteInput
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.Process
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import dev.seamless.companion.connection.ConnectionRuntime
import org.json.JSONArray
import org.json.JSONObject

class NotificationRelay : NotificationListenerService() {
    override fun onListenerConnected() { activeListener = this }
    override fun onListenerDisconnected() { activeListener = null }

    override fun onNotificationRemoved(notification: StatusBarNotification) {
        val profile = notification.user.hashCode().toString()
        ConnectionRuntime.server?.relayNotificationRemoval(notification.packageName, profile,
            JSONObject().put("notificationKey", notification.key))
    }

    override fun onNotificationPosted(notification: StatusBarNotification) {
        val content = notification.notification
        if (notification.packageName == packageName && content.flags and Notification.FLAG_FOREGROUND_SERVICE != 0) return
        val notificationProfile = notification.user.hashCode().toString()
        val payload = JSONObject().put("packageName", notification.packageName)
            .put("profileIdentifier", notificationProfile).put("notificationKey", notification.key)
            .put("title", content.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.take(500) ?: "Notification")
            .put("text", content.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.take(4000) ?: "")
        val actions = JSONArray()
        content.actions?.forEachIndexed { index, action ->
            actions.put(JSONObject().put("index", index).put("title", action.title.toString().take(100))
                .put("supportsReply", action.remoteInputs?.any { it.allowFreeFormInput } == true))
        }
        payload.put("actions", actions)
        applicationIcon(this, notification.packageName)?.let { payload.put("icon", it) }
        ConnectionRuntime.server?.relayNotification(notification.packageName, notificationProfile, payload)
    }

    companion object {
        @Volatile private var activeListener: NotificationRelay? = null
        fun profileID(): String = Process.myUserHandle().hashCode().toString()

        fun applicationInventory(context: Context): JSONObject {
            val launcher = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            val applications = context.packageManager.queryIntentActivities(launcher, 0)
                .distinctBy { it.activityInfo.packageName }
                .sortedBy { it.loadLabel(context.packageManager).toString().lowercase() }
            val array = JSONArray()
            var remainingIconCharacters = 100_000
            for (application in applications.take(500)) {
                val entry = JSONObject().put("packageName", application.activityInfo.packageName)
                    .put("profileIdentifier", profileID()).put("name", application.loadLabel(context.packageManager).toString().take(120))
                val icon = applicationIcon(context, application.activityInfo.packageName)
                if (icon != null && icon.length <= remainingIconCharacters) {
                    entry.put("icon", icon)
                    remainingIconCharacters -= icon.length
                }
                array.put(entry)
            }
            return JSONObject().put("applications", array)
        }

        private fun applicationIcon(context: Context, packageName: String): String? {
            return try {
                val drawable = context.packageManager.getApplicationIcon(packageName)
                val bitmap = Bitmap.createBitmap(48, 48, Bitmap.Config.ARGB_8888)
                drawable.setBounds(0, 0, 48, 48)
                drawable.draw(Canvas(bitmap))
                val output = ByteArrayOutputStream()
                bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)
                bitmap.recycle()
                val imageBytes = output.toByteArray()
                // Leave room for app names and policy data in the bounded control frame.
                if (imageBytes.size > 6000) {
                    null
                } else {
                    Base64.encodeToString(imageBytes, Base64.NO_WRAP)
                }
            } catch (_: Exception) {
                null
            }
        }

        fun performAction(context: Context, payload: JSONObject) {
            val listener = activeListener ?: error("Notification access is unavailable")
            val notification = listener.activeNotifications.firstOrNull {
                it.key == payload.getString("notificationKey") && it.packageName == payload.getString("packageName") &&
                    it.user.hashCode().toString() == payload.getString("profileIdentifier")
            } ?: error("Notification is no longer available")
            if (payload.optBoolean("dismiss")) {
                listener.cancelNotification(notification.key)
                return
            }
            val action = notification.notification.actions?.getOrNull(payload.getInt("index")) ?: error("Action unavailable")
            val intent = Intent()
            val text = payload.optString("replyText").take(4000)
            if (text.isNotEmpty()) {
                val inputs = action.remoteInputs ?: error("Reply unavailable")
                val results = Bundle()
                for (input in inputs) {
                    if (input.allowFreeFormInput) results.putCharSequence(input.resultKey, text)
                }
                RemoteInput.addResultsToIntent(inputs, intent, results)
            }
            action.actionIntent.send(context, 0, intent)
        }
    }
}
