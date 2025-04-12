package com.example.daegu_bus_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.example.daegu_bus_app.BusAlertService
import com.example.daegu_bus_app.TTSService

class AlarmReceiver : BroadcastReceiver() {
    private val TAG = "AlarmReceiver"
    
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d(TAG, "알람 수신: $action")
        
        if (action == "com.example.daegu_bus_app.AUTO_ALARM") {
            handleAutoAlarm(context, intent)
        }
    }
    
    private fun handleAutoAlarm(context: Context, intent: Intent) {
        try {
            val alarmId = intent.getIntExtra("alarmId", 0)
            val busNo = intent.getStringExtra("busNo") ?: return
            val stationName = intent.getStringExtra("stationName") ?: return
            val routeId = intent.getStringExtra("routeId") ?: return
            val stationId = intent.getStringExtra("stationId") ?: return
            val useTTS = intent.getBooleanExtra("useTTS", true)
            
            Log.d(TAG, "자동 알람 처리: $busNo 번 버스, $stationName")
            
            // TTS 서비스 시작
            if (useTTS) {
                val ttsIntent = Intent(context, TTSService::class.java).apply {
                    action = "START_TTS_TRACKING"
                    putExtra("busNo", busNo)
                    putExtra("stationName", stationName)
                    putExtra("routeId", routeId)
                    putExtra("stationId", stationId)
                }
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(ttsIntent)
                } else {
                    context.startService(ttsIntent)
                }
            }
            
            // 버스 알림 서비스 시작
            val busIntent = Intent(context, BusAlertService::class.java).apply {
                action = "START_BUS_MONITORING"
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
            }
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(busIntent)
            } else {
                context.startService(busIntent)
            }
            
            // 다음 알람 스케줄링 (다음 주 같은 시간)
            scheduleNextAlarm(context, intent)
            
        } catch (e: Exception) {
            Log.e(TAG, "자동 알람 처리 오류", e)
        }
    }
    
    private fun scheduleNextAlarm(context: Context, intent: Intent) {
        try {
            val alarmId = intent.getIntExtra("alarmId", 0)
            val busNo = intent.getStringExtra("busNo") ?: return
            val stationName = intent.getStringExtra("stationName") ?: return
            val routeId = intent.getStringExtra("routeId") ?: return
            val stationId = intent.getStringExtra("stationId") ?: return
            val useTTS = intent.getBooleanExtra("useTTS", true)
            val hour = intent.getIntExtra("hour", 0)
            val minute = intent.getIntExtra("minute", 0)
            val repeatDays = intent.getIntArrayExtra("repeatDays") ?: return
            
            // 다음 알람 스케줄링을 위한 WorkManager 작업 등록
            val workManager = androidx.work.WorkManager.getInstance(context)
            val inputData = androidx.work.Data.Builder()
                .putString("taskName", "scheduleAlarmManager")
                .putInt("alarmId", alarmId)
                .putString("busNo", busNo)
                .putString("stationName", stationName)
                .putString("routeId", routeId)
                .putString("stationId", stationId)
                .putBoolean("useTTS", useTTS)
                .putInt("hour", hour)
                .putInt("minute", minute)
                .putIntArray("repeatDays", repeatDays)
                .build()
            
            val workRequest = androidx.work.OneTimeWorkRequestBuilder<BackgroundWorker>()
                .setInputData(inputData)
                .build()
            
            workManager.enqueue(workRequest)
            Log.d(TAG, "다음 알람 스케줄링 요청 완료")
            
        } catch (e: Exception) {
            Log.e(TAG, "다음 알람 스케줄링 오류", e)
        }
    }
} 