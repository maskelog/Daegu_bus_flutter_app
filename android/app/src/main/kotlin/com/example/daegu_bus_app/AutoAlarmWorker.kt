package com.example.daegu_bus_app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import android.app.NotificationManager
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers

// ... BackgroundWorker ...

// --- Worker for Auto Alarms ---
class AutoAlarmWorker(
    private val context: Context,
    workerParams: WorkerParameters
) : Worker(context, workerParams) {
    private val TAG = "AutoAlarmWorker"
    private val ALARM_NOTIFICATION_CHANNEL_ID = "bus_alarm_channel"

    // Store data passed from input
    private var alarmId: Int = 0
    private var busNo: String = ""
    private var stationName: String = ""
    private var routeId: String = "" // Added to pass to TTSService
    private var stationId: String = "" // Added to pass to TTSService
    private var useTTS: Boolean = true

    override fun doWork(): Result {
        Log.d(TAG, "⏰ AutoAlarmWorker 실행 시작")
        alarmId = inputData.getInt("alarmId", 0)
        busNo = inputData.getString("busNo") ?: ""
        stationName = inputData.getString("stationName") ?: ""
        routeId = inputData.getString("routeId") ?: ""
        stationId = inputData.getString("stationId") ?: ""
        useTTS = inputData.getBoolean("useTTS", true)

        Log.d(TAG, "⏰ Executing AutoAlarmWorker: ID=$alarmId, Bus=$busNo, Station=$stationName, TTS=$useTTS, RouteID=$routeId, StationID=$stationId")

        if (busNo.isEmpty() || stationName.isEmpty() || routeId.isEmpty() || stationId.isEmpty()) {
            Log.e(TAG, "❌ Missing busNo, stationName, routeId or stationId in inputData")
            return Result.failure()
        }

        // 실시간 버스 정보 fetch 시도
        var fetchedMinutes: Int? = null
        var fetchedStation: String? = null
        var fetchSuccess = false
        try {
            val apiService = BusApiService(applicationContext)
            val arrivals = runBlocking {
                apiService.getBusArrivalInfo(stationId)
            }
            val matched = arrivals.find { it.id == routeId }
            val bus = matched?.bus?.firstOrNull()
            if (bus != null) {
                val estimated = bus.estimatedTime
                fetchedStation = bus.currentStation
                fetchedMinutes = Regex("\\d+").find(estimated ?: "")?.value?.toIntOrNull()
                fetchSuccess = true
            }
        } catch (e: Exception) {
            Log.e(TAG, "실시간 버스 정보 fetch 실패: ${e.message}")
        }

        // 알림 메시지 결정
        val contentText = if (fetchSuccess && fetchedMinutes != null && fetchedStation != null) {
            "$busNo 번 버스가 $stationName 정류장에 약 ${fetchedMinutes}분 후 도착 예정입니다. (현재: $fetchedStation)"
        } else {
            "$busNo 번 버스의 실시간 정보를 불러오지 못했습니다. 네트워크 상태를 확인해주세요."
        }

        showNotification(alarmId, busNo, stationName, contentText)

        if (useTTS) {
            try {
                val ttsIntent = Intent(applicationContext, TTSService::class.java).apply {
                    action = "REPEAT_TTS_ALERT"
                    putExtra("busNo", busNo)
                    putExtra("stationName", stationName)
                    putExtra("routeId", routeId)
                    putExtra("stationId", stationId)
                    putExtra("remainingMinutes", fetchedMinutes ?: -1)
                    putExtra("currentStation", fetchedStation ?: "")
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    applicationContext.startForegroundService(ttsIntent)
                } else {
                    applicationContext.startService(ttsIntent)
                }
                Log.d(TAG, "✅ TTSService 시작 요청 완료.")
            } catch (e: Exception) {
                Log.e(TAG, "❌ TTSService 시작 중 오류: ${e.message}", e)
            }
        }

        Log.d(TAG, "✅ Worker 작업 완료 (Notification/TTS): ID=$alarmId")
        return Result.success()
    }

    private fun showNotification(alarmId: Int, busNo: String, stationName: String, contentText: String) {
        val notificationManager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val intent = applicationContext.packageManager.getLaunchIntentForPackage(applicationContext.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = intent?.let {
            PendingIntent.getActivity(applicationContext, alarmId, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
        val fullScreenIntent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("alarmId", alarmId)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            applicationContext, alarmId, fullScreenIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = NotificationCompat.Builder(applicationContext, ALARM_NOTIFICATION_CHANNEL_ID)
            .setContentTitle("$busNo 버스 알람")
            .setContentText(contentText)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setFullScreenIntent(fullScreenPendingIntent, true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .build()
        try {
            notificationManager.notify(alarmId, notification)
            Log.d(TAG, "✅ Notification shown with lockscreen support for alarm ID: $alarmId")
        } catch (e: SecurityException) {
            Log.e(TAG, "❌ Notification permission possibly denied: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error showing notification: ${e.message}")
        }
    }

    override fun onStopped() {
        Log.d(TAG, "AutoAlarmWorker stopped.")
        super.onStopped()
    }
} 