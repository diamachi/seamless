// Tests for BulkExchangePolicyTest and the behavior owned by its target module.
// Keep assertions focused on externally visible results and failure boundaries.

package dev.seamless.companion.features

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BulkExchangePolicyTest {
    /** Checks filenames cannot escape the chosen destination by exercising the valid case and the relevant rejection boundary. */
    @Test fun filenamesCannotEscapeTheChosenDestination() {
        for (name in listOf("", ".", "..", "../file", "folder/file", "folder\\file", "bad\u0000name")) {
            assertFalse(BulkExchange.validName(name))
        }
        assertTrue(BulkExchange.validName("Holiday video 100 GB.mp4"))
    }
    /** Checks protocol range does not impose an eight gigabyte cap by exercising the valid case and the relevant rejection boundary. */
    @Test fun protocolRangeDoesNotImposeAnEightGigabyteCap() {
        assertTrue(BulkExchange.MAXIMUM_BYTES > 100_000_000_000L)
    }
}
