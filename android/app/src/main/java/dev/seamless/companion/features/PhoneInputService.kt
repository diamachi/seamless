// Android feature implementation for phone input service.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

package dev.seamless.companion.features

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.json.JSONObject

class PhoneInputService : AccessibilityService() {
    /** Performs on service connected for phone input service. */
    override fun onServiceConnected() { current = this }
    /** Performs on accessibility event for phone input service. */
    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    /** Performs on interrupt for phone input service. */
    override fun onInterrupt() {}
    /** Releases this component’s resources when Android destroys it; ownership checks protect replacement sessions. */
    override fun onDestroy() { current = null; super.onDestroy() }

    /** Performs handle for phone input service. */
    private fun handle(payload: JSONObject) {
        when (payload.getString("kind")) {
            "forward" -> rootInActiveWindow?.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
            "back" -> performGlobalAction(GLOBAL_ACTION_BACK)
            "home" -> performGlobalAction(GLOBAL_ACTION_HOME)
            "recents" -> performGlobalAction(GLOBAL_ACTION_RECENTS)
            "text" -> {
                val focused = rootInActiveWindow?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT) ?: return
                val arguments = Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, payload.getString("text").take(4000))
                }
                focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
            }
            "tap", "swipe" -> dispatchTouch(payload)
        }
    }

    /** Performs dispatch touch for phone input service. */
    private fun dispatchTouch(payload: JSONObject) {
        val metrics = resources.displayMetrics
        /** Performs coordinate for phone input service. */
        fun coordinate(key: String, dimension: Int): Float {
            val value = payload.getDouble(key)
            require(value.isFinite() && value in 0.0..1.0)
            return (value * (dimension - 1)).toFloat()
        }
        val path = Path()
        path.moveTo(coordinate("x", metrics.widthPixels), coordinate("y", metrics.heightPixels))
        val isSwipe = payload.getString("kind") == "swipe"
        if (isSwipe) path.lineTo(coordinate("endX", metrics.widthPixels), coordinate("endY", metrics.heightPixels))
        val duration = if (isSwipe) 250L else 40L
        dispatchGesture(GestureDescription.Builder().addStroke(GestureDescription.StrokeDescription(path, 0, duration)).build(), null, null)
    }

    companion object {
        /** Performs submit for phone input service. */
        @Volatile private var current: PhoneInputService? = null
        /** Handles submit callback by translating the native window event into the owning app action. */
        fun submit(payload: JSONObject): Boolean {
            val service = current ?: return false
            Handler(Looper.getMainLooper()).post {
                try { service.handle(payload) } catch (_: Exception) { }
            }
            return true
        }
    }
}
