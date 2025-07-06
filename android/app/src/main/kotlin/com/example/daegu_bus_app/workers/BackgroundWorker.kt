package com.example.daegu_bus_app.workers

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.example.daegu_bus_app.services.BusAlertService
import com.example.daegu_bus_app.services.TTSService
import com.example.daegu_bus_app.receivers.AlarmReceiver
import java.util.Calendar

class BackgroundWorker(context: Context, params: WorkerParameters) : Worker(context, params) {
    private val TAG = "BackgroundWorker"
    
    override fun doWork(): Result {
        val taskName = inputData.getString("taskName") ?: return Result.failure()
        Log.d(TAG, "백그라운드 작업 시작: $taskName")
        
        return when (taskName) {
            "autoAlarmTask" -> handleAutoAlarmTask()
            "ttsRepeatingTask" -> handleTTSRepeatingTask()
            "scheduleAlarmManager" -> scheduleAlarmManager()
            else -> Result.failure()
        }
    }
    
    private fun handleAutoAlarmTask(): Result {
        try {
            val alarmId = inputData.getInt("alarmId", 0)
            val busNo = inputData.getString("busNo") ?: return Result.failure()
            val stationName = inputData.getString("stationName") ?: return Result.failure()
            val routeId = inputData.getString("routeId") ?: return Result.failure()
            val stationId = inputData.getString("stationId") ?: return Result.failure()
            val useTTS = inputData.getBoolean("useTTS", true)
            val isAutoAlarm = true

            Log.d(TAG, "자동 알람 작업 처리: $busNo 번 버스, $stationName, alarmId: $alarmId")

            if (useTTS) {
                val ttsIntent = Intent(applicationContext, TTSService::class.java).apply {
                    action = "START_TTS_TRACKING"
                    putExtra("busNo", busNo)
                    putExtra("stationName", stationName)
                    putExtra("routeId", routeId)
                    putExtra("stationId", stationId)
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    applicationContext.startForegroundService(ttsIntent)
                } else {
                    applicationContext.startService(ttsIntent)
                }
            }

            val busIntent = Intent(applicationContext, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_START_TRACKING_FOREGROUND
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("isAutoAlarm", isAutoAlarm)
                putExtra("alarmId", alarmId)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(busIntent)
            } else {
                applicationContext.startService(busIntent)
            }

            return Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "자동 알람 작업 처리 오류", e)
            return Result.failure()
        }
    }
    
    private fun handleTTSRepeatingTask(): Result {
        try {
            val busNo = inputData.getString("busNo") ?: return Result.failure()
            val stationName = inputData.getString("stationName") ?: return Result.failure()
            val routeId = inputData.getString("routeId") ?: return Result.failure()
            val stationId = inputData.getString("stationId") ?: return Result.failure()
            val useTTS = inputData.getBoolean("useTTS", true)
            
            Log.d(TAG, "반복 TTS 작업 처리: $busNo 번 버스, $stationName")
            
            if (useTTS) {
                val ttsIntent = Intent(applicationContext, TTSService::class.java).apply {
                    action = "REPEAT_TTS_ALERT"
                    putExtra("busNo", busNo)
                    putExtra("stationName", stationName)
                    putExtra("routeId", routeId)
                    putExtra("stationId", stationId)
                }
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    applicationContext.startForegroundService(ttsIntent)
                } else {
                    applicationContext.startService(ttsIntent)
                }
            }
            
            return Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "반복 TTS 작업 처리 오류", e)
            return Result.failure()
        }
    }
    
    private fun scheduleAlarmManager(): Result {
        try {
            val alarmId = inputData.getInt("alarmId", 0)
            val busNo = inputData.getString("busNo") ?: return Result.failure()
            val stationName = inputData.getString("stationName") ?: return Result.failure()
            val routeId = inputData.getString("routeId") ?: return Result.failure()
            val stationId = inputData.getString("stationId") ?: return Result.failure()
            val useTTS = inputData.getBoolean("useTTS", true)
            val hour = inputData.getInt("hour", 0)
            val minute = inputData.getInt("minute", 0)
            val repeatDays = inputData.getIntArray("repeatDays") ?: return Result.failure()
            
            Log.d(TAG, "AlarmManager 스케줄링: $busNo 번 버스, $stationName, $hour:$minute")
            
            val alarmManager = applicationContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            val alarmIntent = Intent(applicationContext, AlarmReceiver::class.java).apply {
                action = "com.example.daegu_bus_app.AUTO_ALARM"
                putExtra("alarmId", alarmId)
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("useTTS", useTTS)
                putExtra("hour", hour)
                putExtra("minute", minute)
                putExtra("repeatDays", repeatDays)
            }
            
            val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.getBroadcast(
                    applicationContext,
                    alarmId,
                    alarmIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            } else {
                PendingIntent.getBroadcast(
                    applicationContext,
                    alarmId,
                    alarmIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT
                )
            }
            
            val calendar = Calendar.getInstance()
            val now = Calendar.getInstance()
            
            calendar.set(Calendar.HOUR_OF_DAY, hour)
            calendar.set(Calendar.MINUTE, minute)
            calendar.set(Calendar.SECOND, 0)
            calendar.set(Calendar.MILLISECOND, 0)
            
            val currentDay = calendar.get(Calendar.DAY_OF_WEEK)
            val currentDayMapped = if (currentDay == Calendar.SUNDAY) 7 else currentDay - 1
            
            if (repeatDays.contains(currentDayMapped) && calendar.timeInMillis > now.timeInMillis) {
                Log.d(TAG, "오늘 알람 설정: ${calendar.time}, 요일: $currentDayMapped")
            } else {
                var nextAlarmSet = false
                for (i in 1..7) {
                    val testCalendar = Calendar.getInstance()
                    testCalendar.add(Calendar.DAY_OF_YEAR, i)
                    val testDay = testCalendar.get(Calendar.DAY_OF_WEEK)
                    val testDayMapped = if (testDay == Calendar.SUNDAY) 7 else testDay - 1
                    
                    if (repeatDays.contains(testDayMapped)) {
                        calendar.add(Calendar.DAY_OF_YEAR, i)
                        nextAlarmSet = true
                        Log.d(TAG, "다음 알람 설정: ${calendar.time}, 요일: $testDayMapped (${i}일 후)")
                        break
                    }
                }
                
                if (!nextAlarmSet) {
                    Log.e(TAG, "다음 알람 시간을 찾을 수 없습니다")
                    return Result.failure()
                }
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                alarmManager.setAlarmClock(
                    AlarmManager.AlarmClockInfo(calendar.timeInMillis, pendingIntent),
                    pendingIntent
                )
            } else {
                alarmManager.setExact(
                    AlarmManager.RTC_WAKEUP,
                    calendar.timeInMillis,
                    pendingIntent
                )
            }
            
            Log.d(TAG, "✅ AlarmManager 스케줄링 완료: ${busNo}번 버스, ${calendar.time}")
            
            return Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "AlarmManager 스케줄링 오류", e)
            return Result.failure()
        }
    }
} 