package dev.seamless.companion.features

import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

internal object PairingEnvelope {
    fun seal(content: ByteArray, key: ByteArray, sessionID: String, purpose: String): ByteArray {
        require(key.size == 32)
        val nonce = ByteArray(12)
        SecureRandom().nextBytes(nonce)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, nonce))
        cipher.updateAAD(context(sessionID, purpose))
        return nonce + cipher.doFinal(content)
    }

    fun open(combined: ByteArray, key: ByteArray, sessionID: String, purpose: String): ByteArray {
        require(key.size == 32 && combined.size in 28..24_000)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), GCMParameterSpec(128, combined.copyOfRange(0, 12)))
        cipher.updateAAD(context(sessionID, purpose))
        return cipher.doFinal(combined, 12, combined.size - 12)
    }

    private fun context(sessionID: String, purpose: String) = "Seamless QR pairing v1:$sessionID:$purpose".toByteArray(Charsets.UTF_8)
}
