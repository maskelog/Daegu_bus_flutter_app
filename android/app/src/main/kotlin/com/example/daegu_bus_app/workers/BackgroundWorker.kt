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
import org.json.JSONObject
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
            val alarmId = inputData.getInt("alarmId", 0) // alarmId 추가
            val busNo = inputData.getString("busNo") ?: return Result.failure()
            val stationName = inputData.getString("stationName") ?: return Result.failure()
            val routeId = inputData.getString("routeId") ?: return Result.failure()
            val stationId = inputData.getString("stationId") ?: return Result.failure()
            val useTTS = inputData.getBoolean("useTTS", true)
            val isAutoAlarm = true // 자동 알람임을 명시

            Log.d(TAG, "자동 알람 작업 처리: $busNo 번 버스, $stationName, alarmId: $alarmId")

            // TTS 서비스 시작
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

            // 버스 알림 서비스 시작
            val busIntent = Intent(applicationContext, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_START_TRACKING_FOREGROUND // 포그라운드 서비스 시작 액션 사용
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("isAutoAlarm", isAutoAlarm) // isAutoAlarm 플래그 전달
                putExtra("alarmId", alarmId) // alarmId 전달
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
            
            // TTS 서비스에 반복 알림 요청
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
            
            // AlarmManager 인스턴스 가져오기
            val alarmManager = applicationContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            
            // 알람 인텐트 생성
            val alarmIntent = Intent(applicationContext, AlarmReceiver::class.java).apply {
                action = "com.example.daegu_bus_app.AUTO_ALARM"
                putExtra("alarmId", alarmId)
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("useTTS", useTTS)
            }
            
            // PendingIntent 생성
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
            
            // 반복 요일에 따라 알람 설정
            for (day in repeatDays) {
                // 현재 날짜 기준으로 다음 해당 요일 계산
                val calendar = Calendar.getInstance()
                val currentDay = calendar.get(Calendar.DAY_OF_WEEK)
                var daysToAdd = day - currentDay
                if (daysToAdd <= 0) {
                    daysToAdd += 7 // 다음 주로 설정
                }
                
                // 시간 설정
                calendar.add(Calendar.DAY_OF_YEAR, daysToAdd)
                calendar.set(Calendar.HOUR_OF_DAY, hour)
                calendar.set(Calendar.MINUTE, minute)
                calendar.set(Calendar.SECOND, 0)
                
                // 이미 지난 시간이면 다음 주로 설정
                if (calendar.timeInMillis <= System.currentTimeMillis()) {
                    calendar.add(Calendar.DAY_OF_YEAR, 7)
                }
                
                // AlarmManager로 알람 설정
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
                
                Log.d(TAG, "알람 설정 완료: ${calendar.time}, 요일: $day")
            }
            
            return Result.success()
        } catch (e: Exception) {
            Log.e(TAG, "AlarmManager 스케줄링 오류", e)
            return Result.failure()
        }
    }
}
