package com.devground.daegubus.utils

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ManualTrackingRuntimePolicyTest {
    @Test
    fun manualTrackingContinuesBeforeSafetyLimit() {
        assertFalse(
            ManualTrackingRuntimePolicy.hasTimedOut(
                isAutoAlarm = false,
                startedAtElapsedRealtimeMillis = 1_000L,
                nowElapsedRealtimeMillis = 1_000L +
                    ManualTrackingRuntimePolicy.MAX_DURATION_MS - 1L,
            )
        )
    }

    @Test
    fun manualTrackingStopsAtSafetyLimit() {
        assertTrue(
            ManualTrackingRuntimePolicy.hasTimedOut(
                isAutoAlarm = false,
                startedAtElapsedRealtimeMillis = 1_000L,
                nowElapsedRealtimeMillis = 1_000L +
                    ManualTrackingRuntimePolicy.MAX_DURATION_MS,
            )
        )
    }

    @Test
    fun autoAlarmUsesItsOwnConfigurableTimeout() {
        assertFalse(
            ManualTrackingRuntimePolicy.hasTimedOut(
                isAutoAlarm = true,
                startedAtElapsedRealtimeMillis = 1_000L,
                nowElapsedRealtimeMillis = 1_000L +
                    ManualTrackingRuntimePolicy.MAX_DURATION_MS,
            )
        )
    }
}
