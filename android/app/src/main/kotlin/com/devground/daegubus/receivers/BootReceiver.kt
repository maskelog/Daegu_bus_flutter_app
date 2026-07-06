package com.devground.daegubus.receivers

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.devground.daegubus.utils.AutoAlarmScheduleCalculator
import org.json.JSONObject

class BootReceiver : BroadcastReceiver() {
    private val TAG = "BootReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED &&
            intent.action != "android.intent.action.QUICKBOOT_POWERON"
        ) return

        Log.d(TAG, "🔄 기기 재시작 감지 - 자동알람 재등록 시작")
        val pendingResult = goAsync()
        Thread {
            try {
                rescheduleAllAlarms(context.applicationContext)
            } catch (e: Exception) {
                Log.e(TAG, "❌ 자동알람 재등록 오류", e)
            } finally {
                try { pendingResult.finish() } catch (_: Exception) {}
            }
        }.start()
    }

    private fun rescheduleAllAlarms(context: Context) {
        // scheduleNativeAlarm(MainActivity)이 기록해 두는 네이티브 저장소.
        // FlutterSharedPreferences의 StringList는 플러그인이 인코딩된 String으로
        // 저장하므로 getStringSet으로는 읽을 수 없다 — 반드시 이 저장소를 쓸 것.
        val store = context.getSharedPreferences("auto_alarm_store", Context.MODE_PRIVATE)
        val entries = store.all.values.filterIsInstance<String>()
        if (entries.isEmpty()) {
            Log.d(TAG, "저장된 자동알람 없음")
            return
        }

        Log.d(TAG, "자동알람 재등록 대상: ${entries.size}개")
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val excludedDates = AutoAlarmScheduleCalculator.loadExcludedDates(context)

        for (alarmJson in entries) {
            try {
                val obj = JSONObject(alarmJson)
                // 예약 당시 Flutter가 부여한 ID를 그대로 재사용한다 (재계산 금지 —
                // 계산 방식이 갈리면 취소되지 않는 유령 알람이 생긴다).
                val alarmId = obj.optInt("alarmId", 0)
                val busNo = obj.optString("busNo").takeIf { it.isNotBlank() } ?: continue
                val stationName = obj.optString("stationName").takeIf { it.isNotBlank() } ?: continue
                val routeId = obj.optString("routeId").takeIf { it.isNotBlank() } ?: continue
                val stationId = obj.optString("stationId").takeIf { it.isNotBlank() } ?: continue
                val hour = obj.optInt("hour", -1).takeIf { it >= 0 } ?: continue
                val minute = obj.optInt("minute", 0)
                val useTTS = obj.optBoolean("useTTS", true)
                val isCommuteAlarm = obj.optBoolean("isCommuteAlarm", true)
                val excludeHolidays = obj.optBoolean("excludeHolidays", false)
                val alertOnArrivalOnly = try {
                    context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                        .getBoolean("flutter.alert_on_arrival_only", obj.optBoolean("alertOnArrivalOnly", false))
                } catch (e: Exception) {
                    obj.optBoolean("alertOnArrivalOnly", false)
                }

                val repeatDaysArray = obj.optJSONArray("repeatDays") ?: continue
                val repeatDays = IntArray(repeatDaysArray.length()) { repeatDaysArray.getInt(it) }
                if (repeatDays.isEmpty()) continue

                val nowMillis = System.currentTimeMillis()
                val targetAlarmTime = AutoAlarmScheduleCalculator.findNextTargetTime(
                    nowMillis, hour, minute, repeatDays,
                    if (excludeHolidays) excludedDates else emptySet(),
                ) ?: continue
                val trackingStartTime =
                    AutoAlarmScheduleCalculator.trackingStartTime(targetAlarmTime, nowMillis)

                val alarmIntent = Intent(context, AlarmReceiver::class.java).apply {
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
                    putExtra("targetAlarmTime", targetAlarmTime)
                }

                val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    PendingIntent.getBroadcast(
                        context, alarmId, alarmIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                } else {
                    PendingIntent.getBroadcast(
                        context, alarmId, alarmIntent,
                        PendingIntent.FLAG_UPDATE_CURRENT
                    )
                }

                AutoAlarmScheduleCalculator.scheduleExactAlarm(
                    alarmManager, trackingStartTime, pendingIntent, TAG
                )

                Log.d(TAG, "✅ 자동알람 재등록: $busNo, $stationName → tracking=${java.util.Date(trackingStartTime)}, target=${java.util.Date(targetAlarmTime)}")
            } catch (e: Exception) {
                Log.e(TAG, "❌ 알람 재등록 오류 (개별): ${e.message}")
            }
        }
    }
}
