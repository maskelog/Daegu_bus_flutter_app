package com.devground.daegubus.utils

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

class AutoAlarmScheduleCalculatorTest {
    @Test
    fun schedulesNextMorningFromPreviousEvening() {
        val now = Calendar.getInstance().apply {
            set(2026, Calendar.JANUARY, 14, 20, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val target = AutoAlarmScheduleCalculator.findNextTargetTime(
            nowMillis = now.timeInMillis,
            hour = 7,
            minute = 0,
            repeatDays = intArrayOf(4),
        )

        val expected = Calendar.getInstance().apply {
            set(2026, Calendar.JANUARY, 15, 7, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        assertEquals(expected.timeInMillis, target)
    }

    @Test
    fun tracksFiveMinutesBeforeTargetAlarm() {
        val target = Calendar.getInstance().apply {
            set(2026, Calendar.JANUARY, 15, 7, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val now = Calendar.getInstance().apply {
            set(2026, Calendar.JANUARY, 14, 20, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }

        val trackingStart = AutoAlarmScheduleCalculator.trackingStartTime(
            targetTimeMillis = target.timeInMillis,
            nowMillis = now.timeInMillis,
        )

        val expected = Calendar.getInstance().apply {
            set(2026, Calendar.JANUARY, 15, 6, 55, 0)
            set(Calendar.MILLISECOND, 0)
        }
        assertEquals(expected.timeInMillis, trackingStart)
    }

    @Test
    fun lateDeliveryUsesTargetAlarmTimeNotEarlyTrackingTime() {
        val target = Calendar.getInstance().apply {
            set(2026, Calendar.JANUARY, 15, 7, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val trackingStart = Calendar.getInstance().apply {
            set(2026, Calendar.JANUARY, 15, 6, 55, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val deliveredAt = Calendar.getInstance().apply {
            set(2026, Calendar.JANUARY, 15, 7, 11, 0)
            set(Calendar.MILLISECOND, 0)
        }

        assertTrue(
            AutoAlarmScheduleCalculator.shouldStartDeliveredAlarm(
                nowMillis = deliveredAt.timeInMillis,
                scheduledTrackingTimeMillis = trackingStart.timeInMillis,
                targetAlarmTimeMillis = target.timeInMillis,
            )
        )
    }

    @Test
    fun skipsVeryOldAlarmDelivery() {
        val target = Calendar.getInstance().apply {
            set(2026, Calendar.JANUARY, 15, 7, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val deliveredAt = Calendar.getInstance().apply {
            set(2026, Calendar.JANUARY, 15, 10, 0, 0)
            set(Calendar.MILLISECOND, 0)
        }

        assertFalse(
            AutoAlarmScheduleCalculator.shouldStartDeliveredAlarm(
                nowMillis = deliveredAt.timeInMillis,
                scheduledTrackingTimeMillis = target.timeInMillis,
                targetAlarmTimeMillis = target.timeInMillis,
            )
        )
    }

    @Test
    fun chainingAfterEarlyTrackingSkipsTheOccurrenceThatJustFired() {
        val deliveredTarget = Calendar.getInstance().apply {
            set(2026, Calendar.JULY, 28, 17, 35, 0)
            set(Calendar.MILLISECOND, 0)
        }
        val deliveredAt = Calendar.getInstance().apply {
            set(2026, Calendar.JULY, 28, 17, 30, 0)
            set(Calendar.MILLISECOND, 0)
        }

        val nextTarget = AutoAlarmScheduleCalculator.findNextTargetTimeAfterOccurrence(
            nowMillis = deliveredAt.timeInMillis,
            deliveredTargetTimeMillis = deliveredTarget.timeInMillis,
            hour = 17,
            minute = 35,
            repeatDays = intArrayOf(2, 3),
        )

        val expected = Calendar.getInstance().apply {
            set(2026, Calendar.JULY, 29, 17, 35, 0)
            set(Calendar.MILLISECOND, 0)
        }
        assertEquals(expected.timeInMillis, nextTarget)
    }
}
