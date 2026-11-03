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

    fun createTLSContext(): SSLContext {
        val manager = object : X509ExtendedKeyManager() {
            override fun chooseServerAlias(keyType: String?, issuers: Array<out java.security.Principal>?, socket: java.net.Socket?): String? {
                if (keyType == "EC") return TLS_ALIAS
                return null
            }
            override fun getServerAliases(keyType: String?, issuers: Array<out java.security.Principal>?): Array<String>? {
                if (keyType == "EC") return arrayOf(TLS_ALIAS)
                return null
            }
            override fun getCertificateChain(alias: String?): Array<X509Certificate> = arrayOf(keyStore.getCertificate(TLS_ALIAS) as X509Certificate)
            override fun getPrivateKey(alias: String?): PrivateKey = keyStore.getKey(TLS_ALIAS, null) as PrivateKey
            override fun getClientAliases(keyType: String?, issuers: Array<out java.security.Principal>?): Array<String>? = null
            override fun chooseClientAlias(keyTypes: Array<out String>?, issuers: Array<out java.security.Principal>?, socket: java.net.Socket?): String? = null
        }
        return SSLContext.getInstance("TLS").apply { init(arrayOf(manager), null, SecureRandom()) }
    }

    @Synchronized
    fun storePeer(macID: String, credential: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, keyStore.getKey(STORAGE_ALIAS, null) as SecretKey)
        val record = JSONObject().put("iv", encode(cipher.iv)).put("ciphertext", encode(cipher.doFinal(credential.toByteArray())))
        check(preferences.edit().putString("peer.$macID", record.toString()).commit())
    }

    @Synchronized
    fun peerCredential(macID: String): String? {
        val encoded = preferences.getString("peer.$macID", null) ?: return null
        val record = JSONObject(encoded)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, keyStore.getKey(STORAGE_ALIAS, null) as SecretKey,
            GCMParameterSpec(128, Base64.decode(record.getString("iv"), Base64.NO_WRAP)))
        return String(cipher.doFinal(Base64.decode(record.getString("ciphertext"), Base64.NO_WRAP)), Charsets.UTF_8)
    }

    @Synchronized
    fun revokePeer(macID: String) {
        check(preferences.edit().remove("peer.$macID").commit())
    }

    fun hasPeer(macID: String): Boolean = preferences.contains("peer.$macID")

    @Synchronized
    fun revokeAllPeers() {
        val editor = preferences.edit()
        for (key in preferences.all.keys) {
            if (key.startsWith("peer.")) editor.remove(key)
        }
        check(editor.commit())
    }

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
        fun randomSecret(): String {
            val bytes = ByteArray(32)
            SecureRandom().nextBytes(bytes)
            return encode(bytes)
        }
        private fun encode(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_WRAP)
        fun secretsMatch(expected: String, received: String): Boolean {
            return MessageDigest.isEqual(expected.toByteArray(Charsets.UTF_8), received.toByteArray(Charsets.UTF_8))
        }
    }
}
