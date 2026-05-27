package com.devground.daegubus.utils

import java.util.Calendar

object AutoAlarmScheduleCalculator {
    const val EARLY_TRACKING_MINUTES = 5
    const val MAX_LATE_DELIVERY_MS = 2 * 60 * 60 * 1000L

    fun mapCalendarDayToAlarmDay(dayOfWeek: Int): Int {
        return if (dayOfWeek == Calendar.SUNDAY) 7 else dayOfWeek - 1
    }

    fun findNextTargetTime(
        nowMillis: Long,
        hour: Int,
        minute: Int,
        repeatDays: IntArray,
    ): Long? {
        if (repeatDays.isEmpty()) return null

        for (i in 0..7) {
            val candidate = Calendar.getInstance().apply {
                timeInMillis = nowMillis
                add(Calendar.DAY_OF_YEAR, i)
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val mappedDay = mapCalendarDayToAlarmDay(candidate.get(Calendar.DAY_OF_WEEK))
            if (repeatDays.contains(mappedDay) && candidate.timeInMillis > nowMillis) {
                return candidate.timeInMillis
            }
        }

        return null
    }

    fun trackingStartTime(targetTimeMillis: Long, nowMillis: Long): Long {
        val earlyTime = targetTimeMillis - EARLY_TRACKING_MINUTES * 60 * 1000L
        return if (earlyTime < nowMillis && targetTimeMillis > nowMillis) {
            nowMillis + 3000L
        } else {
            earlyTime
        }
    }

    fun shouldStartDeliveredAlarm(
        nowMillis: Long,
        scheduledTrackingTimeMillis: Long,
        targetAlarmTimeMillis: Long,
    ): Boolean {
        val referenceTime = when {
            targetAlarmTimeMillis > 0L -> targetAlarmTimeMillis
            scheduledTrackingTimeMillis > 0L -> scheduledTrackingTimeMillis
            else -> return true
        }

        return nowMillis - referenceTime <= MAX_LATE_DELIVERY_MS
    }
}
