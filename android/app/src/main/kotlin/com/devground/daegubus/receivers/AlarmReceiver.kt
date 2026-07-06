package com.devground.daegubus.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.devground.daegubus.services.BusAlertService
import com.devground.daegubus.utils.AutoAlarmScheduleCalculator

class AlarmReceiver : BroadcastReceiver() {
    private val TAG = "AlarmReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d(TAG, "🔔 알람 수신: $action")

        if (action == "com.devground.daegubus.AUTO_ALARM") {
            val currentTime = System.currentTimeMillis()
            val scheduledTime = intent.getLongExtra("scheduledTime", 0L)
            val targetAlarmTime = intent.getLongExtra("targetAlarmTime", 0L)

            // 오래된 알람만 폐기한다. 기준은 5분 전 사전추적 시각이 아니라 실제 알람 시각이다.
            if (!AutoAlarmScheduleCalculator.shouldStartDeliveredAlarm(currentTime, scheduledTime, targetAlarmTime)) {
                Log.w(TAG, "⚠️ 알람 장시간 지연, 재설정만 수행: scheduled=${java.util.Date(scheduledTime)}, target=${java.util.Date(targetAlarmTime)}, now=${java.util.Date(currentTime)}")
                val pendingResult = goAsync()
                Thread {
                    try { scheduleNextAlarmImmediate(context.applicationContext, intent) }
                    catch (e: Exception) { Log.e(TAG, "❌ 재설정 오류", e) }
                    finally { try { pendingResult.finish() } catch (_: Exception) {} }
                }.start()
                return
            }

            // 10초 초과 이른 도착 → setAlarmClock으로 재설정
            val earlyMs = scheduledTime - currentTime
            if (scheduledTime > 0 && earlyMs > 10000L) {
                Log.w(TAG, "⚠️ 알람 ${earlyMs/1000}초 이른 도착, 정확한 시각으로 재설정")
                val pendingResult = goAsync()
                Thread {
                    try { rescheduleForExactTime(context.applicationContext, intent, scheduledTime) }
                    catch (e: Exception) { Log.e(TAG, "❌ 재설정 오류", e) }
                    finally { try { pendingResult.finish() } catch (_: Exception) {} }
                }.start()
                return
            }

            // Android 14+: FGS 시작 허용 윈도우는 onReceive() 메인 스레드에서 가장 안전
            // goAsync()+Thread 조합 시 Samsung OneUI에서 허용 윈도우 만료 가능성 있음
            val busNo = intent.getStringExtra("busNo") ?: return
            val stationName = intent.getStringExtra("stationName") ?: return
            val routeId = intent.getStringExtra("routeId") ?: return
            val stationId = intent.getStringExtra("stationId") ?: return
            val useTTS = intent.getBooleanExtra("useTTS", true)
            val isCommuteAlarm = intent.getBooleanExtra("isCommuteAlarm", false)
            val alertOnArrivalOnly = intent.getBooleanExtra("alertOnArrivalOnly", false)
            val hour = intent.getIntExtra("hour", -1)
            val minute = intent.getIntExtra("minute", -1)

            val busIntent = Intent(context.applicationContext, BusAlertService::class.java).apply {
                this.action = BusAlertService.ACTION_START_AUTO_ALARM_LIGHTWEIGHT
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("remainingMinutes", -1)
                putExtra("currentStation", "")
                putExtra("useTTS", useTTS)
                putExtra("isCommuteAlarm", isCommuteAlarm)
                putExtra("alertOnArrivalOnly", alertOnArrivalOnly)
                putExtra("alarmHour", hour)
                putExtra("alarmMinute", minute)
                putExtra("targetAlarmTime", targetAlarmTime)
            }

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(busIntent)
                } else {
                    context.startService(busIntent)
                }
                Log.d(TAG, "✅ BusAlertService 시작 요청 완료 (메인 스레드)")
            } catch (e: Exception) {
                Log.e(TAG, "❌ BusAlertService 시작 실패: ${e.javaClass.simpleName}: ${e.message}", e)
            }

            // 다음 알람 재설정은 별도 스레드에서 처리
            val pendingResult = goAsync()
            Thread {
                try { scheduleNextAlarmImmediate(context.applicationContext, intent) }
                catch (e: Exception) { Log.e(TAG, "❌ 다음 알람 설정 오류", e) }
                finally { try { pendingResult.finish() } catch (_: Exception) {} }
            }.start()
        }
    }
    
    /** 정확한 시각으로 알람 재설정 (10초 초과 이른 도착 시) */
    private fun rescheduleForExactTime(context: Context, intent: Intent, scheduledTime: Long) {
        try {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                android.app.PendingIntent.getBroadcast(
                    context, intent.getIntExtra("alarmId", 0), intent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                )
            } else {
                android.app.PendingIntent.getBroadcast(
                    context, intent.getIntExtra("alarmId", 0), intent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT
                )
            }
            AutoAlarmScheduleCalculator.scheduleExactAlarm(
                alarmManager, scheduledTime, pendingIntent, TAG
            )
            Log.d(TAG, "⏰ 정확한 시각으로 재설정: ${java.util.Date(scheduledTime)}")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 정확한 시각 재설정 오류", e)
        }
    }

    /**
     * 다음 알람 즉시 재설정 - 반복 알람의 핵심 로직
     * AlarmManager를 사용하여 다음 알람을 바로 설정
     */
    private fun scheduleNextAlarmImmediate(context: Context, intent: Intent) {
        try {
            val alarmId = intent.getIntExtra("alarmId", 0)
            val busNo = intent.getStringExtra("busNo") ?: return
            val stationName = intent.getStringExtra("stationName") ?: return
            val routeId = intent.getStringExtra("routeId") ?: return
            val stationId = intent.getStringExtra("stationId") ?: return
            val useTTS = intent.getBooleanExtra("useTTS", true)
            val isCommuteAlarm = intent.getBooleanExtra("isCommuteAlarm", false)
            val alertOnArrivalOnly = intent.getBooleanExtra("alertOnArrivalOnly", false)
            val excludeHolidays = intent.getBooleanExtra("excludeHolidays", false)
            val hour = intent.getIntExtra("hour", 0)
            val minute = intent.getIntExtra("minute", 0)
            val repeatDays = intent.getIntArrayExtra("repeatDays") ?: return

            Log.d(TAG, "🔄 다음 자동 알람 즉시 재설정: ${busNo}번 버스, $hour:$minute, 반복 요일: ${repeatDays.joinToString(",")}, 공휴일 제외: $excludeHolidays")

            // 다음 알람 시간 계산 (공휴일 제외 알람은 Flutter가 내려둔 제외 날짜 반영)
            val nowMillis = System.currentTimeMillis()
            val excludedDates = if (excludeHolidays) {
                AutoAlarmScheduleCalculator.loadExcludedDates(context)
            } else {
                emptySet()
            }
            val nextTargetTime =
                AutoAlarmScheduleCalculator.findNextTargetTime(nowMillis, hour, minute, repeatDays, excludedDates)

            if (nextTargetTime == null) {
                Log.e(TAG, "❌ 다음 알람 시간을 찾을 수 없습니다")
                return
            }

            val trackingStartTime =
                AutoAlarmScheduleCalculator.trackingStartTime(nextTargetTime, nowMillis)
            Log.d(TAG, "⏰ 사전 추적: 원래 시간 ${hour}:${minute}, 실제 알람 ${java.util.Date(trackingStartTime)} (${AutoAlarmScheduleCalculator.EARLY_TRACKING_MINUTES}분 전), target=${java.util.Date(nextTargetTime)}")

            // AlarmManager로 다음 알람 설정
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager

            val nextAlarmIntent = Intent(context, AlarmReceiver::class.java).apply {
                action = "com.devground.daegubus.AUTO_ALARM"
                putExtra("alarmId", alarmId)
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("useTTS", useTTS)
                putExtra("isCommuteAlarm", isCommuteAlarm)
                putExtra("alertOnArrivalOnly", alertOnArrivalOnly)
                putExtra("excludeHolidays", excludeHolidays)
                putExtra("hour", hour)
                putExtra("minute", minute)
                putExtra("repeatDays", repeatDays)
                putExtra("scheduledTime", trackingStartTime)
                putExtra("targetAlarmTime", nextTargetTime)
            }

            val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                android.app.PendingIntent.getBroadcast(
                    context,
                    alarmId,
                    nextAlarmIntent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE
                )
            } else {
                android.app.PendingIntent.getBroadcast(
                    context,
                    alarmId,
                    nextAlarmIntent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT
                )
            }

            // 정확한 알람 설정 (권한 회수 시 부정확 알람으로 저하)
            AutoAlarmScheduleCalculator.scheduleExactAlarm(
                alarmManager, trackingStartTime, pendingIntent, TAG
            )

            Log.d(TAG, "✅ 다음 자동 알람 재설정 완료: ${busNo}번 버스, tracking=${java.util.Date(trackingStartTime)}, target=${java.util.Date(nextTargetTime)}")

        } catch (e: Exception) {
            Log.e(TAG, "❌ 다음 알람 즉시 재설정 오류", e)
        }
    }
}
