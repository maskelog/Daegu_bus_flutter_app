package com.devground.daegubus.utils

object ManualTrackingRuntimePolicy {
    const val MAX_DURATION_MS = 2 * 60 * 60 * 1000L

    fun hasTimedOut(
        isAutoAlarm: Boolean,
        startedAtElapsedRealtimeMillis: Long,
        nowElapsedRealtimeMillis: Long,
    ): Boolean =
        !isAutoAlarm &&
            startedAtElapsedRealtimeMillis > 0L &&
            nowElapsedRealtimeMillis - startedAtElapsedRealtimeMillis >= MAX_DURATION_MS
}
