package com.devground.daegubus.utils

object AutoAlarmRuntimePolicy {
    fun isPendingOrActive(
        routeId: String,
        pendingRouteIds: Set<String>,
        activeRouteIds: Set<String>,
    ): Boolean =
        routeId.isNotBlank() &&
            (routeId in pendingRouteIds || routeId in activeRouteIds)

    fun isDuplicateStart(
        isAutoAlarmMode: Boolean,
        activeRouteId: String,
        requestedRouteId: String,
    ): Boolean =
        isAutoAlarmMode &&
            requestedRouteId.isNotBlank() &&
            activeRouteId == requestedRouteId

    fun hasTimedOut(
        isAutoAlarmMode: Boolean,
        startTimeMillis: Long,
        nowMillis: Long,
        timeoutMillis: Long,
    ): Boolean =
        isAutoAlarmMode &&
            startTimeMillis > 0L &&
            nowMillis - startTimeMillis >= timeoutMillis
}
