package com.devground.daegubus.utils

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StationIdPolicyTest {
    @Test
    fun acceptsOnlyDaeguStationIds() {
        assertTrue(StationIdPolicy.isValid("7012345678"))
        assertFalse(StationIdPolicy.isValid(""))
        assertFalse(StationIdPolicy.isValid("12345"))
        assertFalse(StationIdPolicy.isValid("8012345678"))
        assertFalse(StationIdPolicy.isValid("7abcdefghi"))
    }
}
