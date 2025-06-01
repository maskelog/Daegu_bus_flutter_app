package com.example.daegu_bus_app.workers

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.core.app.NotificationCompat
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.Dispatchers
import org.json.JSONArray
import org.json.JSONObject

import com.example.daegu_bus_app.services.BusApiService
import com.example.daegu_bus_app.services.BusAlertService
import com.example.daegu_bus_app.services.TTSService
import com.example.daegu_bus_app.MainActivity
import com.example.daegu_bus_app.R

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

        try {
            alarmId = inputData.getInt("alarmId", 0)
            busNo = inputData.getString("busNo") ?: ""
            stationName = inputData.getString("stationName") ?: ""
            routeId = inputData.getString("routeId") ?: ""
            stationId = inputData.getString("stationId") ?: ""
            useTTS = inputData.getBoolean("useTTS", true)

            Log.d(TAG, "⏰ [AutoAlarm] 입력 데이터 확인:")
            Log.d(TAG, "  - alarmId: $alarmId")
            Log.d(TAG, "  - busNo: '$busNo'")
            Log.d(TAG, "  - stationName: '$stationName'")
            Log.d(TAG, "  - routeId: '$routeId'")
            Log.d(TAG, "  - stationId: '$stationId'")
            Log.d(TAG, "  - useTTS: $useTTS")

            if (busNo.isEmpty() || stationName.isEmpty() || routeId.isEmpty() || stationId.isEmpty()) {
                Log.e(TAG, "❌ [AutoAlarm] 필수 데이터 누락:")
                Log.e(TAG, "  - busNo 비어있음: ${busNo.isEmpty()}")
                Log.e(TAG, "  - stationName 비어있음: ${stationName.isEmpty()}")
                Log.e(TAG, "  - routeId 비어있음: ${routeId.isEmpty()}")
                Log.e(TAG, "  - stationId 비어있음: ${stationId.isEmpty()}")
                return Result.failure()
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ [AutoAlarm] 입력 데이터 처리 오류: ${e.message}", e)
            return Result.failure()
        }

        // 실시간 버스 정보 fetch 시도 (BusApiService 직접 사용)
        var fetchedMinutes: Int? = null
        var fetchedStation: String? = null
        var fetchSuccess = false
        try {
            Log.d(TAG, "🔍 [AutoAlarm] 실시간 버스 정보 조회 시작")
            Log.d(TAG, "  - stationId: $stationId")
            Log.d(TAG, "  - routeId: $routeId")

            val apiService = BusApiService(applicationContext)
            Log.d(TAG, "🔍 [AutoAlarm] BusApiService 인스턴스 생성 완료")

            val stationInfoJson = runBlocking {
                withContext(Dispatchers.IO) {
                    try {
                        Log.d(TAG, "🔍 [AutoAlarm] getStationInfo 호출 시작")
                        val result = apiService.getStationInfo(stationId)
                        Log.d(TAG, "🔍 [AutoAlarm] getStationInfo 호출 완료, 결과 길이: ${result.length}")
                        result
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ [AutoAlarm] BusApiService.getStationInfo 호출 오류: ${e.message}", e)
                        Log.e(TAG, "❌ [AutoAlarm] 오류 스택 트레이스: ${e.stackTrace.joinToString("\n")}")
                        ""
                    }
                }
            }

            Log.d(TAG, "🔍 [AutoAlarm] 정류장 정보 조회 결과 (첫 200자): ${stationInfoJson.take(200)}")

            if (stationInfoJson.isNotBlank() && stationInfoJson != "[]") {
                Log.d(TAG, "🔍 [AutoAlarm] JSON 파싱 시작")
                // JSON 파싱하여 해당 노선의 버스 정보 추출
                val busInfo = parseBusInfoFromJson(stationInfoJson, routeId)
                if (busInfo != null) {
                    fetchedMinutes = busInfo.first
                    fetchedStation = busInfo.second
                    fetchSuccess = true
                    Log.d(TAG, "✅ [AutoAlarm] 버스 정보 파싱 성공: ${fetchedMinutes}분, 현재위치: $fetchedStation")
                } else {
                    Log.w(TAG, "⚠️ [AutoAlarm] 해당 노선의 버스 정보를 찾을 수 없음: $routeId")
                    Log.w(TAG, "⚠️ [AutoAlarm] 전체 JSON 내용: $stationInfoJson")
                }
            } else {
                Log.w(TAG, "⚠️ [AutoAlarm] 정류장 정보가 비어있거나 빈 배열")
                Log.w(TAG, "⚠️ [AutoAlarm] 응답 내용: '$stationInfoJson'")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ [AutoAlarm] 실시간 버스 정보 fetch 실패: ${e.message}", e)
            Log.e(TAG, "❌ [AutoAlarm] 전체 스택 트레이스: ${e.stackTrace.joinToString("\n")}")
        }

        // 알림 메시지 결정
        val contentText = if (fetchSuccess && fetchedMinutes != null && fetchedStation != null) {
            when {
                fetchedMinutes <= 0 -> "$busNo 번 버스가 곧 도착합니다. (현재: $fetchedStation)"
                fetchedMinutes == 1 -> "$busNo 번 버스가 약 1분 후 도착 예정입니다. (현재: $fetchedStation)"
                else -> "$busNo 번 버스가 약 ${fetchedMinutes}분 후 도착 예정입니다. (현재: $fetchedStation)"
            }
        } else {
            "$busNo 번 버스의 실시간 정보를 불러오지 못했습니다. 네트워크 상태를 확인해주세요."
        }

        // 노티피케이션 표시 (BusAlertService를 통해)
        try {
            val busAlertIntent = Intent(applicationContext, BusAlertService::class.java).apply {
                action = "com.example.daegu_bus_app.action.START_TRACKING_FOREGROUND"
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("remainingMinutes", fetchedMinutes ?: 0)
                putExtra("currentStation", fetchedStation ?: "")
                putExtra("isAutoAlarm", true)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(busAlertIntent)
            } else {
                applicationContext.startService(busAlertIntent)
            }
            Log.d(TAG, "✅ BusAlertService 시작 요청 완료 (자동 알람)")
        } catch (e: Exception) {
            Log.e(TAG, "❌ BusAlertService 시작 중 오류: ${e.message}", e)
            // 백업으로 직접 노티피케이션 표시
            try {
                showNotification(alarmId, busNo, stationName, contentText)
                Log.d(TAG, "✅ 백업 노티피케이션 표시 완료")
            } catch (notifError: Exception) {
                Log.e(TAG, "❌ 백업 노티피케이션 표시 실패: ${notifError.message}", notifError)
            }
        }

        if (useTTS) {
            try {
                Log.d(TAG, "🔊 자동 알람 TTS 발화 시작: $busNo 번, $stationName")

                // TTS 메시지 생성
                val ttsMessage = if (fetchSuccess && fetchedMinutes != null) {
                    when {
                        fetchedMinutes <= 0 -> "$busNo 번 버스가 $stationName 정류장에 곧 도착합니다."
                        fetchedMinutes == 1 -> "$busNo 번 버스가 약 1분 후 도착 예정입니다."
                        else -> "$busNo 번 버스가 약 ${fetchedMinutes}분 후 도착 예정입니다."
                    }
                } else {
                    "$busNo 번 버스가 $stationName 정류장에 곧 도착합니다."
                }

                Log.i(TAG, "🗣️ TTS 메시지: $ttsMessage")

                // 즉시 실행된 알람인지 확인 (중복 TTS 방지)
                val scheduledFor = inputData.getLong("scheduledFor", 0L)
                val currentTime = System.currentTimeMillis()
                val isImmediate = (currentTime - scheduledFor) > -120000L // 2분 이내면 즉시 실행으로 간주

                if (isImmediate) {
                    Log.d(TAG, "⏰ [AutoAlarm] 즉시 실행된 알람 - TTS 건너뛰기 (중복 방지)")
                } else {
                    // 자동 알람용 TTS 서비스 시작 (강제 스피커 모드)
                    val ttsIntent = Intent(applicationContext, TTSService::class.java).apply {
                        action = "REPEAT_TTS_ALERT"
                        putExtra("busNo", busNo)
                        putExtra("stationName", stationName)
                        putExtra("routeId", routeId)
                        putExtra("stationId", stationId)
                        putExtra("remainingMinutes", fetchedMinutes ?: 0)
                        putExtra("currentStation", fetchedStation ?: "")
                        putExtra("isAutoAlarm", true)  // 자동 알람 플래그 추가
                        putExtra("forceSpeaker", true) // 강제 스피커 모드 플래그 추가
                        putExtra("ttsMessage", ttsMessage) // TTS 메시지 직접 전달
                    }

                    // 서비스 시작
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        applicationContext.startForegroundService(ttsIntent)
                    } else {
                        applicationContext.startService(ttsIntent)
                    }
                    Log.d(TAG, "✅ 자동 알람 TTSService 시작 요청 완료 (강제 스피커 모드)")

                    // 백업 TTS는 한 번만 실행 (5초 후)
                    android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                        try {
                            val backupTtsIntent = Intent(applicationContext, TTSService::class.java).apply {
                                action = "REPEAT_TTS_ALERT"
                                putExtra("busNo", busNo)
                                putExtra("stationName", stationName)
                                putExtra("routeId", routeId)
                                putExtra("stationId", stationId)
                                putExtra("remainingMinutes", fetchedMinutes ?: 0)
                                putExtra("currentStation", fetchedStation ?: "")
                                putExtra("isAutoAlarm", true)
                                putExtra("forceSpeaker", true)
                                putExtra("ttsMessage", ttsMessage)
                                putExtra("isBackup", true)
                                putExtra("backupNumber", 1)
                            }
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                applicationContext.startForegroundService(backupTtsIntent)
                            } else {
                                applicationContext.startService(backupTtsIntent)
                            }
                            Log.d(TAG, "✅ 백업 TTSService 시작 요청 완료 (5초 후)")
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ 백업 TTSService 시작 중 오류: ${e.message}", e)
                        }
                    }, 5000L)
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ TTSService 시작 중 오류: ${e.message}", e)
            }
        }

        Log.d(TAG, "✅ [AutoAlarm] Worker 작업 완료")
        Log.d(TAG, "  - alarmId: $alarmId")
        Log.d(TAG, "  - busNo: $busNo")
        Log.d(TAG, "  - fetchSuccess: $fetchSuccess")
        Log.d(TAG, "  - useTTS: $useTTS")

        // 성공적으로 완료 (실패해도 재시도하지 않음)
        return Result.success()
    }

    private fun showNotification(alarmId: Int, busNo: String, stationName: String, contentText: String) {
        val notificationManager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        // 노티피케이션 채널 생성 (Android 8.0 이상)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                ALARM_NOTIFICATION_CHANNEL_ID,
                "버스 알람",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "버스 도착 알람 알림"
                enableLights(true)
                enableVibration(true)
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "✅ 노티피케이션 채널 생성 완료: $ALARM_NOTIFICATION_CHANNEL_ID")
        }
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

    // JSON에서 버스 정보 파싱하는 함수
    private fun parseBusInfoFromJson(jsonString: String, targetRouteId: String): Pair<Int, String>? {
        return try {
            Log.d(TAG, "🔍 [AutoAlarm] JSON 파싱 시작, 대상 routeId: $targetRouteId")
            val jsonArray = JSONArray(jsonString)
            Log.d(TAG, "🔍 [AutoAlarm] JSON 배열 길이: ${jsonArray.length()}")

            for (i in 0 until jsonArray.length()) {
                val routeObj = jsonArray.getJSONObject(i)
                val arrList = routeObj.optJSONArray("arrList")

                if (arrList == null) {
                    Log.d(TAG, "🔍 [AutoAlarm] arrList가 null임, 인덱스: $i")
                    continue
                }

                Log.d(TAG, "🔍 [AutoAlarm] arrList 길이: ${arrList.length()}, 인덱스: $i")

                for (j in 0 until arrList.length()) {
                    val busObj = arrList.getJSONObject(j)
                    val routeId = busObj.optString("routeId", "")
                    val routeNo = busObj.optString("routeNo", "")

                    Log.d(TAG, "🔍 [AutoAlarm] 버스 정보 확인: routeId=$routeId, routeNo=$routeNo, 대상=$targetRouteId")

                    if (routeId == targetRouteId) {
                        val arrState = busObj.optString("arrState", "")
                        val bsNm = busObj.optString("bsNm", "정보 없음")

                        Log.d(TAG, "🔍 [AutoAlarm] 매칭된 버스 발견: arrState=$arrState, bsNm=$bsNm")

                        // 운행종료된 버스는 건너뛰기
                        if (arrState.contains("운행종료")) {
                            Log.d(TAG, "🔍 [AutoAlarm] 운행종료된 버스 건너뛰기: $arrState")
                            continue
                        }

                        // 도착 시간에서 분 단위 추출
                        val minutes = when {
                            arrState.contains("분") -> {
                                val regex = Regex("(\\d+)분")
                                regex.find(arrState)?.groupValues?.get(1)?.toIntOrNull() ?: 0
                            }
                            arrState.contains("곧 도착") -> 0
                            arrState == "전" -> 1 // "전"은 1분 후 도착
                            arrState == "전전" -> 0 // "전전"은 곧 도착
                            arrState.contains("출발예정") || arrState.contains("기점출발예정") -> 15 // 기본값
                            arrState.contains("운행종료") -> -1 // 운행종료는 -1로 표시
                            else -> {
                                // 숫자만 추출 시도
                                val regex = Regex("\\d+")
                                regex.find(arrState)?.value?.toIntOrNull() ?: 0
                            }
                        }

                        Log.d(TAG, "✅ [AutoAlarm] 파싱 성공: routeId=$routeId, arrState=$arrState, bsNm=$bsNm, minutes=$minutes")
                        return Pair(minutes, bsNm)
                    }
                }
            }
            Log.w(TAG, "⚠️ [AutoAlarm] 대상 노선 ID를 찾을 수 없음: $targetRouteId")
            Log.w(TAG, "⚠️ [AutoAlarm] 전체 JSON 내용 (디버깅용): $jsonString")
            null
        } catch (e: Exception) {
            Log.e(TAG, "❌ [AutoAlarm] JSON 파싱 오류: ${e.message}", e)
            Log.e(TAG, "❌ [AutoAlarm] JSON 내용: $jsonString")
            null
        }
    }
}