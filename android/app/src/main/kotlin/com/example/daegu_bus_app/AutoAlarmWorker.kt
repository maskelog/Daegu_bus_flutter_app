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
        routeId = inputData.getString("routeId") ?: "" // Get routeId
        stationId = inputData.getString("stationId") ?: "" // Get stationId
        useTTS = inputData.getBoolean("useTTS", true)

        Log.d(TAG, "⏰ Executing AutoAlarmWorker: ID=$alarmId, Bus=$busNo, Station=$stationName, TTS=$useTTS, RouteID=$routeId, StationID=$stationId")

        if (busNo.isEmpty() || stationName.isEmpty() || routeId.isEmpty() || stationId.isEmpty()) {
            Log.e(TAG, "❌ Missing busNo, stationName, routeId or stationId in inputData")
            return Result.failure()
        }

        // Show Notification (can be done immediately)
        showNotification(alarmId, busNo, stationName)

        // If TTS is enabled, send an Intent to TTSService
        if (useTTS) {
            Log.d(TAG, "🔊 TTS 사용 설정됨. TTSService 시작 요청...")
            try {
                val ttsIntent = Intent(applicationContext, TTSService::class.java).apply {
                    // Use REPEAT_TTS_ALERT or a specific action for single alarm speech
                    action = "REPEAT_TTS_ALERT" // Or define a new action like "SPEAK_ALARM"
                    putExtra("busNo", busNo)
                    putExtra("stationName", stationName)
                    putExtra("routeId", routeId)
                    putExtra("stationId", stationId)
                    // Add any other necessary data for TTSService
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    applicationContext.startForegroundService(ttsIntent)
                } else {
                    applicationContext.startService(ttsIntent)
                }
                Log.d(TAG, "✅ TTSService 시작 요청 완료.")
            } catch (e: Exception) {
                Log.e(TAG, "❌ TTSService 시작 중 오류: ${e.message}", e)
                // Decide if this should be a failure
                // return Result.failure()
            }
        } else {
             Log.d(TAG, "🔊 TTS 사용 안 함 설정됨.")
        }

        // Worker result indicates successful scheduling/dispatching, not necessarily TTS completion
        Log.d(TAG, "✅ Worker 작업 완료 (Notification 표시 및 TTS 시작 요청): ID=$alarmId")
        return Result.success() // Return success as the task dispatch is done
    }

    private fun showNotification(alarmId: Int, busNo: String, stationName: String) {
        val notificationManager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val intent = applicationContext.packageManager.getLaunchIntentForPackage(applicationContext.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = intent?.let {
            PendingIntent.getActivity(applicationContext, alarmId, it, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        // Full-screen intent
        val fullScreenIntent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            putExtra("alarmId", alarmId)
        }
        val fullScreenPendingIntent = PendingIntent.getActivity(
            applicationContext, alarmId, fullScreenIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(applicationContext, ALARM_NOTIFICATION_CHANNEL_ID)
            .setContentTitle("$busNo 버스 알람")
            .setContentText("$stationName 정류장에 곧 도착합니다")
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