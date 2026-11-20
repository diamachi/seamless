// Android connection infrastructure for secure identity.
// See docs/ARCHITECTURE.md for the owning subsystem and cross-platform call flow.

package dev.seamless.companion.connection

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.math.BigInteger
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.cert.X509Certificate
import java.util.Date
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.net.ssl.SSLContext
import javax.net.ssl.X509ExtendedKeyManager
import javax.security.auth.x500.X500Principal

class SecureIdentity(context: Context) {
    private val preferences = context.getSharedPreferences("connection_identity", Context.MODE_PRIVATE)
    private val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
    val phoneID: String = preferences.getString("phone_id", null) ?: UUID.randomUUID().toString().also {
        preferences.edit().putString("phone_id", it).commit()
    }

    init {
        createIdentityIfNeeded()
        createStorageKeyIfNeeded()
    }

    val certificatePin: String
        get() = MessageDigest.getInstance("SHA-256").digest(keyStore.getCertificate(TLS_ALIAS).encoded)
            .joinToString("") { "%02x".format(it) }

    /** Creates the TLS context used by authenticated local connections. */
    fun createTLSContext(): SSLContext {
        val manager = object : X509ExtendedKeyManager() {
            /** Performs choose server alias for secure identity. */
            override fun chooseServerAlias(keyType: String?, issuers: Array<out java.security.Principal>?, socket: java.net.Socket?): String? {
                if (keyType == "EC") return TLS_ALIAS
                return null
            }
            /** Performs get server aliases for secure identity. */
            override fun getServerAliases(keyType: String?, issuers: Array<out java.security.Principal>?): Array<String>? {
                if (keyType == "EC") return arrayOf(TLS_ALIAS)
                return null
            }
            /** Performs get certificate chain for secure identity. */
            override fun getCertificateChain(alias: String?): Array<X509Certificate> = arrayOf(keyStore.getCertificate(TLS_ALIAS) as X509Certificate)
            /** Performs get private key for secure identity. */
            override fun getPrivateKey(alias: String?): PrivateKey = keyStore.getKey(TLS_ALIAS, null) as PrivateKey
            /** Performs get client aliases for secure identity. */
            override fun getClientAliases(keyType: String?, issuers: Array<out java.security.Principal>?): Array<String>? = null
            /** Performs choose client alias for secure identity. */
            override fun chooseClientAlias(keyTypes: Array<out String>?, issuers: Array<out java.security.Principal>?, socket: java.net.Socket?): String? = null
        }
        return SSLContext.getInstance("TLS").apply { init(arrayOf(manager), null, SecureRandom()) }
    }

    /** Persists a trusted peer credential after the approval handshake succeeds. */
    @Synchronized
    /** Handles store peer callback by translating the native window event into the owning app action. */
    fun storePeer(macID: String, credential: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, keyStore.getKey(STORAGE_ALIAS, null) as SecretKey)
        val record = JSONObject().put("iv", encode(cipher.iv)).put("ciphertext", encode(cipher.doFinal(credential.toByteArray())))
        check(preferences.edit().putString("peer.$macID", record.toString()).commit())
    }

    /** Looks up the retained credential for a previously trusted peer. */
    @Synchronized
    /** Handles peer credential callback by translating the native window event into the owning app action. */
    fun peerCredential(macID: String): String? {
        val encoded = preferences.getString("peer.$macID", null) ?: return null
        val record = JSONObject(encoded)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, keyStore.getKey(STORAGE_ALIAS, null) as SecretKey,
            GCMParameterSpec(128, Base64.decode(record.getString("iv"), Base64.NO_WRAP)))
        return String(cipher.doFinal(Base64.decode(record.getString("ciphertext"), Base64.NO_WRAP)), Charsets.UTF_8)
    }

    /** Deletes the stored credential so subsequent connections must pair again. */
    @Synchronized
    /** Handles revoke peer callback by translating the native window event into the owning app action. */
    fun revokePeer(macID: String) {
        check(preferences.edit().remove("peer.$macID").commit())
    }

    /** Evaluates has peer against the current model or supplied input. */
    fun hasPeer(macID: String): Boolean = preferences.contains("peer.$macID")

    /** Performs revoke all peers for secure identity. */
    @Synchronized
    /** Handles revoke all peers callback by translating the native window event into the owning app action. */
    fun revokeAllPeers() {
        val editor = preferences.edit()
        for (key in preferences.all.keys) {
            if (key.startsWith("peer.")) editor.remove(key)
        }
        check(editor.commit())
    }

    /** Creates the app’s persistent cryptographic identity only when no valid identity exists. */
    private fun createIdentityIfNeeded() {
        if (keyStore.containsAlias(TLS_ALIAS)) return
        val generator = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, "AndroidKeyStore")
        generator.initialize(KeyGenParameterSpec.Builder(TLS_ALIAS, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
            // Conscrypt supplies an already-hashed ECDSA message during the TLS handshake.
            .setDigests(KeyProperties.DIGEST_NONE, KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA384)
            .setCertificateSubject(X500Principal("CN=Seamless Android"))
            .setCertificateSerialNumber(BigInteger.ONE)
            .setCertificateNotBefore(Date(0))
            .setCertificateNotAfter(Date(4_102_444_800_000L))
            .build())
        generator.generateKeyPair()
    }

    /** Performs create storage key if needed for secure identity. */
    private fun createStorageKeyIfNeeded() {
        if (keyStore.containsAlias(STORAGE_ALIAS)) return
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(KeyGenParameterSpec.Builder(STORAGE_ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        generator.generateKey()
    }

    companion object {
        private const val TLS_ALIAS = "seamless_tls_identity_v2"
        private const val STORAGE_ALIAS = "seamless_peer_storage_v1"
        /** Performs random secret for secure identity. */
        fun randomSecret(): String {
            val bytes = ByteArray(32)
            SecureRandom().nextBytes(bytes)
            return encode(bytes)
        }
        /** Converts the local model into its wire or persisted representation. */
        private fun encode(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_WRAP)
        /** Compares secrets without an early return based on the first mismatched byte. */
        fun secretsMatch(expected: String, received: String): Boolean {
            return MessageDigest.isEqual(expected.toByteArray(Charsets.UTF_8), received.toByteArray(Charsets.UTF_8))
        }
    }
}
