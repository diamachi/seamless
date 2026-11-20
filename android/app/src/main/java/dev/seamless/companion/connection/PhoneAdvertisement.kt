// Android connection infrastructure for phone advertisement.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

package dev.seamless.companion.connection

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo

/** Discovery locates a phone; the pinned TLS handshake remains the trust boundary. */
internal class PhoneAdvertisement(context: Context) : AutoCloseable {
    private val manager = context.getSystemService(NsdManager::class.java)
    private var listener: NsdManager.RegistrationListener? = null

    /** Starts this component’s operation using the provided session inputs. */
    @Synchronized
    /** Handles start callback by translating the native window event into the owning app action. */
    fun start(phoneID: String, port: Int, reconnectRequest: String? = null) {
        if (listener != null) {
            return
        }
        val registration = object : NsdManager.RegistrationListener {
            /** Performs on service registered for phone advertisement. */
            override fun onServiceRegistered(service: NsdServiceInfo) {}
            /** Performs on service unregistered for phone advertisement. */
            override fun onServiceUnregistered(service: NsdServiceInfo) {}
            /** Performs on registration failed for phone advertisement. */
            override fun onRegistrationFailed(service: NsdServiceInfo, errorCode: Int) {
                synchronized(this@PhoneAdvertisement) {
                    listener = null
                }
            }
            /** Performs on unregistration failed for phone advertisement. */
            override fun onUnregistrationFailed(service: NsdServiceInfo, errorCode: Int) {}
        }
        val service = NsdServiceInfo().apply {
            serviceName = "Seamless-$phoneID"
            serviceType = "_seamless._tcp."
            setPort(port)
            if (reconnectRequest != null) setAttribute("reconnect", reconnectRequest)
        }
        listener = registration
        try {
            manager.registerService(service, NsdManager.PROTOCOL_DNS_SD, registration)
        } catch (_: RuntimeException) {
            // Manual invitation addresses still work when multicast discovery is unavailable.
            listener = null
        }
    }

    /** Closes owned resources so sockets, buffers and pending work do not outlive their session. */
    @Synchronized
    override fun close() {
        val registration = listener ?: return
        listener = null
        try {
            manager.unregisterService(registration)
        } catch (_: IllegalArgumentException) {
            // Registration may have failed asynchronously before teardown.
        }
    }
}
