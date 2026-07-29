package com.devground.daegubus.utils

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutoAlarmRuntimePolicyTest {
    @Test
    fun activeSameRouteIsAlwaysADuplicate() {
        assertTrue(
            AutoAlarmRuntimePolicy.isDuplicateStart(
                isAutoAlarmMode = true,
                activeRouteId = "route-1",
                requestedRouteId = "route-1",
            )
        )
    }

    @Test
    fun inactiveOrDifferentRouteIsNotADuplicate() {
        assertFalse(
            AutoAlarmRuntimePolicy.isDuplicateStart(
                isAutoAlarmMode = false,
                activeRouteId = "route-1",
                requestedRouteId = "route-1",
            )
        )
        assertFalse(
            AutoAlarmRuntimePolicy.isDuplicateStart(
                isAutoAlarmMode = true,
                activeRouteId = "route-1",
                requestedRouteId = "route-2",
            )
        )
    }

    @Test
    fun pendingOrActiveRouteBlocksConcurrentStart() {
        assertTrue(
            AutoAlarmRuntimePolicy.isPendingOrActive(
                routeId = "route-1",
                pendingRouteIds = setOf("route-1"),
                activeRouteIds = emptySet(),
            )
        )
        assertTrue(
            AutoAlarmRuntimePolicy.isPendingOrActive(
                routeId = "route-1",
                pendingRouteIds = emptySet(),
                activeRouteIds = setOf("route-1"),
            )
        )
        assertFalse(
            AutoAlarmRuntimePolicy.isPendingOrActive(
                routeId = "route-1",
                pendingRouteIds = emptySet(),
                activeRouteIds = emptySet(),
            )
        )
    }

    @Test
    fun timeoutStopsAtConfiguredBoundaryOnlyWhileActive() {
        assertFalse(
            AutoAlarmRuntimePolicy.hasTimedOut(
                isAutoAlarmMode = true,
                startTimeMillis = 1_000L,
                nowMillis = 10_999L,
                timeoutMillis = 10_000L,
            )
        )
        assertTrue(
            AutoAlarmRuntimePolicy.hasTimedOut(
                isAutoAlarmMode = true,
                startTimeMillis = 1_000L,
                nowMillis = 11_000L,
                timeoutMillis = 10_000L,
            )
        )
        assertFalse(
            AutoAlarmRuntimePolicy.hasTimedOut(
                isAutoAlarmMode = false,
                startTimeMillis = 1_000L,
                nowMillis = 20_000L,
                timeoutMillis = 10_000L,
            )
        )
    }
}
