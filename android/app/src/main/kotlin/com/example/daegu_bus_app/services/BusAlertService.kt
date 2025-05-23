package com.example.daegu_bus_app.services

import io.flutter.plugin.common.MethodChannel
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Binder
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import java.util.*
import java.util.Calendar
import kotlin.collections.HashMap
import kotlin.math.max
import kotlin.math.roundToInt
import android.media.AudioManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioDeviceInfo
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.os.Bundle
import org.json.JSONArray
import org.json.JSONObject
import com.example.daegu_bus_app.models.BusInfo
import com.example.daegu_bus_app.utils.NotificationHandler
import com.example.daegu_bus_app.MainActivity

class BusAlertService : Service() {
    companion object {
        private const val TAG = "BusAlertService"
        // Notification Channel IDs
        private const val CHANNEL_ID_ONGOING = "bus_tracking_ongoing"
        private const val CHANNEL_NAME_ONGOING = "실시간 버스 추적"
        private const val CHANNEL_ID_ALERT = "bus_tracking_alert"
        private const val CHANNEL_NAME_ALERT = "버스 도착 임박 알림"
        private const val CHANNEL_ID_ERROR = "bus_tracking_error"
        private const val CHANNEL_NAME_ERROR = "추적 오류 알림"
        private const val CHANNEL_BUS_ALERTS = "bus_alerts"

        // Notification IDs
        const val ONGOING_NOTIFICATION_ID = NotificationHandler.ONGOING_NOTIFICATION_ID

        // Intent Actions
        const val ACTION_START_TRACKING = "com.example.daegu_bus_app.action.START_TRACKING"
        const val ACTION_STOP_TRACKING = "com.example.daegu_bus_app.action.STOP_TRACKING"
        const val ACTION_STOP_SPECIFIC_ROUTE_TRACKING = "com.example.daegu_bus_app.action.STOP_SPECIFIC_ROUTE_TRACKING"
        const val ACTION_CANCEL_NOTIFICATION = "com.example.daegu_bus_app.action.CANCEL_NOTIFICATION"
        const val ACTION_START_TTS_TRACKING = "com.example.daegu_bus_app.action.START_TTS_TRACKING"
        const val ACTION_STOP_TTS_TRACKING = "com.example.daegu_bus_app.action.STOP_TTS_TRACKING"
        const val ACTION_START_TRACKING_FOREGROUND = "com.example.daegu_bus_app.action.START_TRACKING_FOREGROUND"
        const val ACTION_UPDATE_TRACKING = "com.example.daegu_bus_app.action.UPDATE_TRACKING"
        const val ACTION_STOP_BUS_ALERT_TRACKING = "com.example.daegu_bus_app.action.STOP_BUS_ALERT_TRACKING"

        // TTS Output Modes
        const val OUTPUT_MODE_HEADSET = 0  // 이어폰 전용 (현재 AUTO)
        const val OUTPUT_MODE_SPEAKER = 1  // 스피커 전용 (유지)
        const val OUTPUT_MODE_AUTO = 2     // 자동 감지 (현재 HEADSET)

        // Display Modes
        const val DISPLAY_MODE_ALARMED_ONLY = 0

        // Preference Keys
        const val PREF_ALARM_SOUND_FILENAME = "alarm_sound_filename"
        const val PREF_ALARM_USE_TTS = "alarm_use_tts"
        const val PREF_SPEAKER_MODE = "speaker_mode"
        const val PREF_NOTIFICATION_DISPLAY_MODE_KEY = "notification_display_mode"
        const val PREF_TTS_VOLUME = "tts_volume"

        // Default Values
        const val DEFAULT_ALARM_SOUND = ""

        // Keep instance for potential Singleton-like access if needed
        private var instance: BusAlertService? = null
        fun getInstance(): BusAlertService? = instance

        private const val ARRIVAL_THRESHOLD_MINUTES = 1
        private const val MAX_CONSECUTIVE_ERRORS = 3
    }

    private val binder = LocalBinder()
    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var busApiService: BusApiService
    private lateinit var sharedPreferences: SharedPreferences
    private lateinit var notificationHandler: NotificationHandler
    private var useTextToSpeech: Boolean = true
    private var isInForeground: Boolean = false

    // Tracking State
    private val monitoringJobs = HashMap<String, Job>()
    private val activeTrackings = HashMap<String, TrackingInfo>()
    private val monitoredRoutes = HashMap<String, Triple<String, String, Job?>>()
    private val cachedBusInfo = HashMap<String, BusInfo>()
    private val arrivingSoonNotified = HashSet<String>()
    private var isTtsTrackingActive = false

    // TTS/Audio variables
    private var ttsEngine: TextToSpeech? = null
    private var isTtsInitialized = false
    private val ttsInitializationLock = Object()
    private var ttsVolume: Float = 1.0f
    private var audioOutputMode: Int = OUTPUT_MODE_AUTO
    private var audioManager: AudioManager? = null
    private var audioFocusRequest: AudioFocusRequest? = null
    private var currentAlarmSound: String = DEFAULT_ALARM_SOUND
    private var notificationDisplayMode: Int = DISPLAY_MODE_ALARMED_ONLY
    private var monitoringTimer: Timer? = null

