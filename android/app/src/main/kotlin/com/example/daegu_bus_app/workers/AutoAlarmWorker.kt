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
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONArray
import org.json.JSONObject

import com.example.daegu_bus_app.services.BusApiService
import com.example.daegu_bus_app.services.BusAlertService
import com.example.daegu_bus_app.services.TTSService
import com.example.daegu_bus_app.MainActivity
import com.example.daegu_bus_app.R

// --- Worker for Auto Alarms (Battery Optimized) ---
class AutoAlarmWorker(
    private val context: Context,
    workerParams: WorkerParameters
) : Worker(context, workerParams) {
    private val TAG = "AutoAlarmWorker"
    private val ALARM_NOTIFICATION_CHANNEL_ID = "bus_alarm_channel"

    // 배터리 최적화를 위한 상수들
    private val API_TIMEOUT_MS = 10000L // 10초 타임아웃
    private val MAX_RETRY_COUNT = 2 // 최대 재시도 횟수
    private val CACHE_VALIDITY_MS = 30000L // 30초 캐시 유효성

    // Store data passed from input
    private var alarmId: Int = 0
    private var busNo: String = ""
    private var stationName: String = ""
    private var routeId: String = ""
    private var stationId: String = ""
    private var useTTS: Boolean = true

    // 배터리 절약을 위한 캐시
    private var lastApiCall: Long = 0
    private var cachedBusInfo: Pair<Int, String>? = null

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

        // 배터리 최적화된 실시간 버스 정보 조회
        val busInfo = fetchBusInfoOptimized()
        val fetchedMinutes = busInfo?.first
        val fetchedStation = busInfo?.second
        val fetchSuccess = busInfo != null



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

        // 배터리 절약을 위해 경량화된 알림만 표시 (Foreground Service 사용 안함)
        showLightweightNotification(alarmId, busNo, stationName, contentText, fetchedMinutes, fetchedStation)

        // 배터리 절약을 위한 최적화된 TTS 처리
        if (useTTS) {
            handleOptimizedTTS(fetchedMinutes, fetchSuccess)
        }

        Log.d(TAG, "✅ [AutoAlarm] Worker 작업 완료")
        Log.d(TAG, "  - alarmId: $alarmId")
        Log.d(TAG, "  - busNo: $busNo")
        Log.d(TAG, "  - fetchSuccess: $fetchSuccess")
        Log.d(TAG, "  - useTTS: $useTTS")

        // 성공적으로 완료 (실패해도 재시도하지 않음)
        return Result.success()
    }

    /**
     * 배터리 최적화된 버스 정보 조회
     * - 캐시 사용으로 불필요한 API 호출 방지
     * - 타임아웃 설정으로 무한 대기 방지
     * - 재시도 횟수 제한
     */
    private fun fetchBusInfoOptimized(): Pair<Int, String>? {
        val currentTime = System.currentTimeMillis()

        // 캐시된 데이터가 유효한지 확인
        if (cachedBusInfo != null && (currentTime - lastApiCall) < CACHE_VALIDITY_MS) {
            Log.d(TAG, "🔄 [AutoAlarm] 캐시된 버스 정보 사용: ${cachedBusInfo?.first}분")
            return cachedBusInfo
        }

        var retryCount = 0
        while (retryCount < MAX_RETRY_COUNT) {
            try {
                Log.d(TAG, "🔍 [AutoAlarm] 실시간 버스 정보 조회 시작 (시도: ${retryCount + 1}/$MAX_RETRY_COUNT)")

                val apiService = BusApiService(applicationContext)
                val stationInfoJson = runBlocking {
                    withTimeoutOrNull(API_TIMEOUT_MS) {
                        withContext(Dispatchers.IO) {
                            apiService.getStationInfo(stationId)
                        }
                    }
                }

                if (stationInfoJson != null && stationInfoJson.isNotBlank() && stationInfoJson != "[]") {
                    val busInfo = parseBusInfoFromJson(stationInfoJson, routeId)
                    if (busInfo != null) {
                        // 캐시 업데이트
                        cachedBusInfo = busInfo
                        lastApiCall = currentTime
                        Log.d(TAG, "✅ [AutoAlarm] 버스 정보 조회 성공: ${busInfo.first}분, 현재위치: ${busInfo.second}")
                        return busInfo
                    }
                }

                Log.w(TAG, "⚠️ [AutoAlarm] 버스 정보 조회 실패, 재시도 중...")
                retryCount++

                // 재시도 전 잠시 대기 (배터리 절약)
                if (retryCount < MAX_RETRY_COUNT) {
                    Thread.sleep(1000L * retryCount) // 점진적 백오프
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ [AutoAlarm] API 호출 오류 (시도 ${retryCount + 1}): ${e.message}")
                retryCount++
            }
        }

        Log.e(TAG, "❌ [AutoAlarm] 모든 재시도 실패, 기본값 반환")
        return null
    }

    /**
     * 배터리 절약을 위한 최적화된 TTS 처리
     * - 백업 TTS 제거
     * - 한 번만 실행
     * - 즉시 실행 조건 개선
     */
    private fun handleOptimizedTTS(fetchedMinutes: Int?, fetchSuccess: Boolean) {
        try {
            Log.d(TAG, "🔊 자동 알람 TTS 발화 시작: $busNo 번")

            // TTS 메시지 생성 (간소화)
            val ttsMessage = if (fetchSuccess && fetchedMinutes != null) {
                when {
                    fetchedMinutes <= 0 -> "$busNo 번 버스가 곧 도착합니다."
                    fetchedMinutes == 1 -> "$busNo 번 버스가 약 1분 후 도착 예정입니다."
                    else -> "$busNo 번 버스가 약 ${fetchedMinutes}분 후 도착 예정입니다."
                }
            } else {
                "$busNo 번 버스가 곧 도착합니다."
            }

            // 즉시 실행 조건 확인 (중복 방지)
            val scheduledFor = inputData.getLong("scheduledFor", 0L)
            val currentTime = System.currentTimeMillis()
            val isImmediate = scheduledFor > 0 && (currentTime - scheduledFor) < 60000L // 1분 이내

            if (isImmediate) {
                Log.d(TAG, "⏰ [AutoAlarm] 즉시 실행된 알람 - TTS 건너뛰기")
                return
            }

            // 단일 TTS 실행 (백업 없음)
            val ttsIntent = Intent(applicationContext, TTSService::class.java).apply {
                action = "REPEAT_TTS_ALERT"
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("remainingMinutes", fetchedMinutes ?: 0)
                putExtra("currentStation", "")
                putExtra("isAutoAlarm", true)
                putExtra("forceSpeaker", true)
                putExtra("ttsMessage", ttsMessage)
                putExtra("singleExecution", true) // 단일 실행 플래그
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(ttsIntent)
            } else {
                applicationContext.startService(ttsIntent)
            }
            Log.d(TAG, "✅ 최적화된 TTS 서비스 시작 완료")

        } catch (e: Exception) {
            Log.e(TAG, "❌ 최적화된 TTS 처리 오류: ${e.message}", e)
        }
    }

    /**
     * 배터리 절약을 위한 경량화된 알림
     * - BusAlertService의 경량화 모드 사용
     * - Foreground Service 사용 안함
     */
    private fun showLightweightNotification(alarmId: Int, busNo: String, stationName: String, contentText: String, remainingMinutes: Int?, currentStation: String?) {
        try {
            Log.d(TAG, "📱 경량화된 알림 표시: $busNo 번")

            // BusAlertService의 경량화 모드 사용
            val lightweightIntent = Intent(applicationContext, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_START_AUTO_ALARM_LIGHTWEIGHT
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("remainingMinutes", remainingMinutes ?: 0)
                putExtra("currentStation", currentStation ?: "")
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                applicationContext.startForegroundService(lightweightIntent)
            } else {
                applicationContext.startService(lightweightIntent)
            }

            Log.d(TAG, "✅ BusAlertService 경량화 모드 시작 요청 완료")

        } catch (e: Exception) {
            Log.e(TAG, "❌ 경량화된 알림 표시 실패, 백업 알림 사용: ${e.message}")
            // 백업으로 직접 알림 표시
            showNotification(alarmId, busNo, stationName, contentText)
        }
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