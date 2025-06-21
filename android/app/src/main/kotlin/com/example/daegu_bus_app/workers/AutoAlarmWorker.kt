package com.example.daegu_bus_app.workers

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.example.daegu_bus_app.services.BusAlertService

class AutoAlarmWorker(
    private val context: Context,
    workerParams: WorkerParameters
) : Worker(context, workerParams) {

    private val TAG = "AutoAlarmWorker"

    override fun doWork(): Result {
        Log.d(TAG, "⏰ AutoAlarmWorker 실행 시작")

        return try {
            val alarmId = inputData.getInt("alarmId", 0)
            val busNo = inputData.getString("busNo") ?: ""
            val stationName = inputData.getString("stationName") ?: ""
            val routeId = inputData.getString("routeId") ?: ""
            val stationId = inputData.getString("stationId") ?: ""

            Log.d(TAG, "⏰ [AutoAlarm] 입력 데이터:")
            Log.d(TAG, "  - alarmId: $alarmId")
            Log.d(TAG, "  - busNo: '$busNo'")
            Log.d(TAG, "  - stationName: '$stationName'")
            Log.d(TAG, "  - routeId: '$routeId'")
            Log.d(TAG, "  - stationId: '$stationId'")

            if (busNo.isBlank() || stationName.isBlank() || routeId.isBlank() || stationId.isBlank()) {
                Log.e(TAG, "❌ [AutoAlarm] 필수 데이터 누락. 작업을 중단합니다.")
                return Result.failure()
            }

            // BusAlertService를 시작하여 실제 추적 및 알림을 위임합니다.
            Log.d(TAG, "▶️ BusAlertService에 추적을 위임합니다...")
            val serviceIntent = Intent(applicationContext, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_START_TRACKING_FOREGROUND
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("isAutoAlarm", true) // 자동 알람에서 시작되었음을 알립니다.
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(serviceIntent)
            } else {
                applicationContext.startService(serviceIntent)
            }

            Log.d(TAG, "✅ [AutoAlarm] BusAlertService 시작 요청 완료. Worker 작업 성공.")
            Result.success()

        } catch (e: Exception) {
            Log.e(TAG, "❌ [AutoAlarm] Worker 실행 중 심각한 오류 발생: ${e.message}", e)
            Result.failure()
        }
    }
} 