    // Simplified AudioFocusChangeListener
    private val audioFocusListener = AudioManager.OnAudioFocusChangeListener { focusChange ->
        Log.d(TAG, "Audio focus changed: $focusChange")
    }

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service onCreate")
        instance = this
        busApiService = BusApiService(applicationContext)
        sharedPreferences = applicationContext.getSharedPreferences("AppSettings", Context.MODE_PRIVATE)
        notificationHandler = NotificationHandler(this)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        loadSettings()
        notificationHandler.createNotificationChannels()
        initializeTts()
    }

    private fun loadSettings() {
        try {
            val prefs = applicationContext.getSharedPreferences("AppSettings", Context.MODE_PRIVATE)
            currentAlarmSound = prefs.getString(PREF_ALARM_SOUND_FILENAME, DEFAULT_ALARM_SOUND) ?: DEFAULT_ALARM_SOUND
            useTextToSpeech = prefs.getBoolean(PREF_ALARM_USE_TTS, true)
            audioOutputMode = prefs.getInt(PREF_SPEAKER_MODE, OUTPUT_MODE_AUTO)
            notificationDisplayMode = prefs.getInt(PREF_NOTIFICATION_DISPLAY_MODE_KEY, DISPLAY_MODE_ALARMED_ONLY)
            ttsVolume = prefs.getFloat(PREF_TTS_VOLUME, 1.0f).coerceIn(0f, 1f)
            Log.d(TAG, "⚙️ Settings loaded - TTS: $useTextToSpeech, Sound: $currentAlarmSound, NotifMode: $notificationDisplayMode, Output: $audioOutputMode, Volume: ${ttsVolume * 100}%")
        } catch (e: Exception) {
            Log.e(TAG, "⚙️ Error loading settings: ${e.message}")
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand Received: Action = ${intent?.action}, StartId=$startId")
        loadSettings()

        when (intent?.action) {
            ACTION_START_TRACKING -> {
                val routeId = intent.getStringExtra("routeId")
                val stationId = intent.getStringExtra("stationId")
                val stationName = intent.getStringExtra("stationName")
                val busNo = intent.getStringExtra("busNo")

                if (routeId != null && stationId != null && stationName != null && busNo != null) {
                    Log.i(TAG, "ACTION_START_TRACKING: routeId=$routeId, stationId=$stationId, stationName=$stationName, busNo=$busNo")
                    addMonitoredRoute(routeId, stationId, stationName)
                    startTracking(routeId, stationId, stationName, busNo)
                } else {
                    Log.e(TAG, "Missing data for ACTION_START_TRACKING")
                    stopTrackingIfIdle()
                }
            }
            ACTION_STOP_TRACKING -> {
                Log.i(TAG, "ACTION_STOP_TRACKING: Stopping all tracking.")

                // 현재 추적 중인 모든 버스에 대해 취소 이벤트 발송
                activeTrackings.forEach { (routeId, info) ->
                    sendCancellationBroadcast(info.busNo, routeId, info.stationName)
                }

                // 전체 취소 이벤트 발송
                sendAllCancellationBroadcast()

                // 모든 추적 작업과 서비스 중지
                Log.i(TAG, "Stopping all tracking jobs and the service.")
                stopAllTracking()
            }
            ACTION_STOP_SPECIFIC_ROUTE_TRACKING -> {
                val routeId = intent.getStringExtra("routeId")
                if (routeId != null) {
                    Log.i(TAG, "ACTION_STOP_SPECIFIC_ROUTE_TRACKING: routeId=$routeId")
                    stopTrackingForRoute(routeId, cancelNotification = true)
                } else {
                    Log.e(TAG, "Missing routeId for ACTION_STOP_SPECIFIC_ROUTE_TRACKING")
                    stopTrackingIfIdle()
                }
            }
            ACTION_CANCEL_NOTIFICATION -> {
                val notificationId = intent.getIntExtra("notificationId", -1)
                if (notificationId != -1) {
                    Log.i(TAG, "ACTION_CANCEL_NOTIFICATION: notificationId=$notificationId")
                    notificationHandler.cancelNotification(notificationId)

                    // 알림이 지속적인 추적 알림인 경우 서비스도 중지
                    if (notificationId == ONGOING_NOTIFICATION_ID) {
                        Log.i(TAG, "지속적인 추적 알림 취소. 서비스 중지 시도.")
                        stopAllTracking()
                    }

                    // Flutter 측에 알림 취소 이벤트 전송 시도
                    try {
                        val context = applicationContext
                        val intent = Intent("com.example.daegu_bus_app.NOTIFICATION_CANCELLED")
                        intent.putExtra("notificationId", notificationId)
                        context.sendBroadcast(intent)
                        Log.d(TAG, "알림 취소 이벤트 브로드캩0스트 전송: $notificationId")
                    } catch (e: Exception) {
                        Log.e(TAG, "알림 취소 이벤트 전송 오류: ${e.message}")
                    }
                }
            }
            ACTION_START_TTS_TRACKING -> {
                Log.w(TAG, "Received ACTION_START_TTS_TRACKING, but this should likely be handled by TTSService itself or specific internal logic.")
            }
            ACTION_STOP_TTS_TRACKING -> {
                Log.w(TAG, "Received ACTION_STOP_TTS_TRACKING.")
            }
            ACTION_START_TRACKING_FOREGROUND, ACTION_UPDATE_TRACKING -> {
                val busNo = intent.getStringExtra("busNo") ?: ""
                val stationName = intent.getStringExtra("stationName") ?: ""
                val remainingMinutes = intent.getIntExtra("remainingMinutes", -1)
                val currentStation = intent.getStringExtra("currentStation")
                val isUpdate = intent.action == ACTION_UPDATE_TRACKING
                val allBusesSummary = intent.getStringExtra("allBusesSummary")
                val routeId = intent.getStringExtra("routeId")
                var stationId = intent.getStringExtra("stationId")

                if (routeId == null || busNo.isBlank() || stationName.isBlank()) {
                    Log.e(TAG, "${intent.action} Aborted: Missing required info")
                    stopTrackingIfIdle()
                    return START_NOT_STICKY
                }

                // --- stationId 보정 로직 추가 ---
                if (stationId.isNullOrBlank()) {
                    // routeId가 10자리 숫자(7로 시작)면 stationId로 잘못 들어온 것일 수 있으니 분리
                    if (routeId.length == 10 && routeId.startsWith("7")) {
                        // 실제 routeId는 busApiService.getRouteIdByStationId 등으로 찾아야 함(여기선 생략)
                        Log.w(TAG, "routeId가 10자리 stationId로 들어옴. stationId로 간주: $routeId");
                        val fixedStationId = routeId
                        addMonitoredRoute(routeId, fixedStationId, stationName)
                        startTracking(routeId, fixedStationId, stationName, busNo)
                        return START_STICKY
                    }
                    // stationId가 비어있으면 코루틴에서 보정 시도
                    serviceScope.launch {
                        val fixedStationId = resolveStationIdIfNeeded(routeId, stationName, "", null)
                        if (fixedStationId.isNotBlank()) {
                            addMonitoredRoute(routeId, fixedStationId, stationName)
                            startTracking(routeId, fixedStationId, stationName, busNo)
                        } else {
                            Log.e(TAG, "stationId 보정 실패. 추적 불가: routeId=$routeId, busNo=$busNo, stationName=$stationName")
                            stopTrackingIfIdle()
                        }
                    }
                    return START_NOT_STICKY
                }

                if (intent.action == ACTION_START_TRACKING_FOREGROUND && stationId != null) {
                    addMonitoredRoute(routeId, stationId, stationName)
                }

                // 업데이트 요청인 경우 추적 정보도 업데이트
                if (isUpdate) {
                    Log.d(TAG, "업데이트 요청 수신: $busNo, $stationName, 현재 위치: $currentStation")

                    // 추적 정보 업데이트
                    updateTrackingInfoFromFlutter(
                        routeId = routeId,
                        busNo = busNo,
                        stationName = stationName,
                        remainingMinutes = remainingMinutes,
                        currentStation = currentStation ?: "정보 없음"
                    )
                }

                showOngoingBusTracking(
                    busNo = busNo,
                    stationName = stationName,
                    remainingMinutes = remainingMinutes,
                    currentStation = currentStation,
                    isUpdate = isUpdate,
                    notificationId = ONGOING_NOTIFICATION_ID,
                    allBusesSummary = allBusesSummary,
                    routeId = routeId
                )
                // [AUTO ALARM 실시간 정보 즉시 갱신] autoAlarmTask 등 자동알람 진입점에서 실시간 정보 즉시 fetch
                if (routeId != null && !routeId.isBlank() && stationId != null && !stationId.isBlank() && stationName.isNotBlank()) {
                    updateBusInfo(routeId, stationId, stationName)
                }
            }
            ACTION_STOP_BUS_ALERT_TRACKING -> {
                val routeId = intent.getStringExtra("routeId")
                val stationId = intent.getStringExtra("stationId")
                val busNo = intent.getStringExtra("busNo")
                Log.i(TAG, "Notification Action '$intent.action': Route=$routeId, Station=$stationId, Bus=$busNo")
                if (routeId != null) {
                    stopTrackingForRoute(routeId, stationId = stationId, busNo = busNo, cancelNotification = true)
                } else {
                    Log.e(TAG, "Missing routeId for $intent.action")
                    stopTrackingIfIdle()
                }
            }
            else -> {
                Log.w(TAG, "Unhandled action received: $intent.action")
                stopTrackingIfIdle()
            }
        }

        return START_STICKY
    }

    override fun onDestroy() {
        Log.i(TAG, "🔔 BusAlertService onDestroy Starting")
        instance = null
        serviceScope.launch {
            try {
                stopTracking()
                ttsEngine?.stop()
                ttsEngine?.shutdown()
                Log.d(TAG, "TTS Engine shutdown.")
            } catch (e: Exception) {
                Log.e(TAG, "Error during onDestroy cleanup: ${e.message}")
            } finally {
                ttsEngine = null
                isTtsInitialized = false
                audioManager?.abandonAudioFocus(audioFocusListener)
                Log.d(TAG, "Audio focus abandoned.")
            }
        }.invokeOnCompletion {
            serviceScope.cancel("Service Destroyed")
            Log.i(TAG, "Service scope cancelled.")
            super.onDestroy()
            Log.i(TAG, "🔔 BusAlertService onDestroy Finished")
        }
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    inner class LocalBinder : Binder() {
        fun getService(): BusAlertService = this@BusAlertService
    }

    data class TrackingInfo(
        val routeId: String,
        val stationName: String,
        val busNo: String,
        var lastBusInfo: BusInfo? = null,
        var consecutiveErrors: Int = 0,
        var lastUpdateTime: Long = System.currentTimeMillis(),
        var lastNotifiedMinutes: Int = Int.MAX_VALUE,
        var stationId: String = "",
        // [추가] TTS 중복 방지용
        var lastTtsAnnouncedMinutes: Int? = null,
        var lastTtsAnnouncedStation: String? = null
    )

    private fun startTracking(routeId: String, stationId: String, stationName: String, busNo: String) {
        serviceScope.launch {
            var realStationId = stationId
            if (stationId.length < 10 || !stationId.startsWith("7")) {
                // 변환 필요
                realStationId = busApiService.getStationIdFromBsId(stationId) ?: stationId
                Log.d(TAG, "stationId 변환: $stationId → $realStationId")
            }
            startTrackingInternal(routeId, realStationId, stationName, busNo)
        }
    }

    private fun startTrackingInternal(routeId: String, stationId: String, stationName: String, busNo: String) {
        if (monitoringJobs.containsKey(routeId)) {
            Log.d(TAG, "Tracking already active for route $routeId")
            return
        }

        Log.i(TAG, "Starting tracking for route $routeId ($busNo) at station $stationName ($stationId)")
        val trackingInfo = TrackingInfo(routeId, stationName, busNo, stationId = stationId)
        activeTrackings[routeId] = trackingInfo

        monitoringJobs[routeId] = serviceScope.launch {
            try {
                while (isActive) {
                    try {
                        val arrivals = busApiService.getStationInfo(stationId)
                            .let { jsonString ->
                                if (jsonString.isBlank() || jsonString == "[]") emptyList()
                                else parseJsonBusArrivals(jsonString, routeId)
                            }

                        if (!activeTrackings.containsKey(routeId)) {
                            Log.w(TAG, "Tracking info for $routeId removed. Stopping loop.")
                            break
                        }
                        val currentInfo = activeTrackings[routeId] ?: break
                        currentInfo.consecutiveErrors = 0

                        val firstBus = arrivals.firstOrNull { !it.isOutOfService }

                        if (firstBus != null) {
                            val remainingMinutes = firstBus.getRemainingMinutes()
                            Log.d(TAG, "🚌 Route $routeId ($busNo): Next bus in $remainingMinutes min. At: ${firstBus.currentStation}")

                            // 버스 정보 업데이트
                            currentInfo.lastBusInfo = firstBus
                            currentInfo.lastUpdateTime = System.currentTimeMillis()

                            // 곧 도착 상태에서도 currentStation이 항상 실시간 위치로 들어가도록 보장
                            val currentStation = if (!firstBus.currentStation.isNullOrBlank()) {
                                firstBus.currentStation
                            } else {
                                currentInfo.lastBusInfo?.currentStation ?: trackingInfo.stationName ?: "정보 없음"
                            }
                            Log.d(TAG, "showOngoingBusTracking 호출(곧 도착): busNo=$busNo, remainingMinutes=$remainingMinutes, currentStation=$currentStation, routeId=$routeId")

                            // 실시간 버스 정보로 포그라운드 알림 즉시 업데이트
                            val allBusesSummary = activeTrackings.values.joinToString("\n") { info ->
                                "${info.busNo}: ${info.lastBusInfo?.estimatedTime ?: "정보 없음"} (${info.lastBusInfo?.currentStation ?: "위치 정보 없음"})"
                            }
                            showOngoingBusTracking(
                                busNo = busNo,
                                stationName = stationName,
                                remainingMinutes = remainingMinutes,
                                currentStation = currentStation, // 실시간 위치(항상 보장)
                                isUpdate = true,
                                notificationId = ONGOING_NOTIFICATION_ID,
                                allBusesSummary = allBusesSummary,
                                routeId = routeId
                            )
                            // 알림 강제 갱신(백업)
                            updateForegroundNotification()
                            // 도착 알림 체크
                            checkArrivalAndNotify(currentInfo, firstBus)

                            // [수정] 음성 알림 조건 완화: 5분 이하에서 TTSService 호출, 중복 방지 개선
                            Log.d(TAG, "[TTS] 호출 조건 체크: useTextToSpeech=$useTextToSpeech, remainingMinutes=$remainingMinutes, lastNotifiedMinutes=${currentInfo.lastNotifiedMinutes}")
                            if (useTextToSpeech && remainingMinutes <= 5 && remainingMinutes >= 0) {
                                val ttsShouldAnnounce =
                                    (currentInfo.lastTtsAnnouncedMinutes == null || currentInfo.lastTtsAnnouncedMinutes != remainingMinutes) ||
                                    (currentInfo.lastTtsAnnouncedStation == null || currentInfo.lastTtsAnnouncedStation != currentStation)
                                if (ttsShouldAnnounce) {
                                    val ttsMessage = when (firstBus.estimatedTime) {
                                        "곧 도착" -> "${currentInfo.busNo}번 버스가 ${currentInfo.stationName} 정류장에 곧 도착합니다."
                                        "출발예정", "기점출발예정" -> null // TTS 울리지 않음
                                        else -> "${currentInfo.busNo}번 버스가 ${currentInfo.stationName} 정류장에 약 ${remainingMinutes}분 후 도착 예정입니다."
                                    }
                                    if (ttsMessage != null) {
                                        speakTts(ttsMessage)
                                        currentInfo.lastTtsAnnouncedMinutes = remainingMinutes
                                        currentInfo.lastTtsAnnouncedStation = currentStation
                                        Log.d(TAG, "[TTS] 실시간 TTS 안내: $ttsMessage (중복 방지 적용)")
                                    } else {
                                        Log.d(TAG, "[TTS] TTS 메시지 없음(출발예정 등): estimatedTime=${firstBus.estimatedTime}")
                                    }
                                } else {
                                    Log.d(TAG, "[TTS] 중복 방지로 TTS 미호출: remainingMinutes=$remainingMinutes, currentStation=$currentStation")
                                }
                            } else if (remainingMinutes < 0) {
                                currentInfo.lastTtsAnnouncedMinutes = null
                                currentInfo.lastTtsAnnouncedStation = null
                            }
                        } else {
                            Log.w(TAG, "No available buses for route $routeId at $stationId.")
                            currentInfo.lastBusInfo = null
                            updateForegroundNotification()
                        }

                        // 정기적인 업데이트 - 15초 간격으로 로그 출력 (디버깅용)
                        if (activeTrackings.isNotEmpty()) {
                            Log.d(TAG, "⏰ 현재 추적 중: ${activeTrackings.size}개 노선, 다음 업데이트 30초 후")
                        }

                        // 30초마다 업데이트 (기존 60초에서 변경)
                        delay(30000)
                    } catch (e: CancellationException) {
                        Log.i(TAG, "Tracking job for $routeId cancelled.")
                        break
                    } catch (e: Exception) {
                        Log.e(TAG, "Error tracking $routeId: ${e.message}", e)
                        val currentInfo = activeTrackings[routeId]
                        if (currentInfo != null) {
                            currentInfo.consecutiveErrors++
                            if (currentInfo.consecutiveErrors >= 3) {
                                Log.e(TAG, "Stopping tracking for $routeId due to errors.")
                                notificationHandler.sendErrorNotification(routeId, currentInfo.busNo, currentInfo.stationName, "정보 조회 실패")
                            }
                        }
                        updateForegroundNotification()
                        delay(30000)
                    }
                }
                Log.i(TAG, "Tracking loop finished for route $routeId")
            } finally {
                if (activeTrackings.containsKey(routeId)) {
                    Log.w(TAG, "Tracker coroutine for $routeId ended unexpectedly (scope cancellation?). Triggering cleanup.")
                    stopTrackingForRoute(routeId, cancelNotification = true)
                }
            }
        }

        // 백업 타이머 시작 - 5분마다 알림 갱신 (메인 업데이트가 실패할 경우를 대비)
        startBackupUpdateTimer()
    }

    // 백업 타이머 추가 - 노티피케이션이 갱신되지 않는 문제 해결
    private fun startBackupUpdateTimer() {
        if (monitoringTimer != null) {
            try {
                monitoringTimer?.cancel()
                monitoringTimer = null
                Log.d(TAG, "기존 백업 타이머 취소")
            } catch (e: Exception) {
                Log.e(TAG, "기존 타이머 취소 중 오류: ${e.message}", e)
            }
        }

        monitoringTimer = Timer("BackupUpdateTimer")
        monitoringTimer?.schedule(object : TimerTask() {
            override fun run() {
                try {
                    if (activeTrackings.isEmpty()) {
                        Log.d(TAG, "백업 타이머: 활성 추적 없음, 타이머 종료")
                        monitoringTimer?.cancel()
                        monitoringTimer = null
                        return
                    }

                    Log.d(TAG, "🔄 백업 타이머: 활성 노티피케이션 갱신 (${activeTrackings.size}개 추적 중)")

                    // 메인 스레드에서 UI 작업 실행
                    Handler(Looper.getMainLooper()).post {
                        // 포그라운드 알림 즉시 업데이트
                        try {
                            val notification = notificationHandler.buildOngoingNotification(activeTrackings)
                            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                            notificationManager.notify(ONGOING_NOTIFICATION_ID, notification)
                            Log.d(TAG, "✅ 백업 타이머: 포그라운드 알림 업데이트 성공")
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ 백업 타이머: 포그라운드 알림 업데이트 실패: ${e.message}", e)
                        }

                        // 각 추적 중인 노선의 정보도 업데이트 (백그라운드에서)
                        serviceScope.launch {
                            activeTrackings.forEach { (routeId, info) ->
                                try {
                                    val stationId = info.stationId
                                    if (stationId.isNotEmpty()) {
                                        Log.d(TAG, "🔄 백업 타이머: $routeId 노선 정보 업데이트 시도")
                                        updateBusInfo(routeId, stationId, info.stationName)
                                    } else {
                                        Log.w(TAG, "⚠️ 백업 타이머: $routeId 노선의 stationId가 비어있음")
                                    }
                                } catch (e: Exception) {
                                    Log.e(TAG, "❌ 백업 타이머 노선 업데이트 오류: ${e.message}", e)
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 백업 타이머 오류: ${e.message}", e)
                }
            }
        }, 10000, 30000)  // 10초 후 시작, 30초마다 반복 (기존 60초에서 변경)

        Log.d(TAG, "✅ 백업 타이머 시작됨: 10초 후 첫 실행, 30초 간격")
    }

    // JSON에서 버스 도착 정보 파싱하는 함수
    private fun parseJsonBusArrivals(jsonString: String, inputRouteId: String): List<BusInfo> {
        return try {
            val jsonArray = JSONArray(jsonString)
            val busInfoList = mutableListOf<BusInfo>()
            for (i in 0 until jsonArray.length()) {
                val routeObj = jsonArray.getJSONObject(i)
                val arrList = routeObj.optJSONArray("arrList") ?: continue
                for (j in 0 until arrList.length()) {
                    val busObj = arrList.getJSONObject(j)
                    if (busObj.optString("routeId", "") != inputRouteId) continue
                    busInfoList.add(
                        BusInfo(
                            currentStation = busObj.optString("bsNm", null) ?: "정보 없음",
                            estimatedTime = busObj.optString("arrState", null) ?: "정보 없음",
                            remainingStops = busObj.optString("bsGap", null) ?: "0",
                            busNumber = busObj.optString("routeNo", null) ?: "",
                            isLowFloor = busObj.optString("busTCd2", "N") == "1",
                            isOutOfService = busObj.optString("arrState", "") == "운행종료"
                        )
                    )
                }
            }
            busInfoList
        } catch (e: Exception) {
            Log.e(TAG, "❌ 버스 도착 정보 파싱 오류: ${e.message}", e)
            emptyList()
        }
    }

    // 버스 업데이트 함수 개선
    private fun updateBusInfo(routeId: String, stationId: String, stationName: String) {
        try {
            serviceScope.launch {
                try {
                    val jsonString = busApiService.getStationInfo(stationId)
                    val busInfoList = parseJsonBusArrivals(jsonString, routeId)
                    val firstBus = busInfoList.firstOrNull { !it.isOutOfService }
                    val trackingInfo = activeTrackings[routeId]

                    if (trackingInfo != null) {
                        if (firstBus != null) {
                            trackingInfo.lastBusInfo = firstBus
                            trackingInfo.consecutiveErrors = 0
                            trackingInfo.lastUpdateTime = System.currentTimeMillis()

                            val remainingMinutes = firstBus.getRemainingMinutes()

                            // 실시간 정보 로깅
                            Log.d(TAG, "🔄 버스 정보 업데이트: ${trackingInfo.busNo}번 버스, ${remainingMinutes}분 후 도착 예정, 현재 위치: ${firstBus.currentStation}")

                            // 노티피케이션 업데이트
                            try {
                                showOngoingBusTracking(
                                    busNo = trackingInfo.busNo,
                                    stationName = stationName,
                                    remainingMinutes = remainingMinutes,
                                    currentStation = firstBus.currentStation,
                                    isUpdate = true,
                                    notificationId = ONGOING_NOTIFICATION_ID,
                                    routeId = routeId,
                                    allBusesSummary = null
                                )
                                updateForegroundNotification()
                                Log.d(TAG, "✅ 노티피케이션 업데이트 완료: ${trackingInfo.busNo}번")
                            } catch (e: Exception) {
                                Log.e(TAG, "❌ 노티피케이션 업데이트 실패: ${e.message}", e)
                                // 실패 시 백업 방법으로 노티피케이션 업데이트
                                updateForegroundNotification()
                            }

                            // 도착 임박 체크
                            checkArrivalAndNotify(trackingInfo, firstBus)
                        } else {
                            trackingInfo.consecutiveErrors++
                            Log.w(TAG, "⚠️ 버스 정보 없음 (${trackingInfo.consecutiveErrors}번째): ${trackingInfo.busNo}번 (lastBusInfo 기존 값 유지)")

                            if (trackingInfo.consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
                                Log.e(TAG, "❌ 연속 오류 한도 초과로 추적 중단: ${trackingInfo.busNo}번")
                                stopTrackingForRoute(routeId, cancelNotification = true)
                            } else {
                                // 정보가 없어도 노티피케이션은 업데이트
                                updateForegroundNotification()
                            }
                        }
                        // [추가] 실시간 정보 fetch 후 알림 강제 갱신
                        updateForegroundNotification()
                    }
                } catch(e: Exception) {
                    Log.e(TAG, "버스 정보 업데이트 코루틴 오류: ${e.message}", e)
                    // 오류 발생 시에도 노티피케이션 업데이트 시도
                    updateForegroundNotification()
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "버스 정보 업데이트 오류: ${e.message}", e)
        }
    }

    private fun startTTSServiceSpeak(busNo: String, stationName: String, routeId: String, stationId: String, remainingMinutes: Int = -1, forceSpeaker: Boolean = false, currentStation: String? = null) {
        val isHeadset = isHeadsetConnected()
        // 이어폰 전용 모드일 때 이어폰이 연결되어 있지 않으면 TTSService 호출하지 않음 (단, forceSpeaker면 무시)
        if (!forceSpeaker && audioOutputMode == OUTPUT_MODE_HEADSET && !isHeadset) {
            Log.w(TAG, "이어폰 전용 모드이나 이어폰이 연결되어 있지 않아 TTSService 호출 안함 (audioOutputMode=$audioOutputMode, isHeadset=$isHeadset)")
            return
        }

        // 이어폰 연결 상태 로깅
        // Log.d(TAG, "🎧 TTSService 호출 전 이어폰 연결 상태: $isHeadset, 모드: $audioOutputMode")

        val ttsIntent = Intent(this, TTSService::class.java).apply {
            action = "REPEAT_TTS_ALERT"
            putExtra("busNo", busNo)
            putExtra("stationName", stationName)
            putExtra("routeId", routeId)
            putExtra("stationId", stationId)
            putExtra("remainingMinutes", remainingMinutes)
            putExtra("currentStation", (currentStation ?: "").toString())
            if (forceSpeaker) putExtra("forceSpeaker", true)
        }
        startService(ttsIntent)
        // Log.d(TAG, "Requested TTSService to speak for $busNo")
    }

    private fun stopTTSServiceTracking(routeId: String? = null) {
        try {
            val ttsIntent = Intent(this, TTSService::class.java).apply {
                action = "STOP_TTS_TRACKING"
            }
            startService(ttsIntent)
            Log.d(TAG, "Requested TTSService to stop tracking ${routeId ?: "(all)"}")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping TTSService tracking: ${e.message}", e)
        }
    }

    private fun initializeTts() {
        if (isTtsInitialized || ttsEngine != null) return
        synchronized(ttsInitializationLock) {
            if (isTtsInitialized || ttsEngine != null) return
            Log.d(TAG, "🔊 Initializing TTS Engine...")
            try {
                ttsEngine = TextToSpeech(this, TextToSpeech.OnInitListener { status ->
                    Log.d(TAG, "🔊 TTS OnInitListener called. Status: $status")
                    if (status == TextToSpeech.SUCCESS) {
                        val result = ttsEngine?.setLanguage(Locale.KOREAN)
                        Log.d(TAG, "🔊 TTS setLanguage result: $result")
                        if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                            Log.e(TAG, "🔊 TTS Korean language not supported.")
                            ttsEngine = null
                            isTtsInitialized = false
                        } else {
                            ttsEngine?.setPitch(1.0f)
                            ttsEngine?.setSpeechRate(1.0f)
                            isTtsInitialized = true
                            Log.i(TAG, "🔊 TTS Engine Initialized Successfully.")
                        }
                    } else {
                        Log.e(TAG, "🔊 TTS Engine Initialization Failed! Status: $status")
                        ttsEngine = null
                        isTtsInitialized = false
                    }
                })
            } catch (e: Exception) {
                Log.e(TAG, "🔊 TTS Engine Initialization Exception: ${e.message}", e)
                ttsEngine = null
                isTtsInitialized = false
            }
        }
    }

    private fun createTtsListener(): UtteranceProgressListener {
        return object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {
                Log.d(TAG, "TTS Start: $utteranceId")
            }
            override fun onDone(utteranceId: String?) {
                Log.d(TAG, "TTS Done: $utteranceId")
                audioManager?.abandonAudioFocus(audioFocusListener)
            }
            override fun onError(utteranceId: String?) {
                Log.e(TAG, "TTS Error: $utteranceId")
                audioManager?.abandonAudioFocus(audioFocusListener)
            }
            override fun onError(utteranceId: String?, errorCode: Int) {
                Log.e(TAG, "TTS Error: $utteranceId, Code: $errorCode")
                audioManager?.abandonAudioFocus(audioFocusListener)
            }
        }
    }

    fun initialize() {
        Log.d(TAG, "Service initialize called")
        busApiService = BusApiService(applicationContext)
        notificationHandler = NotificationHandler(this)
        loadSettings()
        notificationHandler.createNotificationChannels()
        initializeTts()
    }

    fun addMonitoredRoute(routeId: String, stationId: String, stationName: String) {
        monitoredRoutes[routeId] = Triple(stationId, stationName, monitoringJobs[routeId])
        Log.d(TAG, "Added route to monitored list: $routeId at $stationName ($stationId)")
    }

    // stationId 보정 함수 (wincId 우선)
    private suspend fun resolveStationIdIfNeeded(routeId: String, stationName: String, stationId: String, wincId: String?): String {
        if (stationId.length == 10 && stationId.startsWith("7")) return stationId
        // 1. wincId가 있으면 우선 사용
        if (!wincId.isNullOrBlank()) {
            val fixed = busApiService.getStationIdFromBsId(wincId)
            if (!fixed.isNullOrBlank()) {
                Log.d(TAG, "resolveStationIdIfNeeded: wincId=$wincId → stationId=$fixed")
                return fixed
            }
        }
        // 2. routeId로 노선 정류장 리스트 조회 후, stationName 유사 매칭(보조)
        val stations = busApiService.getBusRouteMap(routeId)
        val found = stations.find { normalize(it.stationName) == normalize(stationName) }
        if (found != null && found.stationId.isNotBlank()) {
            Log.d(TAG, "resolveStationIdIfNeeded: routeId=$routeId, stationName=$stationName → stationId=${found.stationId}")
            return found.stationId
        }
        // 3. 그래도 안되면 stationName을 wincId로 간주
        val fallback = busApiService.getStationIdFromBsId(stationName)
        if (!fallback.isNullOrBlank()) {
            Log.d(TAG, "resolveStationIdIfNeeded: fallback getStationIdFromBsId($stationName) → $fallback")
            return fallback
        }
        Log.w(TAG, "resolveStationIdIfNeeded: stationId 보정 실패 (routeId=$routeId, stationName=$stationName, wincId=$wincId)")
        return ""
    }
    private fun normalize(name: String) = name.replace("\\s".toRegex(), "").replace("[^\\p{L}\\p{N}]".toRegex(), "")

    // showOngoingBusTracking에서 wincId 파라미터 추가
    fun showOngoingBusTracking(
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String?,
        isUpdate: Boolean,
        notificationId: Int,
        allBusesSummary: String?,
        routeId: String?,
        stationId: String? = null,
        wincId: String? = null
    ) {
        // Log current time but don't restrict notifications
        val currentHour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        if (currentHour < 5 || currentHour >= 23) {
            Log.w(TAG, "⚠️ 현재 버스 운행 시간이 아닙니다 (현재 시간: ${currentHour}시). 테스트 목적으로 계속 진행합니다.")
        }
        val effectiveRouteId = routeId ?: "temp_${busNo}_${stationName.hashCode()}"
        val trackingInfo = activeTrackings[effectiveRouteId] ?: TrackingInfo(
            routeId = effectiveRouteId,
            stationName = stationName,
            busNo = busNo
        ).also { activeTrackings[effectiveRouteId] = it }

        Log.d(TAG, "🔄 showOngoingBusTracking: $busNo, $stationName, $remainingMinutes, currentStation='$currentStation'")

        // stationId 보정
        var effectiveStationId = stationId ?: trackingInfo.stationId
        if (effectiveStationId.isBlank() || effectiveStationId.length < 10 || !effectiveStationId.startsWith("7")) {
            serviceScope.launch {
                val fixedStationId = resolveStationIdIfNeeded(effectiveRouteId, stationName, effectiveStationId, wincId)
                if (fixedStationId.isNotBlank()) {
                    showOngoingBusTracking(
                        busNo, stationName, remainingMinutes, currentStation, isUpdate, notificationId, allBusesSummary, routeId, fixedStationId, wincId
                    )
                } else {
                    Log.e(TAG, "❌ stationId 보정 실패: $routeId, $busNo, $stationName")
                }
            }
            return
        }

        // BusInfo 생성 (remainingMinutes는 BusInfo에서 파생)
        // Check if the bus is out of service based on time
        val isOutOfService = remainingMinutes < 0 ||
                            (trackingInfo.lastBusInfo?.isOutOfService == true) ||
                            (currentStation?.contains("운행종료") == true)

        val busInfo = BusInfo(
            currentStation = currentStation ?: "정보 없음",
            estimatedTime = if (isOutOfService) "운행종료" else when {
                remainingMinutes <= 0 -> "곧 도착"
                remainingMinutes == 1 -> "1분"
                else -> "${remainingMinutes}분"
            },
            remainingStops = trackingInfo.lastBusInfo?.remainingStops ?: "0",
            busNumber = busNo,
            isLowFloor = trackingInfo.lastBusInfo?.isLowFloor ?: false,
            isOutOfService = isOutOfService
        )
        trackingInfo.lastBusInfo = busInfo
        trackingInfo.lastUpdateTime = System.currentTimeMillis()
        trackingInfo.stationId = effectiveStationId

        val minutes = busInfo.getRemainingMinutes()
        val formattedTime = when (val minutes = busInfo.getRemainingMinutes()) {
            in Int.MIN_VALUE..0 -> if (busInfo.estimatedTime.isNotEmpty()) busInfo.estimatedTime else "정보 없음"
            1 -> "1분"
            else -> "${minutes}분"
        }
        val currentStationFinal = busInfo.currentStation

        Log.d(TAG, "✅ lastBusInfo 갱신: $busNo, $formattedTime, '$currentStationFinal'")

        // TTS 알림
        try {
            val lastSpokenMinutes = trackingInfo.lastNotifiedMinutes
            if (useTextToSpeech && minutes in 0..5) {
                if (lastSpokenMinutes == Int.MAX_VALUE || lastSpokenMinutes > minutes) {
                    val ttsIntent = Intent(this, TTSService::class.java).apply {
                        action = "REPEAT_TTS_ALERT"
                        putExtra("busNo", busNo)
                        putExtra("stationName", stationName)
                        putExtra("routeId", effectiveRouteId)
                        putExtra("stationId", effectiveStationId)
                        putExtra("remainingMinutes", minutes as Int)
                        putExtra("currentStation", (currentStationFinal ?: "").toString())
                    }
                    startService(ttsIntent)
                    trackingInfo.lastNotifiedMinutes = minutes
                    Log.d(TAG, "[TTS] 실시간 TTSService 호출: $busNo, $stationName, $minutes, stationId=$effectiveStationId")
                }
            } else if (minutes > 5 && trackingInfo.lastNotifiedMinutes != Int.MAX_VALUE) {
                trackingInfo.lastNotifiedMinutes = Int.MAX_VALUE
            }
        } catch (e: Exception) {
            Log.e(TAG, "[TTS] 오류: ${e.message}", e)
        }

        // 알림 갱신
        try {
            val notification = notificationHandler.buildOngoingNotification(activeTrackings)
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(ONGOING_NOTIFICATION_ID, notification)
            Log.d(TAG, "✅ 알림 업데이트: $busNo, $formattedTime, $currentStationFinal")
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    notificationManager.notify(ONGOING_NOTIFICATION_ID, notificationHandler.buildOngoingNotification(activeTrackings))
                } catch (_: Exception) {}
            }, 1000)
        } catch (e: Exception) {
            Log.e(TAG, "❌ 알림 업데이트 오류: ${e.message}", e)
            updateForegroundNotification()
        }
    }

    fun updateAutoAlarmBusInfo(
        busNo: String,
        stationName: String,
        routeId: String,
        stationId: String,
        remainingMinutes: Int,
        currentStation: String
    ) {
        Log.d(TAG, "🔄 updateAutoAlarmBusInfo: $busNo, $stationName, $remainingMinutes, '$currentStation'")
        val info = activeTrackings[routeId] ?: TrackingInfo(
            routeId = routeId,
            stationName = stationName,
            busNo = busNo,
            stationId = stationId
        ).also { activeTrackings[routeId] = it }

        // Check if the bus is out of service based on time
        val isOutOfService = remainingMinutes < 0 ||
                            (info.lastBusInfo?.isOutOfService == true) ||
                            (currentStation.contains("운행종료"))

        val busInfo = BusInfo(
            currentStation = currentStation,
            estimatedTime = if (isOutOfService) "운행종료" else when {
                remainingMinutes <= 0 -> "곧 도착"
                remainingMinutes == 1 -> "1분"
                else -> "${remainingMinutes}분"
            },
            remainingStops = info.lastBusInfo?.remainingStops ?: "0",
            busNumber = busNo,
            isLowFloor = info.lastBusInfo?.isLowFloor ?: false,
            isOutOfService = isOutOfService
        )
        info.lastBusInfo = busInfo
        info.lastUpdateTime = System.currentTimeMillis()
        info.stationId = stationId

        showOngoingBusTracking(
            busNo = busNo,
            stationName = stationName,
            remainingMinutes = busInfo.getRemainingMinutes(),
            currentStation = busInfo.currentStation,
            isUpdate = true,
            notificationId = ONGOING_NOTIFICATION_ID,
            allBusesSummary = null,
            routeId = routeId,
            stationId = stationId
        )
    }

    private fun checkAndStopServiceIfNeeded() {
        if (activeTrackings.isEmpty() && monitoredRoutes.isEmpty() && !isTtsTrackingActive) {
            Log.i(TAG, "Service idle. Requesting stop.")
            stopSelf()
        } else {
            Log.d(TAG, "Service not idle (Active: ${activeTrackings.size}, Monitored: ${monitoredRoutes.size}, TTS: $isTtsTrackingActive).")
        }
    }

    fun setAlarmSound(filename: String, useTts: Boolean = false) {
        Log.d(TAG, "setAlarmSound called: $filename, TTS: $useTts")
        currentAlarmSound = filename
        useTextToSpeech = useTts
        val prefs = applicationContext.getSharedPreferences("AppSettings", Context.MODE_PRIVATE)
        prefs.edit().putString(PREF_ALARM_SOUND_FILENAME, currentAlarmSound).putBoolean(PREF_ALARM_USE_TTS, useTextToSpeech).apply()
    }

    fun setAudioOutputMode(mode: Int) {
        Log.d(TAG, "setAudioOutputMode called: $mode")
        if (mode in OUTPUT_MODE_HEADSET..OUTPUT_MODE_AUTO) {
            audioOutputMode = mode
            val prefs = applicationContext.getSharedPreferences("AppSettings", Context.MODE_PRIVATE)
            prefs.edit().putInt(PREF_SPEAKER_MODE, audioOutputMode).apply()
        }
    }

    fun getAudioOutputMode(): Int = audioOutputMode

    fun isHeadsetConnected(): Boolean {
        if (audioManager == null) {
            Log.w(TAG, "AudioManager null in isHeadsetConnected")
            return false
        }
        try {
            // 1. 기본 방식으로 체크 (이전 방식 - 안정성을 위해 유지)
            val isWired = audioManager?.isWiredHeadsetOn ?: false
            val isA2dp = audioManager?.isBluetoothA2dpOn ?: false
            val isSco = audioManager?.isBluetoothScoOn ?: false

            // 2. Android 6 이상의 경우 AudioDeviceInfo로 더 정확하게 체크 (추가)
            var hasHeadset = false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                val devices = audioManager?.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                if (devices != null) {
                    Log.d(TAG, "[DEBUG] AudioDeviceInfo 목록:")
                    for (device in devices) {
                        val type = device.type
                        Log.d(TAG, "[DEBUG] AudioDeviceInfo: type=$type, productName=${device.productName}, id=${device.id}, isSink=${device.isSink}")
                        if (type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                            type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                            type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                            type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
                            type == AudioDeviceInfo.TYPE_USB_HEADSET) {
                                hasHeadset = true
                                break
                        }
                    }
                }
                Log.d(TAG, "🎧 Modern headset check: hasHeadset=$hasHeadset")
            }

            // 두 방식 중 하나라도 헤드셋 연결을 감지하면 true 반환
            val isConnected = isWired || isA2dp || isSco || hasHeadset
            Log.d(TAG, "🎧 Headset status: Wired=$isWired, A2DP=$isA2dp, SCO=$isSco, Modern=$hasHeadset -> Connected=$isConnected")
            return isConnected
        } catch (e: Exception) {
            Log.e(TAG, "🎧 Error checking headset status: ${e.message}", e)
            return false
        }
    }

    fun speakTts(text: String, earphoneOnly: Boolean = false) {
        Log.d(TAG, "🎧 speakTts 이어폰 체크 시작: earphoneOnly=$earphoneOnly, audioOutputMode=$audioOutputMode")
        val headsetConnected = isHeadsetConnected()
        // 이어폰 전용 모드일 때 이어폰이 연결되어 있지 않으면 무조건 return
        if (audioOutputMode == OUTPUT_MODE_HEADSET && !headsetConnected) {
            Log.w(TAG, "🚫 이어폰 전용 모드이나 이어폰이 연결되어 있지 않아 TTS 실행 안함 (BusAlertService)")
            return
        }
        // earphoneOnly 파라미터가 true이면 이어폰 연결 필요
        if (earphoneOnly && !headsetConnected) {
            Log.w(TAG, "🚫 earphoneOnly=true인데 이어폰이 연결되어 있지 않아 TTS 실행 안함 (BusAlertService)")
            return
        }
        Log.d(TAG, "🔊 speakTts called: text='$text', isTtsInitialized=$isTtsInitialized, ttsEngine=${ttsEngine != null}, useTextToSpeech=$useTextToSpeech")
        if (!isTtsInitialized || ttsEngine == null) {
            Log.e(TAG, "🔊 TTS speak failed - engine not ready")
            initializeTts()
            return
        }
        if (!useTextToSpeech) {
            Log.d(TAG, "🔊 TTS speak skipped - disabled in settings.")
            return
        }
        if (text.isBlank()) {
            Log.w(TAG, "🔊 TTS speak skipped - empty text")
            return
        }
        serviceScope.launch {
            try {
                // 발화 직전에 이어폰 연결 상태 한 번 더 재확인
                val latestHeadsetConnected = isHeadsetConnected()
                if (audioOutputMode == OUTPUT_MODE_HEADSET && !latestHeadsetConnected) {
                    Log.w(TAG, "🚫 [발화 직전 최종방어] 이어폰 전용 모드이나 이어폰이 연결되어 있지 않아 TTS 실행 안함")
                    return@launch
                }

                val useSpeaker = when (audioOutputMode) {
                    OUTPUT_MODE_SPEAKER -> true
                    OUTPUT_MODE_HEADSET -> false // 이어폰 전용 모드는 절대 스피커 사용 안함
                    OUTPUT_MODE_AUTO -> !latestHeadsetConnected
                    else -> !latestHeadsetConnected
                }

                // 이어폰 전용 모드에서는 STREAM_MUSIC 사용, 스피커 모드에서는 STREAM_ALARM 사용
                val streamType = if (audioOutputMode == OUTPUT_MODE_HEADSET) {
                    android.media.AudioManager.STREAM_MUSIC // 이어폰 모드는 무조건 MUSIC
                } else if (useSpeaker) {
                    android.media.AudioManager.STREAM_ALARM // 스피커 사용 시 ALARM
                } else {
                    android.media.AudioManager.STREAM_MUSIC // 그 외에는 MUSIC
                }

                Log.d(TAG, "🔊 Preparing TTS: Stream=${if (streamType == android.media.AudioManager.STREAM_ALARM) "ALARM" else "MUSIC"}, Speaker=$useSpeaker, Mode=$audioOutputMode")

                val utteranceId = "tts_${System.currentTimeMillis()}"
                val params = android.os.Bundle().apply {
                    putString(android.speech.tts.TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
                    putInt(android.speech.tts.TextToSpeech.Engine.KEY_PARAM_STREAM, streamType)
                    putFloat(android.speech.tts.TextToSpeech.Engine.KEY_PARAM_VOLUME, ttsVolume)
                }

                // 스피커폰 상태 명확히 세팅
                audioManager?.isSpeakerphoneOn = useSpeaker

                val focusResult = requestAudioFocus(useSpeaker)
                Log.d(TAG, "🔊 Audio focus request result: $focusResult")

                // 발화 직전 이어폰 연결 한 번 더 확인
                if (audioOutputMode == OUTPUT_MODE_HEADSET && !isHeadsetConnected()) {
                    Log.w(TAG, "🚫 [발화 직전 최종방어-재확인] 이어폰 전용 모드이나 이어폰이 연결되어 있지 않아 TTS 발화 취소")
                    audioManager?.abandonAudioFocus(audioFocusListener)
                    return@launch
                }

                if (focusResult == android.media.AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                    Log.d(TAG, "🔊 Audio focus granted. Speaking.")
                    ttsEngine?.setOnUtteranceProgressListener(createTtsListener())
                    Log.i(TAG, "TTS 발화: $text, outputMode=$audioOutputMode, headset=${isHeadsetConnected()}, utteranceId=$utteranceId")
                    ttsEngine?.speak(text, android.speech.tts.TextToSpeech.QUEUE_FLUSH, params, utteranceId)
                } else {
                    Log.e(TAG, "🔊 Audio focus request failed ($focusResult). Speak cancelled.")
                    audioManager?.abandonAudioFocus(audioFocusListener)
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ TTS speak error: ${e.message}", e)
                audioManager?.abandonAudioFocus(audioFocusListener)
            }
        }
    }

    private fun requestAudioFocus(useSpeaker: Boolean): Int {
        if (audioManager == null) return AudioManager.AUDIOFOCUS_REQUEST_FAILED
        val streamType = if (useSpeaker) AudioManager.STREAM_ALARM else AudioManager.STREAM_MUSIC
        val focusResult: Int
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val usage = if (useSpeaker) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY
            val audioAttributes = AudioAttributes.Builder()
                .setUsage(usage)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
            audioFocusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
                .setAudioAttributes(audioAttributes)
                .setAcceptsDelayedFocusGain(true)
                .setOnAudioFocusChangeListener(audioFocusListener)
                .build()
            focusResult = audioManager?.requestAudioFocus(audioFocusRequest!!) ?: AudioManager.AUDIOFOCUS_REQUEST_FAILED
        } else {
            @Suppress("DEPRECATION")
            focusResult = audioManager?.requestAudioFocus(
                audioFocusListener, streamType, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
            ) ?: AudioManager.AUDIOFOCUS_REQUEST_FAILED
        }
        return focusResult
    }

    fun setTtsVolume(volume: Double) {
        serviceScope.launch {
            try {
                ttsVolume = volume.toFloat().coerceIn(0f, 1f)
                val prefs = applicationContext.getSharedPreferences("AppSettings", Context.MODE_PRIVATE)
                prefs.edit().putFloat(PREF_TTS_VOLUME, ttsVolume).apply()
                Log.d(TAG, "TTS Volume set to: ${ttsVolume * 100}%")
            } catch (e: Exception) {
                Log.e(TAG, "Error setting TTS volume: ${e.message}", e)
            }
        }
    }

    fun cancelOngoingTracking() {
        Log.d(TAG, "cancelOngoingTracking called (ID: $ONGOING_NOTIFICATION_ID)")
        try {
            // 1. 먼저 모든 추적 작업 중지
            monitoringJobs.values.forEach { it.cancel() }
            monitoringJobs.clear()
            activeTrackings.clear()
            monitoredRoutes.clear()

            // 2. 포그라운드 서비스 중지
            if (isInForeground) {
                Log.d(TAG, "Service is in foreground, calling stopForeground(STOP_FOREGROUND_REMOVE).")
                stopForeground(STOP_FOREGROUND_REMOVE)
                isInForeground = false
            }

            // 3. 알림 직접 취소 (모든 알림 취소)
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll() // 모든 알림 취소
            Log.d(TAG, "All notifications cancelled via NotificationManager.")

            // 4. NotificationManagerCompat을 통한 취소 (백업)
            try {
                NotificationManagerCompat.from(this).cancelAll() // 모든 알림 취소
                Log.d(TAG, "All notifications cancelled via NotificationManagerCompat (backup).")
            } catch (e: Exception) {
                Log.e(TAG, "NotificationManagerCompat 취소 오류: ${e.message}", e)
            }

            // 5. Flutter 측에 알림 취소 이벤트 전송 시도
            try {
                val context = applicationContext
                val intent = Intent("com.example.daegu_bus_app.ALL_TRACKING_CANCELLED")
                context.sendBroadcast(intent)
                Log.d(TAG, "모든 추적 취소 이벤트 브로드캐스트 전송")
            } catch (e: Exception) {
                Log.e(TAG, "알림 취소 이벤트 전송 오류: ${e.message}", e)
            }

            // 6. 서비스 중지 요청
            stopSelf()
            Log.d(TAG, "Service stop requested from cancelOngoingTracking.")
        } catch (e: Exception) {
            Log.e(TAG, "🚌 Ongoing notification cancellation/Foreground stop error: ${e.message}", e)
            try {
                // 오류 발생 시 강제 중지 시도
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancelAll()
                stopForeground(STOP_FOREGROUND_REMOVE)
                isInForeground = false
                stopSelf()
                Log.d(TAG, "Force stop attempted after error.")
            } catch (ex: Exception) {
                Log.e(TAG, "Additional error when trying to stop service: ${ex.message}", ex)
            }
        }
    }

    fun stopTracking() {
        serviceScope.launch {
            Log.i(TAG, "--- BusAlertService stopTracking Starting ---")
            try {
                // 1. 모든 추적 작업 중지
                monitoringJobs.values.forEach { it.cancel() }
                monitoringJobs.clear()
                stopMonitoringTimer()
                stopTtsTracking(forceStop = true)
                monitoredRoutes.clear()
                cachedBusInfo.clear()
                arrivingSoonNotified.clear()
                activeTrackings.clear() // 추가: 활성 추적 목록 초기화
                Log.d(TAG, "Monitoring, jobs, and related caches/flags reset.")

                // 2. 모든 알림 직접 취소
                try {
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancelAll()
                    Log.i(TAG, "모든 알림 직접 취소 완료 (stopTracking)")
                } catch (e: Exception) {
                    Log.e(TAG, "알림 취소 오류: ${e.message}")
                }

                // 3. 포그라운드 서비스 중지
                if (isInForeground) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    isInForeground = false
                    Log.d(TAG, "Foreground service stopped explicitly.")
                }

                // 4. Flutter 측에 알림 취소 이벤트 전송 시도
                try {
                    val context = applicationContext
                    val intent = Intent("com.example.daegu_bus_app.ALL_TRACKING_CANCELLED")
                    context.sendBroadcast(intent)
                    Log.d(TAG, "모든 추적 취소 이벤트 브로드캐스트 전송 (stopTracking)")
                } catch (e: Exception) {
                    Log.e(TAG, "알림 취소 이벤트 전송 오류: ${e.message}")
                }

                // 5. 서비스 중지 요청
                Log.i("BusAlertService", "All tasks stopped. Service stop requested.")
                stopSelf()
            } catch (e: Exception) {
                Log.e(TAG, "Error in stopTracking: ${e.message}", e)

                // 오류 발생 시 강제 중지 시도
                if (isInForeground) {
                    try {
                        stopForeground(STOP_FOREGROUND_REMOVE)
                        isInForeground = false
                        Log.d(TAG, "Foreground service stopped after error.")
                    } catch (ex: Exception) {
                        Log.e(TAG, "Error stopping foreground service: ${ex.message}", ex)
                    }
                }

                // 모든 알림 강제 취소 시도
                try {
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancelAll()
                    Log.i(TAG, "모든 알림 강제 취소 완료 (오류 복구)")
                } catch (ex: Exception) {
                    Log.e(TAG, "모든 알림 강제 취소 오류: ${ex.message}", ex)
                }

                stopSelf()
            } finally {
                Log.i(TAG, "--- BusAlertService stopTracking Finished ---")
            }
        }
    }

    fun cancelNotification(id: Int) {
        Log.d(TAG, "Cancel requested for notification ID: $id")
        notificationHandler.cancelNotification(id)
    }

    fun cancelAllNotifications() {
        Log.i(TAG, "Cancel all notifications requested.")
        notificationHandler.cancelAllNotifications()
        cancelOngoingTracking()
    }

    private fun stopTrackingIfIdle() {
        serviceScope.launch {
            checkAndStopServiceIfNeeded()
        }
    }

    private fun sendCancellationBroadcast(busNo: String, routeId: String, stationName: String) {
        try {
            val intent = Intent("com.example.daegu_bus_app.NOTIFICATION_CANCELLED").apply {
                putExtra("busNo", busNo)
                putExtra("routeId", routeId)
                putExtra("stationName", stationName)
                putExtra("source", "native_service")
                flags = Intent.FLAG_INCLUDE_STOPPED_PACKAGES
            }
            sendBroadcast(intent)
            Log.d(TAG, "알림 취소 이벤트 브로드캐스트 전송: $busNo, $routeId, $stationName")

            // Flutter 메서드 채널을 통해 직접 이벤트 전송 시도
            try {
                val context = applicationContext
                if (context is MainActivity) {
                    context._methodChannel?.invokeMethod("onAlarmCanceledFromNotification", mapOf(
                        "busNo" to busNo,
                        "routeId" to routeId,
                        "stationName" to stationName
                    ))
                    Log.d(TAG, "Flutter 메서드 채널로 알림 취소 이벤트 직접 전송 완료")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Flutter 메서드 채널 전송 오류: ${e.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "알림 취소 이벤트 전송 오류: ${e.message}")
        }
    }

    private fun sendAllCancellationBroadcast() {
        try {
            val intent = Intent("com.example.daegu_bus_app.ALL_TRACKING_CANCELLED").apply {
                flags = Intent.FLAG_INCLUDE_STOPPED_PACKAGES
            }
            sendBroadcast(intent)
            Log.d(TAG, "모든 추적 취소 이벤트 브로드캐스트 전송")

            // Flutter 메서드 채널을 통해 직접 이벤트 전송 시도
            try {
                val context = applicationContext
                if (context is MainActivity) {
                    context._methodChannel?.invokeMethod("onAllAlarmsCanceled", null)
                    Log.d(TAG, "Flutter 메서드 채널로 모든 알람 취소 이벤트 직접 전송 완료")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Flutter 메서드 채널 전송 오류: ${e.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "모든 알람 취소 이벤트 전송 오류: ${e.message}")
        }
    }

    private fun checkAndStopService() {
        if (activeTrackings.isEmpty() && monitoredRoutes.isEmpty() && !isTtsTrackingActive) {
            Log.i(TAG, "Service idle. Requesting stop.")
            Handler(Looper.getMainLooper()).postDelayed({
                if (activeTrackings.isEmpty() && monitoredRoutes.isEmpty() && !isTtsTrackingActive) {
                    stopSelf()
                    Log.i(TAG, "Service stopped after delay check.")
                }
            }, 1000) // 1초 후 다시 확인
        }
    }

    private val hasNotifiedTts = HashSet<String>()
    private val hasNotifiedArrival = HashSet<String>()

    private fun checkArrivalAndNotify(trackingInfo: TrackingInfo, busInfo: BusInfo) {
        // Check if the bus is out of service
        if (busInfo.isOutOfService || busInfo.estimatedTime == "운행종료") {
            Log.d(TAG, "버스 운행종료 상태입니다. 알림을 표시하지 않습니다: ${trackingInfo.busNo}번")
            return
        }

        // Log current time but don't restrict notifications
        val currentHour = Calendar.getInstance().get(Calendar.HOUR_OF_DAY)
        if (currentHour < 5 || currentHour >= 23) {
            Log.w(TAG, "⚠️ 현재 버스 운행 시간이 아닙니다 (현재 시간: ${currentHour}시). 테스트 목적으로 계속 진행합니다.")
        }

        val remainingMinutes = when {
            busInfo.estimatedTime == "곧 도착" -> 0
            busInfo.estimatedTime == "운행종료" -> -1
            busInfo.estimatedTime.contains("분") -> {
                busInfo.estimatedTime.filter { it.isDigit() }.toIntOrNull() ?: -1
            }
            busInfo.estimatedTime == "전" -> 0
            busInfo.estimatedTime == "도착" -> 0
            busInfo.estimatedTime == "출발" -> 0
            busInfo.estimatedTime.isBlank() || busInfo.estimatedTime == "정보 없음" -> -1
            else -> -1 // 기타 예상치 못한 값은 -1(정보 없음)로 처리
        }

        if (remainingMinutes >= 0 && remainingMinutes <= ARRIVAL_THRESHOLD_MINUTES) {
            if (useTextToSpeech && !hasNotifiedTts.contains(trackingInfo.routeId)) {
                // TTS 시스템을 통한 발화 시도
                try {
                    startTTSServiceSpeak(
                        busNo = trackingInfo.busNo,
                        stationName = trackingInfo.stationName,
                        routeId = trackingInfo.routeId,
                        stationId = trackingInfo.stationId,
                        remainingMinutes = 0, // 곧 도착 상태
                        currentStation = busInfo.currentStation
                    )
                    hasNotifiedTts.add(trackingInfo.routeId)
                    Log.d(TAG, "📢 TTS 발화 시도 성공: ${trackingInfo.busNo}번 버스, ${trackingInfo.stationName}")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ TTS 발화 시도 오류: ${e.message}", e)

                    // TTSService 실패 시 백업으로 내부 TTS 시도
                    val message = "${trackingInfo.busNo}번 버스가 ${trackingInfo.stationName} 정류장에 곧 도착합니다."
                    speakTts(message)
                    hasNotifiedTts.add(trackingInfo.routeId)
                }
            }

            // 도착 알림
            if (!hasNotifiedArrival.contains(trackingInfo.routeId)) {
                notificationHandler.sendAlertNotification(
                    trackingInfo.routeId,
                    trackingInfo.busNo,
                    trackingInfo.stationName
                )
                hasNotifiedArrival.add(trackingInfo.routeId)
                Log.d(TAG, "📳 도착 알림 전송: ${trackingInfo.busNo}번, ${trackingInfo.stationName}")
            }
        }
    }

    fun updateTrackingInfoFromFlutter(
        routeId: String,
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String
    ) {
        Log.d(TAG, "🔄 updateTrackingInfoFromFlutter 호출: $busNo, $stationName, ${remainingMinutes}분, 현재 위치: $currentStation")

        try {
            // 1. 추적 정보 업데이트 또는 생성
            val info = activeTrackings[routeId] ?: TrackingInfo(
                routeId = routeId,
                stationName = stationName,
                busNo = busNo,
                stationId = ""
            ).also {
                activeTrackings[routeId] = it
                Log.d(TAG, "✅ 새 추적 정보 생성: $busNo, $stationName")
            }

            // 2. 버스 정보 업데이트 (항상 최신 currentStation 반영)
            // Check if the bus is out of service
            val isOutOfService = remainingMinutes < 0 ||
                                (info.lastBusInfo?.isOutOfService == true) ||
                                (currentStation.contains("운행종료"))

            val busInfo = BusInfo(
                currentStation = currentStation,
                estimatedTime = if (isOutOfService) "운행종료" else if (remainingMinutes <= 0) "곧 도착" else "${remainingMinutes}분",
                remainingStops = info.lastBusInfo?.remainingStops ?: "0",
                busNumber = busNo,
                isLowFloor = info.lastBusInfo?.isLowFloor ?: false,
                isOutOfService = isOutOfService
            )
            info.lastBusInfo = busInfo
            info.lastUpdateTime = System.currentTimeMillis()

            Log.d(TAG, "✅ 버스 정보 업데이트: $busNo, ${busInfo.estimatedTime}, 현재 위치: ${busInfo.currentStation}")

            // 3. 알림 즉시 업데이트
            updateForegroundNotification()
            showOngoingBusTracking(
                busNo = busNo,
                stationName = stationName,
                remainingMinutes = remainingMinutes,
                currentStation = currentStation, // 최신 값으로 무조건 덮어쓰기
                isUpdate = true,
                notificationId = ONGOING_NOTIFICATION_ID,
                allBusesSummary = null,
                routeId = routeId
            )

            // 4. 메인 스레드에서 알림 강제 업데이트 (추가)
            Handler(Looper.getMainLooper()).post {
                try {
                    val notification = notificationHandler.buildOngoingNotification(activeTrackings)
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.notify(ONGOING_NOTIFICATION_ID, notification)
                    Log.d(TAG, "✅ 메인 스레드에서 알림 강제 업데이트 완료: ${System.currentTimeMillis()}")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 메인 스레드 알림 업데이트 오류: ${e.message}", e)
                }
            }

            // 5. 1초 후 다시 한번 업데이트 (지연 백업)
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    val notification = notificationHandler.buildOngoingNotification(activeTrackings)
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.notify(ONGOING_NOTIFICATION_ID, notification)
                    Log.d(TAG, "✅ 지연 알림 업데이트 완료: ${System.currentTimeMillis()}")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 지연 알림 업데이트 오류: ${e.message}", e)
                }
            }, 1000)

            Log.d(TAG, "✅ updateTrackingInfoFromFlutter 완료: $busNo, ${remainingMinutes}분")
        } catch (e: Exception) {
            Log.e(TAG, "❌ updateTrackingInfoFromFlutter 오류: ${e.message}", e)
            updateForegroundNotification() // 오류 발생 시에도 알림 업데이트 시도
        }
    }

    /**
     * 버스 추적 알림을 업데이트하는 메서드 (MainActivity에서 직접 호출)
     */
    fun updateTrackingNotification(
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String,
        routeId: String,
        stationId: String? = null,
        wincId: String? = null
    ) {
        // stationId 보정
        var effectiveStationId = stationId ?: ""
        if (effectiveStationId.isBlank()) {
            serviceScope.launch {
                val fixedStationId = resolveStationIdIfNeeded(routeId, stationName, "", wincId)
                if (fixedStationId.isNotBlank()) {
                    updateTrackingNotification(
                        busNo = busNo,
                        stationName = stationName,
                        remainingMinutes = remainingMinutes,
                        currentStation = currentStation,
                        routeId = routeId,
                        stationId = fixedStationId,
                        wincId = wincId
                    )
                } else {
                    Log.e(TAG, "stationId 보정 실패. 추적 알림 갱신 불가: routeId=$routeId, busNo=$busNo, stationName=$stationName")
                }
            }
            return
        }
        Log.d(TAG, "🔄 updateTrackingNotification 호출: $busNo, $stationName, $remainingMinutes, $currentStation, $routeId")
        try {
            // 1. 추적 정보 업데이트 또는 생성
            val info = activeTrackings[routeId] ?: TrackingInfo(
                routeId = routeId,
                stationName = stationName,
                busNo = busNo,
                stationId = ""
            ).also {
                activeTrackings[routeId] = it
                Log.d(TAG, "✅ 새 추적 정보 생성: $busNo, $stationName")
            }

            // 2. 버스 정보 업데이트
            // Check if the bus is out of service
            val isOutOfService = remainingMinutes < 0 ||
                                (info.lastBusInfo?.isOutOfService == true) ||
                                (currentStation.contains("운행종료"))

            val busInfo = BusInfo(
                currentStation = currentStation,
                estimatedTime = if (isOutOfService) "운행종료" else if (remainingMinutes <= 0) "곧 도착" else "${remainingMinutes}분",
                remainingStops = info.lastBusInfo?.remainingStops ?: "0",
                busNumber = busNo,
                isLowFloor = info.lastBusInfo?.isLowFloor ?: false,
                isOutOfService = isOutOfService
            )
            info.lastBusInfo = busInfo
            info.lastUpdateTime = System.currentTimeMillis()

            Log.d(TAG, "✅ 버스 정보 업데이트: $busNo, ${busInfo.estimatedTime}, 현재 위치: ${busInfo.currentStation}")

            // 3. 알림 업데이트 (여러 방법 시도)
            // 3.1. showOngoingBusTracking 호출
            showOngoingBusTracking(
                busNo = busNo,
                stationName = stationName,
                remainingMinutes = remainingMinutes,
                currentStation = currentStation,
                isUpdate = true,
                notificationId = ONGOING_NOTIFICATION_ID,
                allBusesSummary = null,
                routeId = routeId
            )

            // 3.2. 백업 방법으로 알림 업데이트
            updateForegroundNotification()

            // 3.3. 메인 스레드에서 알림 강제 업데이트 (추가 백업)
            Handler(Looper.getMainLooper()).post {
                try {
                    val notification = notificationHandler.buildOngoingNotification(activeTrackings)
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.notify(ONGOING_NOTIFICATION_ID, notification)
                    Log.d(TAG, "✅ 메인 스레드에서 알림 강제 업데이트 완료: ${System.currentTimeMillis()}")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 메인 스레드 알림 업데이트 오류: ${e.message}", e)
                }
            }

            // 3.4. 1초 후 다시 한번 업데이트 (지연 백업)
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    val notification = notificationHandler.buildOngoingNotification(activeTrackings)
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.notify(ONGOING_NOTIFICATION_ID, notification)
                    Log.d(TAG, "✅ 지연 알림 업데이트 완료: ${System.currentTimeMillis()}")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 지연 알림 업데이트 오류: ${e.message}", e)
                }
            }, 1000)

            Log.d(TAG, "✅ 버스 추적 알림 업데이트 완료: $busNo, ${remainingMinutes}분, 현재 위치: $currentStation")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 버스 추적 알림 업데이트 오류: ${e.message}", e)
            // 오류 발생 시에도 알림 업데이트 시도
            updateForegroundNotification()
        }
    }

    // [ADD] Stop all tracking jobs and clean up everything (used for ACTION_STOP_TRACKING etc)
    private fun stopAllTracking() {
        serviceScope.launch {
            Log.i(TAG, "--- stopAllTracking called ---")
            try {
                monitoringJobs.values.forEach { it.cancel() }
                monitoringJobs.clear()
                stopMonitoringTimer()
                stopTtsTracking(forceStop = true)
                monitoredRoutes.clear()
                cachedBusInfo.clear()
                arrivingSoonNotified.clear()
                activeTrackings.clear()
                Log.d(TAG, "All tracking jobs and caches cleared.");
                if (isInForeground) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    isInForeground = false
                }
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancelAll()
                Log.d(TAG, "All notifications cancelled (stopAllTracking)");
                stopSelf()
            } catch (e: Exception) {
                Log.e(TAG, "Error in stopAllTracking: ${e.message}", e)
            }
        }
    }

    // [ADD] Stop tracking for a specific route (optionally cancel notification)
    fun stopTrackingForRoute(routeId: String, stationId: String? = null, busNo: String? = null, cancelNotification: Boolean = false) {
        serviceScope.launch {
            Log.i(TAG, "--- stopTrackingForRoute called: routeId=$routeId, stationId=$stationId, busNo=$busNo, cancelNotification=$cancelNotification ---")
            try {
                monitoringJobs[routeId]?.cancel()
                monitoringJobs.remove(routeId)
                activeTrackings.remove(routeId)
                monitoredRoutes.remove(routeId)
                if (cancelNotification) {
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancel(ONGOING_NOTIFICATION_ID)
                    Log.d(TAG, "Notification cancelled for route $routeId");
                }
                if (activeTrackings.isEmpty()) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    isInForeground = false
                    stopSelf()
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error in stopTrackingForRoute: ${e.message}", e)
            }
        }
    }

    // [ADD] Update the foreground notification with the latest tracking info
    private fun updateForegroundNotification() {
        try {
            val notification = notificationHandler.buildOngoingNotification(activeTrackings)
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(ONGOING_NOTIFICATION_ID, notification)
            Log.d(TAG, "Foreground notification updated (updateForegroundNotification)");
        } catch (e: Exception) {
            Log.e(TAG, "Error updating foreground notification: ${e.message}", e)
        }
    }

    // [ADD] Stop the monitoring timer if running
    private fun stopMonitoringTimer() {
        try {
            monitoringTimer?.cancel()
            monitoringTimer = null
            Log.d(TAG, "Monitoring timer stopped (stopMonitoringTimer)")
        } catch (e: Exception) {
            Log.e(TAG, "Error stopping monitoring timer: ${e.message}", e)
        }
    }

    // [ADD] Stop TTS tracking (set isTtsTrackingActive to false and clean up)
    fun stopTtsTracking(forceStop: Boolean = false) {
        isTtsTrackingActive = false
        // If there are any TTS-related jobs/handlers, stop them here (expand as needed)
        Log.d(TAG, "TTS tracking stopped (stopTtsTracking), forceStop=$forceStop")
    }

    // [ADD] Show a notification for bus arriving soon
    fun showBusArrivingSoon(busNo: String, stationName: String, currentStation: String?) {
        try {
            val notification = notificationHandler.buildArrivingSoonNotification(busNo, stationName, currentStation)
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NotificationHandler.ARRIVING_SOON_NOTIFICATION_ID, notification)
            Log.d(TAG, "Arriving soon notification shown: $busNo, $stationName, $currentStation")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing arriving soon notification: ${e.message}", e)
        }
    }

    // [ADD] Show a generic ongoing notification (for compatibility)
    fun showNotification() {
        try {
            val notification = notificationHandler.buildOngoingNotification(activeTrackings)
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(NotificationHandler.ONGOING_NOTIFICATION_ID, notification)
            Log.d(TAG, "Ongoing notification shown (showNotification)")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing ongoing notification: ${e.message}", e)
        }
    }

    // [ADD] Overloaded showNotification to match MainActivity call
    fun showNotification(
        id: Int,
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String?
    ) {
        try {
            val notification = notificationHandler.buildNotification(
                id = id,
                busNo = busNo,
                stationName = stationName,
                remainingMinutes = remainingMinutes,
                currentStation = currentStation
            )
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(id, notification)
            Log.d(TAG, "Ongoing notification shown (showNotification overload): $busNo, $stationName, $remainingMinutes, $currentStation")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing ongoing notification (overload): ${e.message}", e)
        }
    }
}

class NotificationDismissReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val notificationId = intent.getIntExtra("NOTIFICATION_ID", -1)
        if (notificationId != -1) {
            Log.d("NotificationDismiss", "🔔 Notification dismissed (ID: $notificationId)")
        }
    }
}

fun getNotificationChannels(context: Context): List<NotificationChannel>? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager?
        notificationManager?.notificationChannels
    } else {
        null
    }
}

fun StationArrivalOutput.toMap(): Map<String, Any?> {
    return mapOf(
        "name" to name, "sub" to sub, "id" to id, "forward" to forward,
        "bus" to bus.map { it.toMap() }
    )
}

fun RouteStation.toMap(): Map<String, Any?> {
    return mapOf(
        "stationId" to stationId, "stationName" to stationName,
        "sequenceNo" to sequenceNo, "direction" to direction
    )
}

fun BusInfo.toMap(): Map<String, Any?> {
    val isLowFloor = false
    val isOutOfService = estimatedTime == "운행종료"
    val remainingMinutes = when {
        estimatedTime == "곧 도착" -> 0
        estimatedTime == "운행종료" -> -1
        estimatedTime.contains("분") -> estimatedTime.filter { it.isDigit() }.toIntOrNull() ?: Int.MAX_VALUE
        else -> Int.MAX_VALUE
    }
    return mapOf(
        "busNumber" to busNumber, "estimatedTime" to estimatedTime,
        "currentStation" to currentStation, "isLowFloor" to isLowFloor,
        "isOutOfService" to isOutOfService, "remainingMinutes" to remainingMinutes
    )
}

fun StationArrivalOutput.BusInfo.toMap(): Map<String, Any?> {
    return mapOf(
        "busNumber" to busNumber, "currentStation" to currentStation,
        "remainingStations" to remainingStations, "estimatedTime" to estimatedTime
    )
}