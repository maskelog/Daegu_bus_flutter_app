package com.example.daegu_bus_app

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
import kotlin.collections.HashMap
import kotlin.math.max
import kotlin.math.roundToInt
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.os.Bundle
import android.media.AudioAttributes
import android.media.AudioFocusRequest

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
        const val OUTPUT_MODE_AUTO = 0
        const val OUTPUT_MODE_SPEAKER = 1
        const val OUTPUT_MODE_HEADSET = 2

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
    private val cachedBusInfo = HashMap<String, com.example.daegu_bus_app.BusInfo>()
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
                val stationId = intent.getStringExtra("stationId")

                if (routeId == null || busNo.isBlank() || stationName.isBlank()) {
                    Log.e(TAG, "$intent.action Aborted: Missing required info")
                    stopTrackingIfIdle()
                    return START_NOT_STICKY
                }

                if (intent.action == ACTION_START_TRACKING_FOREGROUND && stationId != null) {
                    addMonitoredRoute(routeId, stationId, stationName)
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
        val stationId: String,
        val stationName: String,
        val busNo: String,
        var lastBusInfo: com.example.daegu_bus_app.BusInfo? = null,
        var lastNotifiedMinutes: Int = Int.MAX_VALUE,
        var consecutiveErrors: Int = 0
    )

    private fun startTracking(routeId: String, stationId: String, stationName: String, busNo: String) {
        if (monitoringJobs.containsKey(routeId)) {
            Log.d(TAG, "Tracking already active for route $routeId")
            return
        }

        Log.i(TAG, "Starting tracking for route $routeId ($busNo) at station $stationName ($stationId)")
        val trackingInfo = TrackingInfo(routeId, stationId, stationName, busNo)
        activeTrackings[routeId] = trackingInfo

        monitoringJobs[routeId] = serviceScope.launch {
            try {
                while (isActive) {
                    try {
                        val arrivals = busApiService.getBusArrivals(stationId, routeId)
                        if (!activeTrackings.containsKey(routeId)) {
                            Log.w(TAG, "Tracking info for $routeId removed. Stopping loop.")
                            break
                        }
                        val currentInfo = activeTrackings[routeId] ?: break
                        currentInfo.consecutiveErrors = 0

                        val firstBus = arrivals.firstOrNull { !it.isOutOfService }

                        if (firstBus != null) {
                            val remainingMinutes = firstBus.getRemainingMinutes()
                            Log.d(TAG, "Route $routeId ($busNo): Next bus in $remainingMinutes min. At: ${firstBus.currentStation}")
                            currentInfo.lastBusInfo = firstBus

                            if (useTextToSpeech && remainingMinutes <= 1 && currentInfo.lastNotifiedMinutes > 1) {
                                startTTSServiceSpeak(busNo, stationName, routeId, stationId)
                                currentInfo.lastNotifiedMinutes = remainingMinutes
                            } else if (remainingMinutes > 1) {
                                currentInfo.lastNotifiedMinutes = Int.MAX_VALUE
                            }
                            updateForegroundNotification()
                        } else {
                            Log.w(TAG, "No available buses for route $routeId at $stationId.")
                            currentInfo.lastBusInfo = null
                            updateForegroundNotification()
                        }
                        delay(calculateDelay(firstBus?.getRemainingMinutes()))
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
                                stopTrackingForRoute(routeId, cancelNotification = true)
                                break
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
    }

    private fun startTTSServiceSpeak(busNo: String, stationName: String, routeId: String, stationId: String) {
        try {
            val ttsIntent = Intent(this, TTSService::class.java).apply {
                action = "REPEAT_TTS_ALERT"
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
            }
            startService(ttsIntent)
            Log.d(TAG, "Requested TTSService to speak for $busNo")
        } catch (e: Exception) {
            Log.e(TAG, "Error starting TTSService for speaking: ${e.message}", e)
        }
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
                    if (status == TextToSpeech.SUCCESS) {
                        val result = ttsEngine?.setLanguage(Locale.KOREAN)
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

    fun showOngoingBusTracking(
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String?,
        isUpdate: Boolean,
        notificationId: Int,
        allBusesSummary: String?,
        routeId: String?
    ) {
        Log.d(TAG, "showOngoingBusTracking called: Bus=$busNo, Station=$stationName, currentStation=$currentStation Update=$isUpdate")

        // 유효한 routeId가 없으면 임시 ID 생성
        val effectiveRouteId = routeId ?: "temp_${busNo}_${stationName.hashCode()}"

        // 이미 추적 중인지 확인
        if (!activeTrackings.containsKey(effectiveRouteId)) {
            // 추적 정보 생성 및 추가
            val trackingInfo = TrackingInfo(
                routeId = effectiveRouteId,
                stationId = "",  // 정류장 ID가 없는 경우 빈 문자열 사용
                stationName = stationName,
                busNo = busNo
            )

            // 버스 정보가 있으면 설정
            if (remainingMinutes >= 0) {
                val busInfo = com.example.daegu_bus_app.BusInfo(
                    busNumber = busNo,
                    estimatedTime = if (remainingMinutes <= 0) "곧 도착" else "${remainingMinutes}분",
                    currentStation = currentStation ?: "정보 없음",
                    remainingStops = "0"
                )
                trackingInfo.lastBusInfo = busInfo
            }

            // 추적 목록에 추가
            activeTrackings[effectiveRouteId] = trackingInfo
            Log.d(TAG, "Added bus tracking info: $busNo at $stationName (ID: $effectiveRouteId)")
        } else {
            // 기존 추적 정보 업데이트
            val trackingInfo = activeTrackings[effectiveRouteId]
            if (trackingInfo != null && remainingMinutes >= 0) {
                val busInfo = com.example.daegu_bus_app.BusInfo(
                    busNumber = busNo,
                    estimatedTime = if (remainingMinutes <= 0) "곧 도착" else "${remainingMinutes}분",
                    currentStation = currentStation ?: trackingInfo.lastBusInfo?.currentStation ?: "정보 없음",
                    remainingStops = trackingInfo.lastBusInfo?.remainingStops ?: "0"
                )
                trackingInfo.lastBusInfo = busInfo
                Log.d(TAG, "Updated bus tracking info: $busNo, ${busInfo.estimatedTime}, currentStation: ${busInfo.currentStation}")
            }
        }

        // 포그라운드 알림 업데이트
        updateForegroundNotification()
    }

    fun stopTtsTracking(routeId: String? = null, stationId: String? = null, forceStop: Boolean = false) {
        Log.d(TAG, "Stopping internal TTS tracking for route ${routeId ?: "all"}")
        isTtsTrackingActive = false
        ttsEngine?.stop()
        stopTTSServiceTracking(routeId)
        checkAndStopServiceIfNeeded()
    }

    fun stopTrackingForRoute(routeId: String, stationId: String? = null, busNo: String? = null, cancelNotification: Boolean = true) {
        Log.i(TAG, "Stopping tracking for route $routeId. Cancel notification: $cancelNotification")
        try {
            // 1. 추적 정보 저장 (Flutter에 전송하기 위해)
            val trackingInfo = activeTrackings[routeId]
            val busNumber = busNo ?: trackingInfo?.busNo ?: ""
            val stationName = trackingInfo?.stationName ?: ""

            // 2. 추적 작업 취소
            monitoringJobs[routeId]?.cancel("Tracking stopped for route $routeId")
            monitoringJobs.remove(routeId)

            // 3. 추적 목록에서 제거
            activeTrackings.remove(routeId)
            monitoredRoutes.remove(routeId)

            // 4. TTS 추적 중지
            stopTtsTracking(routeId = routeId, stationId = stationId, forceStop = true)

            // 5. 알림 처리
            if (cancelNotification) {
                if (activeTrackings.isEmpty()) {
                    // 마지막 추적이 취소된 경우 전체 서비스 중지
                    Log.i(TAG, "Last tracking canceled. Stopping service completely.")
                    cancelOngoingTracking()
                } else {
                    // 다른 추적이 남아있는 경우 알림 업데이트
                    updateForegroundNotification()
                }
            }

            // 6. Flutter 측에 알림 취소 이벤트 전송 (브로드캐스트 방식)
            try {
                // 개별 알림 취소 이벤트
                val cancelIntent = Intent("com.example.daegu_bus_app.NOTIFICATION_CANCELLED").apply {
                    putExtra("routeId", routeId)
                    putExtra("busNo", busNumber)
                    putExtra("stationName", stationName)
                    putExtra("source", "native_service")
                }
                applicationContext.sendBroadcast(cancelIntent)
                Log.d(TAG, "알림 취소 이벤트 브로드캐스트 전송: $busNumber, $routeId, $stationName")

                // 모든 추적이 취소된 경우 전체 취소 이벤트도 전송
                if (activeTrackings.isEmpty()) {
                    val allCancelIntent = Intent("com.example.daegu_bus_app.ALL_TRACKING_CANCELLED")
                    applicationContext.sendBroadcast(allCancelIntent)
                    Log.d(TAG, "모든 추적 취소 이벤트 브로드캐스트 전송")
                }

                // 추가: 명시적으로 NotificationManager를 통해 알림 취소
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(ONGOING_NOTIFICATION_ID)
                Log.d(TAG, "알림 직접 취소 완료: ID=$ONGOING_NOTIFICATION_ID")

            } catch (e: Exception) {
                Log.e(TAG, "알림 취소 이벤트 전송 오류: ${e.message}", e)
            }

        } catch (e: Exception) {
            Log.e(TAG, "Error stopping tracking for route $routeId: ${e.message}", e)
            // 오류 발생 시에도 서비스 상태 확인
            if (activeTrackings.isEmpty()) {
                cancelOngoingTracking()
            }
        } finally {
            checkAndStopServiceIfNeeded()
        }
    }

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
            NotificationManagerCompat.from(this).notify(id, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Error showing notification: ${e.message}")
        }
    }

    fun showBusArrivingSoon(
        busNo: String,
        stationName: String,
        currentStation: String?
    ) {
        try {
            val notification = notificationHandler.buildArrivingSoonNotification(
                busNo = busNo,
                stationName = stationName,
                currentStation = currentStation
            )
            NotificationManagerCompat.from(this).notify(
                NotificationHandler.ARRIVING_SOON_NOTIFICATION_ID,
                notification
            )
        } catch (e: Exception) {
            Log.e(TAG, "Error showing arriving soon notification: ${e.message}")
        }
    }

    private fun stopBusMonitoring(routeId: String) {
        Log.d(TAG, "Stopping bus monitoring for route $routeId")
        monitoringJobs[routeId]?.cancel("Bus monitoring stopped for route")
        monitoringJobs.remove(routeId)
        monitoredRoutes.remove(routeId)
        checkAndStopServiceIfNeeded()
        if (activeTrackings.isNotEmpty() || monitoredRoutes.isNotEmpty()) {
            updateForegroundNotification()
        }
    }

    private fun stopMonitoringTimer() {
        Log.d(TAG, "Stopping monitoring timer")
        monitoringTimer?.cancel()
        monitoringTimer = null
    }

    private fun stopAllTracking() {
        Log.i(TAG, "Stopping all tracking.")
        
        // 현재 추적 중인 모든 버스에 대해 취소 이벤트 발송
        activeTrackings.forEach { (routeId, info) ->
            sendCancellationBroadcast(info.busNo, routeId, info.stationName)
        }
        
        // 전체 취소 이벤트 발송
        sendAllCancellationBroadcast()
        
        // 모든 추적 작업과 서비스 중지
        monitoringJobs.values.forEach { it.cancel() }
        monitoringJobs.clear()
        
        // 모니터링 타이머 중지
        stopMonitoringTimer()
        
        // TTS 추적 중지
        stopTtsTracking(forceStop = true)
        
        // 모든 데이터 초기화
        activeTrackings.clear()
        monitoredRoutes.clear()
        cachedBusInfo.clear()
        arrivingSoonNotified.clear()
        
        // 알림 취소
        cancelOngoingTracking()
        
        // 서비스가 유휴 상태인지 확인하고 중지
        checkAndStopService()
    }

    private fun stopInternalTtsTracking(routeId: String) {
        if (routeId == "all") {
            isTtsTrackingActive = false
            ttsEngine?.stop()
            Log.i(TAG, "모든 TTS 추적 중지")
        } else {
            // 해당 노선에 대한 TTS 추적만 중지
            ttsEngine?.stop()
            Log.i(TAG, "노선 $routeId 에 대한 TTS 추적 중지")
            
            // 다른 활성 추적이 없으면 TTS 전체 중지
            if (activeTrackings.isEmpty()) {
                isTtsTrackingActive = false
                ttsEngine?.stop()
                Log.i(TAG, "남은 추적이 없어 TTS 전체 중지")
            }
        }
        
        // TTS 서비스도 중지
        stopTTSServiceTracking(routeId)
        
        // 서비스 상태 확인
        checkAndStopServiceIfNeeded()
    }

    private fun calculateDelay(remainingMinutes: Int?): Long {
        return when {
            remainingMinutes == null -> 30000L
            remainingMinutes <= 1 -> 15000L
            remainingMinutes <= 5 -> 20000L
            else -> 30000L
        }
    }

    private fun updateForegroundNotification() {
        Handler(Looper.getMainLooper()).post {
            try {
                if (activeTrackings.isNotEmpty()) {
                    val notification = notificationHandler.buildOngoingNotification(activeTrackings)
                    if (!isInForeground) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            startForeground(ONGOING_NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
                        } else {
                            @Suppress("DEPRECATION")
                            startForeground(ONGOING_NOTIFICATION_ID, notification)
                        }
                        isInForeground = true
                        Log.d(TAG, "Foreground service started.")
                    } else {
                        NotificationManagerCompat.from(this).notify(ONGOING_NOTIFICATION_ID, notification)
                        Log.d(TAG, "Foreground notification updated.")
                    }
                } else {
                    Log.d(TAG, "No active trackings. Stopping foreground.")
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    isInForeground = false
                }
            } catch (e: SecurityException) {
                Log.e(TAG, "Foreground Service Permission Error: ${e.message}", e)
                stopTracking()
            } catch (e: Exception) {
                Log.e(TAG, "🚨 Error updating/starting foreground service: ${e.message}", e)
                stopTracking()
            }
        }
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

    private fun isHeadsetConnected(): Boolean {
        if (audioManager == null) {
            Log.w(TAG, "AudioManager null in isHeadsetConnected")
            return false
        }
        try {
            val isWired = audioManager?.isWiredHeadsetOn ?: false
            val isA2dp = audioManager?.isBluetoothA2dpOn ?: false
            val isSco = audioManager?.isBluetoothScoOn ?: false
            val isConnected = isWired || isA2dp || isSco
            Log.d(TAG, "🎧 Headset status: Wired=$isWired, A2DP=$isA2dp, SCO=$isSco -> Connected=$isConnected")
            return isConnected
        } catch (e: Exception) {
            Log.e(TAG, "🎧 Error checking headset status: ${e.message}", e)
            return false
        }
    }

    fun speakTts(text: String, earphoneOnly: Boolean = false) {
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
                val useSpeaker = when (audioOutputMode) {
                    OUTPUT_MODE_SPEAKER -> true
                    OUTPUT_MODE_HEADSET -> false
                    OUTPUT_MODE_AUTO -> !isHeadsetConnected()
                    else -> !isHeadsetConnected()
                }
                val streamType = if (useSpeaker) AudioManager.STREAM_ALARM else AudioManager.STREAM_MUSIC
                Log.d(TAG, "🔊 Preparing TTS: Stream=${if(streamType == AudioManager.STREAM_ALARM) "ALARM" else "MUSIC"}, Speaker=$useSpeaker")

                val utteranceId = "tts_${System.currentTimeMillis()}"
                val params = Bundle().apply {
                    putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
                    putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, streamType)
                    putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, ttsVolume)
                }

                val focusResult = requestAudioFocus(useSpeaker)

                if (focusResult == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                    Log.d(TAG, "🔊 Audio focus granted. Speaking.")
                    ttsEngine?.setOnUtteranceProgressListener(createTtsListener())
                    ttsEngine?.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
                } else {
                    Log.e(TAG, "🔊 Audio focus request failed ($focusResult). Speak cancelled.")
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
                    Log.e(TAG, "알림 취소 오류: ${e.message}", e)
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
                    Log.e(TAG, "알림 취소 이벤트 전송 오류: ${e.message}", e)
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

fun com.example.daegu_bus_app.BusInfo.toMap(): Map<String, Any?> {
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