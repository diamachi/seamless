package dev.seamless.companion.features

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class SetupAccessPolicyTest {
    @Test fun existingGrantsAreSkippedWithoutAnotherRequest() {
        val access = CompanionPermissions(true, true, true, false, true, true)
        assertEquals(1, SetupAccessPolicy.nextMissingStep(access, 0))
        assertEquals(4, SetupAccessPolicy.nextMissingStep(access.copy(phoneControl = true), 0))
    }
    @Test fun skippedFeatureDoesNotBecomeGranted() {
        val access = CompanionPermissions(false, false, false, false, false, false)
        assertEquals(0, SetupAccessPolicy.nextMissingStep(access, 0))
        assertEquals(1, SetupAccessPolicy.nextMissingStep(access, 1))
        assertFalse(access.notificationSharing)
    }
}
