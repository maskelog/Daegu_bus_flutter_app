package com.example.daegu_bus_app.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.example.daegu_bus_app.services.BusAlertService
import com.example.daegu_bus_app.services.TTSService
import com.example.daegu_bus_app.workers.BackgroundWorker

class AlarmReceiver : BroadcastReceiver() {
    private val TAG = "AlarmReceiver"

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action
        Log.d(TAG, "🔔 알람 수신: $action")

        if (action == "com.example.daegu_bus_app.AUTO_ALARM") {
            handleOptimizedAutoAlarm(context, intent)
        }
    }
    
    /**
     * 배터리 최적화된 자동알람 처리
     * - 경량화된 알림만 표시
     * - 불필요한 Foreground Service 사용 안함
     * - 정확한 시간에만 실행
     */
    private fun handleOptimizedAutoAlarm(context: Context, intent: Intent) {
        try {
            val alarmId = intent.getIntExtra("alarmId", 0)
            val busNo = intent.getStringExtra("busNo") ?: return
            val stationName = intent.getStringExtra("stationName") ?: return
            val routeId = intent.getStringExtra("routeId") ?: return
            val stationId = intent.getStringExtra("stationId") ?: return
            val useTTS = intent.getBooleanExtra("useTTS", true)

            Log.d(TAG, "🔔 배터리 최적화된 자동 알람 처리: $busNo 번 버스, $stationName")

            // 현재 시간 확인 (정확한 알람 시간인지 검증)
            val currentTime = System.currentTimeMillis()
            val scheduledTime = intent.getLongExtra("scheduledTime", 0L)
            val timeDiff = Math.abs(currentTime - scheduledTime)

            // 5분 이상 차이나면 실행하지 않음 (배터리 절약)
            if (scheduledTime > 0 && timeDiff > 300000L) { // 5분 = 300초
                Log.w(TAG, "⚠️ 알람 시간이 부정확함 (${timeDiff/1000}초 차이), 실행 취소")
                return
            }

            // 배터리 절약을 위한 경량화된 TTS 처리
            if (useTTS) {
                val ttsIntent = Intent(context, TTSService::class.java).apply {
                    action = "REPEAT_TTS_ALERT"
                    putExtra("busNo", busNo)
                    putExtra("stationName", stationName)
                    putExtra("routeId", routeId)
                    putExtra("stationId", stationId)
                    putExtra("isAutoAlarm", true)
                    putExtra("forceSpeaker", true)
                    putExtra("singleExecution", true) // 단일 실행 모드
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(ttsIntent)
                } else {
                    context.startService(ttsIntent)
                }
                Log.d(TAG, "✅ 경량화된 TTS 서비스 시작")
            }

            // 경량화된 알림 서비스 시작
            val busIntent = Intent(context, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_START_AUTO_ALARM_LIGHTWEIGHT
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("remainingMinutes", 0) // 기본값
                putExtra("currentStation", "")
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(busIntent)
            } else {
                context.startService(busIntent)
            }
            Log.d(TAG, "✅ 경량화된 알림 서비스 시작")

            // 다음 알람 스케줄링 (배터리 절약을 위해 조건부)
            scheduleNextAlarmOptimized(context, intent)

        } catch (e: Exception) {
            Log.e(TAG, "❌ 배터리 최적화된 자동 알람 처리 오류", e)
        }
    }
    
    /**
     * 배터리 최적화된 다음 알람 스케줄링
     * - 조건부 스케줄링으로 불필요한 작업 방지
     * - 배터리 상태 확인
     */
    private fun scheduleNextAlarmOptimized(context: Context, intent: Intent) {
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

            Log.d(TAG, "🔄 다음 자동 알람 스케줄링 시작: ${busNo}번 버스, $hour:$minute, 반복 요일: ${repeatDays.joinToString(",")}")

            // 배터리 상태 확인 (간단한 체크)
            val batteryManager = context.getSystemService(Context.BATTERY_SERVICE) as? android.os.BatteryManager
            val batteryLevel = batteryManager?.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY) ?: 100

            // 배터리가 15% 미만이면 다음 알람 스케줄링 건너뛰기 (20%에서 15%로 완화)
            if (batteryLevel < 15) {
                Log.w(TAG, "⚠️ 배터리 부족 ($batteryLevel%), 다음 알람 스케줄링 건너뛰기")
                return
            }

            // 다음 알람 스케줄링을 위한 WorkManager 작업 등록 (배터리 최적화)
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
                .setConstraints(
                    androidx.work.Constraints.Builder()
                        .setRequiredNetworkType(androidx.work.NetworkType.NOT_REQUIRED) // 네트워크 요구사항 완화
                        .setRequiresBatteryNotLow(true) // 배터리 부족 시 실행 안함
                        .setRequiresStorageNotLow(true) // 저장공간 부족 시 실행 안함
                        .build()
                )
                .setBackoffCriteria(
                    androidx.work.BackoffPolicy.EXPONENTIAL,
                    30000L, // 30초 백오프
                    java.util.concurrent.TimeUnit.MILLISECONDS
                )
                .addTag("nextAutoAlarm_${alarmId}") // 태그 추가로 추적 가능
                .build()

            workManager.enqueue(workRequest)
            Log.d(TAG, "✅ 배터리 최적화된 다음 알람 스케줄링 요청 완료 (배터리: $batteryLevel%)")

        } catch (e: Exception) {
            Log.e(TAG, "❌ 배터리 최적화된 다음 알람 스케줄링 오류", e)
        }
    }
} 