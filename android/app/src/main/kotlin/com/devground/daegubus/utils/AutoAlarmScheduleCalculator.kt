package com.devground.daegubus.utils

import android.content.Context
import org.json.JSONArray
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

object AutoAlarmScheduleCalculator {
    const val EARLY_TRACKING_MINUTES = 5
    const val MAX_LATE_DELIVERY_MS = 2 * 60 * 60 * 1000L

    // 제외 날짜가 연휴로 이어질 수 있어 8일보다 넉넉히 탐색한다.
    private const val MAX_SEARCH_DAYS = 60

    fun mapCalendarDayToAlarmDay(dayOfWeek: Int): Int {
        return if (dayOfWeek == Calendar.SUNDAY) 7 else dayOfWeek - 1
    }

    /**
     * Flutter가 prefs(flutter.excluded_dates)로 내려둔 공휴일·커스텀 예외 날짜
     * ("yyyy-MM-dd" JSON 배열)를 읽는다. 없거나 파싱 실패면 빈 집합.
     */
    fun loadExcludedDates(context: Context): Set<String> {
        return try {
            val prefs = context.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            val raw = prefs.getString("flutter.excluded_dates", null) ?: return emptySet()
            val arr = JSONArray(raw)
            (0 until arr.length()).map { arr.getString(it) }.toSet()
        } catch (e: Exception) {
            emptySet()
        }
    }

    fun findNextTargetTime(
        nowMillis: Long,
        hour: Int,
        minute: Int,
        repeatDays: IntArray,
        excludedDates: Set<String> = emptySet(),
    ): Long? {
        if (repeatDays.isEmpty()) return null

        val dateFormat = SimpleDateFormat("yyyy-MM-dd", Locale.US)
        for (i in 0..MAX_SEARCH_DAYS) {
            val candidate = Calendar.getInstance().apply {
                timeInMillis = nowMillis
                add(Calendar.DAY_OF_YEAR, i)
                set(Calendar.HOUR_OF_DAY, hour)
                set(Calendar.MINUTE, minute)
                set(Calendar.SECOND, 0)
                set(Calendar.MILLISECOND, 0)
            }
            val mappedDay = mapCalendarDayToAlarmDay(candidate.get(Calendar.DAY_OF_WEEK))
            if (!repeatDays.contains(mappedDay) || candidate.timeInMillis <= nowMillis) continue
            if (excludedDates.isNotEmpty() &&
                dateFormat.format(Date(candidate.timeInMillis)) in excludedDates
            ) continue
            return candidate.timeInMillis
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
