package com.devground.daegubus.receivers

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.Calendar

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

    private fun resolveStationId(context: Context, bsId: String): String {
        if (bsId.startsWith("7") && bsId.length == 10) return bsId
        try {
            val dbFile = context.getDatabasePath("bus_stops.db")
            if (!dbFile.exists()) {
                Log.w(TAG, "bus_stops.db 파일 없음, 원본 stationId 사용: $bsId")
                return bsId
            }
            android.database.sqlite.SQLiteDatabase.openDatabase(
                dbFile.absolutePath, null,
                android.database.sqlite.SQLiteDatabase.OPEN_READONLY
            ).use { db ->
                db.rawQuery("SELECT stationId FROM bus_stops WHERE bsId = ? LIMIT 1", arrayOf(bsId)).use { c ->
                    if (c.moveToFirst()) {
                        val stationId = c.getString(0)
                        if (!stationId.isNullOrBlank()) {
                            Log.d(TAG, "✅ stationId 변환: $bsId → $stationId")
                            return stationId
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "stationId 변환 오류 ($bsId): ${e.message}")
        }
        Log.w(TAG, "stationId 변환 실패, 원본 사용: $bsId")
        return bsId
    }

    private fun rescheduleAllAlarms(context: Context) {
        val flutterPrefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val alarmSet: Set<String> = flutterPrefs.getStringSet("flutter.auto_alarms", null) ?: run {
            Log.d(TAG, "저장된 자동알람 없음")
            return
        }
        val alarmListJson: List<String> = alarmSet.toList()

        Log.d(TAG, "자동알람 재등록 대상: ${alarmListJson.size}개")
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

        for (alarmJson in alarmListJson) {
            try {
                val obj = JSONObject(alarmJson)
                if (!obj.optBoolean("isActive", true)) continue

                val alarmId = Math.abs(obj.optString("id", "0").hashCode())
                val busNo = obj.optString("routeNo").takeIf { it.isNotBlank() } ?: continue
                val stationName = obj.optString("stationName").takeIf { it.isNotBlank() } ?: continue
                val routeId = obj.optString("routeId").takeIf { it.isNotBlank() } ?: continue
                val rawStationId = obj.optString("stationId").takeIf { it.isNotBlank() } ?: continue
                val stationId = resolveStationId(context, rawStationId)
                val hour = obj.optInt("hour", -1).takeIf { it >= 0 } ?: continue
                val minute = obj.optInt("minute", 0)
                val useTTS = obj.optBoolean("useTTS", true)
                val isCommuteAlarm = obj.optBoolean("isCommuteAlarm", true)
                val alertOnArrivalOnly = flutterPrefs.getBoolean("flutter.alert_on_arrival_only", false)

                val repeatDaysArray = obj.optJSONArray("repeatDays") ?: continue
                val repeatDays = IntArray(repeatDaysArray.length()) { repeatDaysArray.getInt(it) }
                if (repeatDays.isEmpty()) continue

                val calendar = Calendar.getInstance()
                calendar.set(Calendar.HOUR_OF_DAY, hour)
                calendar.set(Calendar.MINUTE, minute)
                calendar.set(Calendar.SECOND, 0)
                calendar.set(Calendar.MILLISECOND, 0)

                // 다음 유효 발동 날짜 탐색
                val now = Calendar.getInstance()
                var scheduled = false
                for (i in 0..7) {
                    val testCal = Calendar.getInstance()
                    if (i > 0) testCal.add(Calendar.DAY_OF_YEAR, i)
                    testCal.set(Calendar.HOUR_OF_DAY, hour)
                    testCal.set(Calendar.MINUTE, minute)
                    testCal.set(Calendar.SECOND, 0)
                    testCal.set(Calendar.MILLISECOND, 0)
                    val dayOfWeek = testCal.get(Calendar.DAY_OF_WEEK)
                    val mappedDay = if (dayOfWeek == Calendar.SUNDAY) 7 else dayOfWeek - 1
                    if (repeatDays.contains(mappedDay) && testCal.timeInMillis > now.timeInMillis) {
                        calendar.timeInMillis = testCal.timeInMillis
                        scheduled = true
                        break
                    }
                }
                if (!scheduled) continue

                // 5분 사전 추적
                calendar.add(Calendar.MINUTE, -5)
                if (calendar.timeInMillis < now.timeInMillis) {
                    calendar.timeInMillis = now.timeInMillis + 5000
                }

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
                    putExtra("hour", hour)
                    putExtra("minute", minute)
                    putExtra("repeatDays", repeatDays)
                    putExtra("scheduledTime", calendar.timeInMillis)
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

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    alarmManager.setAlarmClock(
                        AlarmManager.AlarmClockInfo(calendar.timeInMillis, pendingIntent),
                        pendingIntent
                    )
                } else {
                    alarmManager.setExact(AlarmManager.RTC_WAKEUP, calendar.timeInMillis, pendingIntent)
                }

                Log.d(TAG, "✅ 자동알람 재등록: $busNo, $stationName → ${java.util.Date(calendar.timeInMillis)}")
            } catch (e: Exception) {
                Log.e(TAG, "❌ 알람 재등록 오류 (개별): ${e.message}")
            }
        }
    }
}
