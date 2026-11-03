package dev.seamless.companion.features

import android.util.Base64
import org.json.JSONObject
import java.util.UUID

internal data class MacQrPairingOffer(val sessionID: String, val name: String, val addresses: List<String>, val port: Int, val key: ByteArray) {
    companion object {
        fun parse(text: String): MacQrPairingOffer {
            require(text.startsWith("seamlessmac1:") && text.length <= 16_384) { "This is not a Seamless Mac pairing QR code" }
            val data = Base64.decode(text.removePrefix("seamlessmac1:"), Base64.NO_WRAP)
            val payload = JSONObject(String(data, Charsets.UTF_8))
            require(payload.getInt("version") == 1) { "Unsupported pairing QR version" }
            val session = payload.getString("sessionID")
            require(UUID.fromString(session).toString() == session)
            val name = payload.getString("name")
            require(name.isNotBlank() && name.length <= 120)
            val port = payload.getInt("port")
            require(port in 1..65535)
            val key = Base64.decode(payload.getString("key"), Base64.NO_WRAP)
            require(key.size == 32)
            val addresses = payload.getJSONArray("addresses")
            require(addresses.length() in 1..8)
            val hosts = mutableListOf<String>()
            for (index in 0 until addresses.length()) {
                val host = addresses.getString(index)
                val octets = host.split('.')
                require(octets.size == 4 && octets.all { part ->
                    val number = part.toIntOrNull()
                    if (number == null) false else number in 0..255 && part == number.toString()
                }) { "Invalid local address in QR" }
                require(!host.startsWith("127.") && !host.startsWith("0.") && !host.startsWith("169.254."))
                hosts.add(host)
            }
            return MacQrPairingOffer(session, name, hosts, port, key)
        }
    }
}
