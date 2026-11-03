package dev.seamless.companion.features

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BulkExchangePolicyTest {
    @Test fun filenamesCannotEscapeTheChosenDestination() {
        for (name in listOf("", ".", "..", "../file", "folder/file", "folder\\file", "bad\u0000name")) {
            assertFalse(BulkExchange.validName(name))
        }
        assertTrue(BulkExchange.validName("Holiday video 100 GB.mp4"))
    }
    @Test fun protocolRangeDoesNotImposeAnEightGigabyteCap() {
        assertTrue(BulkExchange.MAXIMUM_BYTES > 100_000_000_000L)
    }
}
