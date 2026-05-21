package com.devground.daegubus.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.devground.daegubus.services.BusAlertService
import com.devground.daegubus.services.TTSService

class AlarmReceiver : BroadcastReceiver() {
    private val TAG = "AlarmReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d(TAG, "🔔 알람 수신: $action")

        if (action == "com.devground.daegubus.AUTO_ALARM") {
            val currentTime = System.currentTimeMillis()
            val scheduledTime = intent.getLongExtra("scheduledTime", 0L)

            // 15분 초과 지연 → 서비스 시작 없이 재설정만
            if (scheduledTime > 0 && (currentTime - scheduledTime) > 900000L) {
                Log.w(TAG, "⚠️ 알람 15분 초과 지연, 재설정만 수행")
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAlarmClock(android.app.AlarmManager.AlarmClockInfo(scheduledTime, pendingIntent), pendingIntent)
            } else {
                alarmManager.setExact(android.app.AlarmManager.RTC_WAKEUP, scheduledTime, pendingIntent)
            }
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
            val hour = intent.getIntExtra("hour", 0)
            val minute = intent.getIntExtra("minute", 0)
            val repeatDays = intent.getIntArrayExtra("repeatDays") ?: return

            Log.d(TAG, "🔄 다음 자동 알람 즉시 재설정: ${busNo}번 버스, $hour:$minute, 반복 요일: ${repeatDays.joinToString(",")}")

            // 다음 알람 시간 계산
            val calendar = java.util.Calendar.getInstance()
            calendar.set(java.util.Calendar.HOUR_OF_DAY, hour)
            calendar.set(java.util.Calendar.MINUTE, minute)
            calendar.set(java.util.Calendar.SECOND, 0)
            calendar.set(java.util.Calendar.MILLISECOND, 0)

            // 다음 유효한 알람 날짜 찾기
            var nextAlarmSet = false
            for (i in 1..7) {
                val testCalendar = java.util.Calendar.getInstance()
                testCalendar.add(java.util.Calendar.DAY_OF_YEAR, i)
                val testDay = testCalendar.get(java.util.Calendar.DAY_OF_WEEK)
                val testDayMapped = if (testDay == java.util.Calendar.SUNDAY) 7 else testDay - 1

                if (repeatDays.contains(testDayMapped)) {
                    calendar.add(java.util.Calendar.DAY_OF_YEAR, i)
                    nextAlarmSet = true
                    Log.d(TAG, "✅ 다음 알람 시간 계산됨: ${calendar.time}, 요일: $testDayMapped (${i}일 후)")
                    break
                }
            }

            if (!nextAlarmSet) {
                Log.e(TAG, "❌ 다음 알람 시간을 찾을 수 없습니다")
                return
            }

            // 사전 추적: 설정 시간 5분 전부터 추적 시작 (버스 놓침 방지)
            val EARLY_TRACKING_MINUTES = 5
            calendar.add(java.util.Calendar.MINUTE, -EARLY_TRACKING_MINUTES)
            Log.d(TAG, "⏰ 사전 추적: 원래 시간 ${hour}:${minute}, 실제 알람 ${calendar.time} (${EARLY_TRACKING_MINUTES}분 전)")

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
                putExtra("hour", hour)
                putExtra("minute", minute)
                putExtra("repeatDays", repeatDays)
                putExtra("scheduledTime", calendar.timeInMillis)
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

            // 정확한 알람 설정
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAlarmClock(
                    android.app.AlarmManager.AlarmClockInfo(calendar.timeInMillis, pendingIntent),
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    android.app.AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            }

            Log.d(TAG, "✅ 다음 자동 알람 재설정 완료: ${busNo}번 버스, ${calendar.time}")

        } catch (e: Exception) {
            Log.e(TAG, "❌ 다음 알람 즉시 재설정 오류", e)
        }
    }
}
