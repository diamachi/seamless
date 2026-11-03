package dev.seamless.companion.features

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test
import java.util.Base64

class PairingEnvelopeTest {
    private val key = ByteArray(32) { it.toByte() }
    private val session = "11111111-2222-3333-4444-555555555555"

    @Test fun decryptsSwiftEnvelopeAndRejectsWrongPurpose() {
        val combined = Base64.getDecoder().decode("AAECAwQFBgcICQoLNGe3dqmAsWi8e+Ty350QCPe/5BmEHiwIFQ6L83QdYcZof8AqElQqVsbSqRwad9IFwcqg")
        assertEquals("seamless1:synthetic-test-invitation", String(PairingEnvelope.open(combined, key, session, "request"), Charsets.UTF_8))
        try {
            PairingEnvelope.open(combined, key, session, "ack")
            fail("A request must not authenticate as an acknowledgement")
        } catch (_: javax.crypto.AEADBadTagException) { }
    }

    @Test fun tamperingCannotChangeAcceptedInvitation() {
        val content = "private-test-invitation".toByteArray()
        val sealed = PairingEnvelope.seal(content, key, session, "request")
        assertArrayEquals(content, PairingEnvelope.open(sealed, key, session, "request"))
        sealed[15] = (sealed[15].toInt() xor 1).toByte()
        try {
            PairingEnvelope.open(sealed, key, session, "request")
            fail("Modified ciphertext must be rejected")
        } catch (_: javax.crypto.AEADBadTagException) { }
    }
}
