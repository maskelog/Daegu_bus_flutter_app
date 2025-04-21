package com.example.daegu_bus_app

import io.flutter.plugin.common.MethodChannel
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.graphics.Color
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import java.util.Timer
import java.util.TimerTask
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.media.AudioManager.OnAudioFocusChangeListener
import android.media.AudioFocusRequest
import android.os.Bundle
import android.app.Notification
import java.util.Locale
import java.text.SimpleDateFormat
import java.util.Date
import org.json.JSONArray
import org.json.JSONObject
import io.flutter.embedding.engine.FlutterEngine
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.min

class BusAlertService : Service() {
    companion object {
        private const val TAG = "BusAlertService"
        private const val CHANNEL_BUS_ALERTS = "bus_alerts"
        private const val CHANNEL_BUS_ONGOING = "bus_ongoing"
        const val ONGOING_NOTIFICATION_ID = 10000

        // 설정 관련 상수
        private const val PREF_ALARM_SOUND = "alarm_sound_preference"
        private const val PREF_ALARM_SOUND_FILENAME = "alarm_sound_filename"
        private const val PREF_ALARM_USE_TTS = "alarm_use_tts"
        private const val DEFAULT_ALARM_SOUND = "alarm_sound"
        private const val PREF_SPEAKER_MODE = "speaker_mode"
        private const val PREF_NOTIFICATION_DISPLAY_MODE_KEY = "notificationDisplayMode"
        private const val PREF_TTS_VOLUME = "tts_volume"

        // 오디오 출력 모드 상수
        private const val OUTPUT_MODE_HEADSET = 0
        private const val OUTPUT_MODE_SPEAKER = 1
        private const val OUTPUT_MODE_AUTO = 2

        // 알림 표시 모드 상수
        private const val DISPLAY_MODE_ALARMED_ONLY = 0
        private const val DISPLAY_MODE_ALL_BUSES = 1

        @Volatile
        private var instance: BusAlertService? = null

        fun getInstance(context: Context): BusAlertService {
            return instance ?: synchronized(this) {
                instance ?: BusAlertService().also {
                    instance = it
                }
            }
        }

        const val ACTION_START_TRACKING_FOREGROUND = "com.example.daegu_bus_app.action.START_TRACKING_FOREGROUND"
        const val ACTION_UPDATE_TRACKING = "com.example.daegu_bus_app.action.UPDATE_TRACKING"
        const val ACTION_STOP_BUS_ALERT_TRACKING = "com.example.daegu_bus_app.action.STOP_BUS_ALERT_TRACKING"
    }

    // 서비스 상태 및 설정
    private var _methodChannel: MethodChannel? = null
    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    // 서비스 컨텍스트 저장
    private var mApplicationContext: Context? = null

    // 컨텍스트 가져오기 함수
    private fun getAppContext(): Context {
        return mApplicationContext ?: this
    }
    private lateinit var busApiService: BusApiService
    private var monitoringJob: Job? = null
    private val monitoredRoutes = ConcurrentHashMap<String, Pair<String, String>>()
    private var timer = Timer()
    private var ttsJob: Job? = null
    private var ttsEngine: TextToSpeech? = null
    private var isTtsInitialized = false
    private var isTtsTrackingActive = false
    private var isInForeground = false // Track foreground state - Correctly declared

    // Settings (loaded in initialize)
    private var currentAlarmSound = DEFAULT_ALARM_SOUND
    private var useTextToSpeech = false
    private var audioOutputMode = OUTPUT_MODE_AUTO
    private var notificationDisplayMode = DISPLAY_MODE_ALARMED_ONLY
    private var ttsVolume: Float = 1.0f
    private var audioManager: AudioManager? = null

    val isInTrackingMode: Boolean
        get() = monitoredRoutes.isNotEmpty()

    private val cachedBusInfo = ConcurrentHashMap<String, BusInfo>()
    private val arrivingSoonNotified = ConcurrentHashMap.newKeySet<String>()

    data class BusInfo(
        val busNumber: String,
        val routeId: String,
        val estimatedTime: String,
        val currentStation: String?,
        val remainingStations: String,
        var lastUpdateTime: Long? = null
    ) {
         fun getRemainingMinutes(): Int {
             return when {
                 estimatedTime == "곧 도착" -> 0
                 estimatedTime == "운행종료" -> -1
                 estimatedTime.contains("분") -> estimatedTime.filter { it.isDigit() }.toIntOrNull() ?: -1
                 else -> -1
             }
         }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "🔔 BusAlertService onCreate")
        // Initialize components using context
        busApiService = BusApiService(this)
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        createNotificationChannels()
        loadSettings()
        initializeTts()
    }

    fun initialize(context: Context? = null, flutterEngine: FlutterEngine? = null) {
        Log.d(TAG, "🔔 BusAlertService initialize (Engine: ${flutterEngine != null})")
        try {
            // 안전하게 context 저장
            if (context != null) {
                // 애플리케이션 컨텍스트를 사용하여 서비스가 종료되어도 유효한 컨텍스트 유지
                val appContext = context.applicationContext
                if (appContext != null) {
                    // 이 서비스의 컨텍스트를 애플리케이션 컨텍스트로 업데이트
                    mApplicationContext = appContext
                    Log.d(TAG, "🔔 애플리케이션 컨텍스트 업데이트 완료")
                }
            }

            // 메서드 채널 초기화
            if (_methodChannel == null && flutterEngine != null) {
                initializeMethodChannel(flutterEngine)
            }

            // 설정 및 알림 채널 초기화
            loadSettings()
            createNotificationChannels()
            // TTS is initialized in onCreate
            Log.d(TAG, "✅ BusAlertService 초기화 완료")
        } catch (e: Exception) {
            Log.e(TAG, "🔔 BusAlertService 초기화 오류: ${e.message}", e)
        }
    }

    private fun initializeMethodChannel(flutterEngine: FlutterEngine?) {
        _methodChannel = flutterEngine?.dartExecutor?.binaryMessenger?.let {
            MethodChannel(it, "com.example.daegu_bus_app/bus_api").also {
                 Log.d(TAG, "🔌 메서드 채널 초기화 완료 (FlutterEngine 사용)")
            }
        } ?: run {
            Log.w(TAG, "🔌 메서드 채널 초기화 실패 - FlutterEngine 없음")
            null
        }
    }

    private fun initializeTts() {
        Log.d(TAG, "🔊 TTS 엔진 초기화 시작")
        try {
            ttsEngine?.stop()
            ttsEngine?.shutdown()
            // Use context for TTS initialization
            ttsEngine = TextToSpeech(this) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    isTtsInitialized = true
                    configureTts()
                } else {
                    isTtsInitialized = false
                    Log.e(TAG, "❌ TTS 엔진 초기화 실패: $status")
                }
            }
        } catch (e: Exception) {
            isTtsInitialized = false
            Log.e(TAG, "❌ TTS 엔진 생성 중 오류 발생: ${e.message}", e)
        }
    }

    private fun configureTts() {
        if (!isTtsInitialized || ttsEngine == null) {
             Log.e(TAG,"❌ TTS 설정 시도 - 엔진 초기화 안됨")
             return
        }
        try {
            val result = ttsEngine?.setLanguage(Locale.KOREAN)
            if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                Log.e(TAG, "❌ TTS 한국어 지원 안됨/데이터 없음 (결과: $result)")
                isTtsInitialized = false
            } else {
                ttsEngine?.apply {
                    setSpeechRate(1.0f)
                    setPitch(1.0f)
                    setOnUtteranceProgressListener(createTtsListener())
                }
                Log.d(TAG, "🔊 TTS 엔진 설정 완료 (한국어)")
            }
        } catch (e: Exception) {
            isTtsInitialized = false
            Log.e(TAG, "❌ TTS 언어 및 속성 설정 중 오류: ${e.message}", e)
        }
    }

     // Declare the listener as a member variable
     private val audioFocusListener = OnAudioFocusChangeListener { focusChange ->
         serviceScope.launch {
             when (focusChange) {
                AudioManager.AUDIOFOCUS_LOSS -> {
                    Log.d(TAG, "🔊 오디오 포커스 완전 손실 -> TTS 중지")
                    stopTtsTracking(forceStop = true)
                }
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                    Log.d(TAG, "🔊 일시적 오디오 포커스 손실 -> TTS 중지")
                    if (isTtsInitialized && ttsEngine != null) {
                        ttsEngine?.stop()
                    }
                }
                 AudioManager.AUDIOFOCUS_GAIN -> {
                      Log.d(TAG, "🔊 오디오 포커스 획득/복구")
                 }
             }
         }
     }

    private fun createTtsListener() = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) {
            Log.d(TAG, "🔊 TTS 발화 시작: $utteranceId")
        }

        override fun onDone(utteranceId: String?) {
            Log.d(TAG, "🔊 TTS 발화 완료: $utteranceId")
            audioManager?.abandonAudioFocus(audioFocusListener)
        }

        @Deprecated("Deprecated in Java", ReplaceWith("onError(utteranceId, errorCode)"))
        override fun onError(utteranceId: String?) {
             onError(utteranceId, -1)
        }

        override fun onError(utteranceId: String?, errorCode: Int) {
            Log.e(TAG, "❌ TTS 발화 오류: $utteranceId, errorCode: $errorCode")
            audioManager?.abandonAudioFocus(audioFocusListener)
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                // 컨텍스트 가져오기
                val context = getAppContext()
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                createBusAlertsChannel(notificationManager)
                createBusOngoingChannel(notificationManager)
                Log.d(TAG, "🔔 알림 채널 생성/확인 완료")
            } catch (e: Exception) {
                Log.e(TAG, "🔔 알림 채널 생성 오류: ${e.message}", e)
            }
        }
    }

    private fun createBusAlertsChannel(notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = CHANNEL_BUS_ALERTS
            if (notificationManager.getNotificationChannel(channelId) == null) {
                 val channel = NotificationChannel(channelId, "버스 도착 알림", NotificationManager.IMPORTANCE_HIGH)
                 .apply {
                    description = "버스가 정류장에 도착하기 직전 알림"
                    enableLights(true)
                    lightColor = Color.RED
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 500, 200, 500)
                 }
                 notificationManager.createNotificationChannel(channel)
                 Log.d(TAG,"'$channelId' 채널 생성됨")
            } else {
                 Log.d(TAG,"'$channelId' 채널 이미 존재함")
            }
             updateChannelSound(notificationManager, channelId)
        }
    }

     private fun updateChannelSound(notificationManager: NotificationManager, channelId: String) {
         if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
             val channel = notificationManager.getNotificationChannel(channelId)
             if (channel != null && channel.importance >= NotificationManager.IMPORTANCE_DEFAULT) {
                 val soundUri = if (currentAlarmSound.isNotEmpty()) {
                     // 컨텍스트 가져오기
                     val context = getAppContext()
                     Uri.parse("android.resource://${context.packageName}/raw/$currentAlarmSound")
                 } else { null }
                 val audioAttributes = AudioAttributes.Builder()
                     .setUsage(AudioAttributes.USAGE_ALARM)
                     .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                     .build()
                 channel.setSound(soundUri, audioAttributes)
                 notificationManager.createNotificationChannel(channel)
                 Log.d(TAG,"'$channelId' 채널 사운드 업데이트됨: $currentAlarmSound")
             }
         }
     }

    private fun createBusOngoingChannel(notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
             val channelId = CHANNEL_BUS_ONGOING
             if (notificationManager.getNotificationChannel(channelId) == null) {
                 // applicationContext가 null인 경우 서비스 컨텍스트 사용
                 val context = applicationContext ?: this
                 val channel = NotificationChannel(channelId, "실시간 버스 추적", NotificationManager.IMPORTANCE_DEFAULT)
                 .apply {
                    description = "선택한 버스의 위치 실시간 추적"
                    setSound(null, null)
                    enableVibration(false)
                    enableLights(true)
                    // 컨텍스트를 사용하여 색상 가져오기
                    lightColor = ContextCompat.getColor(context, R.color.tracking_color)
                    setShowBadge(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                 }
                 notificationManager.createNotificationChannel(channel)
                 Log.d(TAG,"'$channelId' 채널 생성됨")
             } else {
                  Log.d(TAG,"'$channelId' 채널 이미 존재함")
             }
        }
    }

    private fun checkNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            try {
                // 컨텍스트 가져오기
                val context = getAppContext()
                val hasPermission = NotificationManagerCompat.from(context).areNotificationsEnabled()
                Log.d(TAG, "Android 13+ 알림 권한 상태: ${if(hasPermission) "허용됨" else "필요함/거부됨"}")
            } catch (e: Exception) {
                Log.e(TAG, "알림 권한 확인 오류: ${e.message}")
            }
        }
    }

    fun registerBusArrivalReceiver() {
        serviceScope.launch {
            if (monitoredRoutes.isEmpty()) {
                Log.w(TAG, "🔔 모니터링할 노선 없음. 타이머 시작 안 함.")
                stopMonitoringTimer()
                return@launch
            }
            if (monitoringJob == null || monitoringJob?.isActive != true) {
                 Log.d(TAG, "🔔 버스 도착 정보 모니터링 타이머 시작 (10초 간격)")
                 stopMonitoringTimer()
                 timer = Timer()
                 monitoringJob = launch {
                    timer.scheduleAtFixedRate(object : TimerTask() {
                        override fun run() {
                             if (monitoredRoutes.isNotEmpty()) {
                                  // Use serviceScope.launch for checkBusArrivals
                                  serviceScope.launch { checkBusArrivals() }
                             } else {
                                  Log.d(TAG, "🔔 모니터링 노선 없어 타이머 작업 중지.")
                                  this.cancel()
                                  stopMonitoringTimer()
                             }
                        }
                    }, 0, 10000)
                 }
                 _methodChannel?.invokeMethod("onBusMonitoringStarted", null)
            } else {
                 Log.d(TAG,"🔔 모니터링 타이머 이미 실행 중.")
            }
        }
    }

    // Make sure this function is defined within the class
    private fun stopMonitoringTimer() {
         serviceScope.launch {
              if (monitoringJob?.isActive == true) {
                   Log.d(TAG,"🔔 모니터링 작업(Job) 취소 시도")
                   monitoringJob?.cancel()
              }
              monitoringJob = null
              try {
                   timer.cancel()
                   Log.d(TAG,"🔔 모니터링 타이머 취소 완료")
              } catch (e: IllegalStateException) {
                   Log.d(TAG,"🔔 모니터링 타이머 이미 취소됨 또는 오류: ${e.message}")
              }
         }
    }

    private suspend fun checkBusArrivals() {
         if (monitoredRoutes.isEmpty()) {
            Log.d(TAG, "🚌 [Timer] 모니터링 노선 없음, 확인 중단")
            stopMonitoringTimer()
            stopTrackingIfIdle()
            return
         }
        Log.d(TAG, "🚌 [Timer] 버스 도착 정보 확인 시작 (${monitoredRoutes.size}개 노선)")
        try {
             val allBusInfos = withContext(Dispatchers.IO) { collectBusArrivals() }
             withContext(Dispatchers.Main) { updateNotifications(allBusInfos) }
        } catch (e: CancellationException) {
             Log.d(TAG,"🚌 [Timer] 버스 도착 확인 작업 취소됨")
        } catch (e: Exception) {
            Log.e(TAG, "❌ [Timer] 버스 도착 확인 중 오류: ${e.message}", e)
        }
    }

    private suspend fun collectBusArrivals(): List<Triple<String, String, BusInfo>> {
        val allBusInfos = mutableListOf<Triple<String, String, BusInfo>>()
        val routesToCheck = monitoredRoutes.toMap()
        for ((routeId, stationInfo) in routesToCheck) {
            val (stationId, stationName) = stationInfo
            try {
                 if (!monitoredRoutes.containsKey(routeId)) {
                      Log.d(TAG, "🚌 $routeId 노선 모니터링 중지됨, API 호출 건너뜀")
                      continue
                 }
                val arrivalInfo = busApiService.getBusArrivalInfoByRouteId(stationId, routeId)
                if (arrivalInfo?.bus?.isNotEmpty() == true) {
                    processBusArrivals(arrivalInfo.bus, routeId, stationName, allBusInfos)
                } else {
                    Log.d(TAG, "🚌 [API Check] $routeId @ $stationName: 도착 예정 버스 정보 없음")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ [API] $routeId 노선 정보 조회 중 오류: ${e.message}")
            }
        }
        return allBusInfos
    }

    private fun processBusArrivals(
        buses: List<StationArrivalOutput.BusInfo>,
        routeId: String,
        stationName: String,
        allBusInfos: MutableList<Triple<String, String, BusInfo>>
    ) {
        for (bus in buses) {
             val busInfo = BusInfo(
                busNumber = bus.busNumber, routeId = routeId,
                estimatedTime = bus.estimatedTime, currentStation = bus.currentStation,
                remainingStations = bus.remainingStations, lastUpdateTime = System.currentTimeMillis()
             )
             val remainingTime = busInfo.getRemainingMinutes()
             val busNo = busInfo.busNumber
             val currentStation = busInfo.currentStation
             val remainingStops = busInfo.remainingStations.replace("[^0-9]".toRegex(), "").toIntOrNull() ?: -1
            updateBusCache(busNo, routeId, busInfo)
            allBusInfos.add(Triple(busNo, stationName, busInfo))
             checkArrivingSoon(
                routeId = routeId, stationId = monitoredRoutes[routeId]?.first ?: "",
                busNo = busNo, stationName = stationName, remainingTime = remainingTime,
                remainingStops = remainingStops, currentStation = currentStation
             )
            Log.d(TAG, "🚌 [API Process] $busNo @ $stationName: 남은 시간 $remainingTime 분, 현재 위치 $currentStation, 남은 정류장 $remainingStops")
        }
    }

    private fun updateBusCache(busNo: String, routeId: String, bus: BusInfo) {
        val cacheKey = "$busNo-$routeId"
        cachedBusInfo[cacheKey] = bus
    }

    private fun checkArrivingSoon(
        routeId: String,
        stationId: String,
        busNo: String,
        stationName: String,
        remainingTime: Int,
        remainingStops: Int,
        currentStation: String?
    ) {
        val shouldTriggerArrivingSoon = (remainingStops == 1 && remainingTime in 0..3)
        val currentNotificationKey = "${routeId}_${stationId}_$busNo"
        if (shouldTriggerArrivingSoon && arrivingSoonNotified.add(currentNotificationKey)) {
            Log.i(TAG, "✅ [Arriving Soon] 조건 만족 & 첫 알림 발생: $currentNotificationKey")
             serviceScope.launch { showBusArrivingSoon(busNo, stationName, currentStation) }
             stopTtsTracking(routeId = routeId, stationId = stationId)
        } else if (shouldTriggerArrivingSoon) {
             Log.d(TAG,"☑️ [Arriving Soon] 조건 만족했으나 이미 알림: $currentNotificationKey")
        }
    }

    private fun updateNotifications(allBusInfos: List<Triple<String, String, BusInfo>>) {
        if (monitoredRoutes.isEmpty()) {
            Log.d(TAG, "모니터링 노선이 없어 알림 업데이트 중지 및 서비스 정리")
            stopTracking()
            return
        }
        // 컨텍스트 가져오기
        val context = getAppContext()
        val notificationManager = NotificationManagerCompat.from(context)
        if (allBusInfos.isEmpty()) {
            Log.d(TAG,"도착 예정 버스 정보 없음. 알림 업데이트 (정보 없음)")
            updateEmptyNotification()
        } else {
            val sortedBusInfos = allBusInfos.sortedBy { it.third.getRemainingMinutes().let { time -> if (time < 0) Int.MAX_VALUE else time } }
            val displayBusTriple = sortedBusInfos.first()
            val (busNo, stationName, busInfo) = displayBusTriple
            val remainingTime = busInfo.getRemainingMinutes()
            val routeId = busInfo.routeId
            val allBusesSummary = if (notificationDisplayMode == DISPLAY_MODE_ALL_BUSES) {
                formatAllArrivalsForNotification(sortedBusInfos)
            } else null
            showOngoingBusTracking(
                busNo = busNo, stationName = stationName, remainingMinutes = remainingTime,
                currentStation = busInfo.currentStation, isUpdate = true,
                notificationId = ONGOING_NOTIFICATION_ID, allBusesSummary = allBusesSummary,
                routeId = routeId
            )
            updateFlutterUI(busNo, busInfo.routeId, remainingTime, busInfo.currentStation)
        }
    }

    private fun updateEmptyNotification() {
         if (monitoredRoutes.isEmpty()) {
              cancelOngoingTracking()
              stopTrackingIfIdle()
              return
         }
         val firstRouteEntry = monitoredRoutes.entries.firstOrNull()
         val routeId = firstRouteEntry?.key ?: "알 수 없음"
         val stationName = firstRouteEntry?.value?.second ?: "알 수 없음"
         showOngoingBusTracking(
            busNo = "-", stationName = stationName, remainingMinutes = -1,
            currentStation = "도착 정보 없음", isUpdate = true,
            notificationId = ONGOING_NOTIFICATION_ID, routeId = routeId
         )
    }

    private fun updateFlutterUI(busNo: String, routeId: String, remainingTime: Int, currentStation: String?) {
         if (_methodChannel == null) {
              Log.w(TAG, "Flutter UI 업데이트 시도 - MethodChannel 초기화 안됨")
              return
         }
        try {
            _methodChannel?.invokeMethod("onBusLocationUpdated", mapOf(
                "busNo" to busNo, "routeId" to routeId, "remainingMinutes" to remainingTime,
                "currentStation" to (currentStation ?: "정보 없음")
            ))
        } catch (e: Exception) {
            Log.e(TAG, "❌ Flutter UI 업데이트 오류: ${e.message}")
        }
    }

    private fun showBusArrivalNotification(stationName: String, busNo: String, remainingTime: Int) {
        try {
            // 컨텍스트 가져오기
            val context = getAppContext()
            val notificationManager = NotificationManagerCompat.from(context)
            val channelId = CHANNEL_BUS_ALERTS
            val notificationId = System.currentTimeMillis().toInt()
            val title = "🚌 $busNo 번 버스 도착 임박!"
            val content = "$stationName 정류장 ${if (remainingTime == 0) "곧 도착" else "약 $remainingTime 분 후 도착"}"
            // 알림 클릭 시 이동할 인텐트 생성
            val intent = Intent(context, MainActivity::class.java).apply {
                 flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
             val pendingIntent = PendingIntent.getActivity(
                 context, notificationId, intent,
                 PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
             )
            // 알림 빌더 생성
            val builder = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.drawable.ic_bus_notification)
                .setContentTitle(title).setContentText(content)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true).setContentIntent(pendingIntent)
                .setDefaults(NotificationCompat.DEFAULT_VIBRATE)
            if (!useTextToSpeech && currentAlarmSound.isNotEmpty()) {
                 // 알림 음성 URI 생성
                 val soundUri = Uri.parse("android.resource://${context.packageName}/raw/$currentAlarmSound")
                 builder.setSound(soundUri)
            }
            notificationManager.notify(notificationId, builder.build())
            Log.d(TAG, "🔔 도착 알림 표시됨 (ID: $notificationId): $busNo 번 ($remainingTime 분)")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 도착 알림 표시 중 오류: ${e.message}")
        }
    }

    fun addMonitoredRoute(routeId: String, stationId: String, stationName: String) {
        if (routeId.isBlank() || stationId.isBlank() || stationName.isBlank()) {
            Log.e(TAG, "🔔 모니터링 추가 실패 - 유효하지 않은 파라미터: R=$routeId, S=$stationId, N=$stationName")
            return
        }
        Log.d(TAG, "🔔 모니터링 노선 추가 요청: R=$routeId, S=$stationId, N=$stationName")
        val wasEmpty = monitoredRoutes.isEmpty()
        monitoredRoutes[routeId] = Pair(stationId, stationName)
        Log.i(TAG, "🔔 모니터링 노선 추가 완료: ${monitoredRoutes.size}개 추적 중")
        if (wasEmpty) {
            registerBusArrivalReceiver()
        } else {
            serviceScope.launch { checkBusArrivals() }
        }
    }

    fun getMonitoredRoutesCount(): Int = monitoredRoutes.size

    fun showNotification(
        id: Int, busNo: String, stationName: String, remainingMinutes: Int,
        currentStation: String? = null, payload: String? = null, routeId: String? = null
    ) {
         Log.d(TAG,"showNotification 호출됨 (Alert 용도): ID=$id, Bus=$busNo, Station=$stationName")
         showBusArrivalNotification(stationName, busNo, remainingMinutes)
    }

    fun showOngoingBusTracking(
        busNo: String, stationName: String, remainingMinutes: Int,
        currentStation: String?, isUpdate: Boolean = false,
        notificationId: Int = ONGOING_NOTIFICATION_ID, allBusesSummary: String? = null,
        routeId: String? = null
    ) {
        try {
            if (routeId == null) {
                 Log.e(TAG, "🚌 routeId가 null입니다. Ongoing 알림 표시/업데이트 불가.")
                 return
            }
            Log.d(TAG, "🚌 Ongoing 알림 표시/업데이트: Bus=$busNo, Route=$routeId, Station=$stationName, Mins=$remainingMinutes, Update=$isUpdate")

            val currentTime = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
            val title = if (monitoredRoutes.size > 1) "$busNo 번 버스 → $stationName" else "$busNo 번 버스 실시간 추적"
            val bodyText = if (remainingMinutes < 0) "도착 정보 없음 ($currentTime)"
                           else if (remainingMinutes == 0) "$stationName 에 곧 도착!"
                           else "약 $remainingMinutes 분 후 $stationName 도착"
            val bigBodyText = buildString {
                if (remainingMinutes < 0) append("$busNo 번 버스 - 도착 정보 없음")
                else if (remainingMinutes == 0) append("✅ $busNo 번 버스가 $stationName 정류장에 곧 도착합니다!")
                else {
                     append("⏱️ $busNo 번 버스가 $stationName 정류장까지 약 $remainingMinutes 분 남았습니다.")
                     if (!currentStation.isNullOrEmpty()) append("\n📍 현재 위치: $currentStation")
                }
                if (allBusesSummary != null) append("\n\n--- 다른 버스 ---\n$allBusesSummary")
            }

            // Use applicationContext
            val contentIntent = Intent(applicationContext, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                putExtra("NOTIFICATION_ID", notificationId)
                putExtra("routeId", routeId)
                putExtra("stationName", stationName)
                putExtra("stationId", monitoredRoutes[routeId]?.first)
            }
            val pendingContentIntent = PendingIntent.getActivity(
                // Use applicationContext
                applicationContext, notificationId,
                contentIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Stop Intent - Ensure it uses applicationContext and correct action
            // Use applicationContext
            val stopTrackingIntent = Intent(applicationContext, BusAlertService::class.java).apply {
                action = ACTION_STOP_BUS_ALERT_TRACKING
                putExtra("routeId", routeId)
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("stationId", monitoredRoutes[routeId]?.first)
            }
            val stopRequestCode = notificationId + (routeId.hashCode() % 10000) + 1
            val stopTrackingPendingIntent = PendingIntent.getService(
                // Use applicationContext
                applicationContext, stopRequestCode,
                stopTrackingIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // Use applicationContext
            val builder = NotificationCompat.Builder(applicationContext, CHANNEL_BUS_ONGOING)
                .setSmallIcon(R.drawable.ic_bus_notification)
                .setContentTitle(title).setContentText(bodyText)
                .setStyle(NotificationCompat.BigTextStyle().bigText(bigBodyText))
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                 // Use applicationContext
                .setColor(ContextCompat.getColor(applicationContext, R.color.tracking_color))
                .setColorized(true).setOngoing(true).setAutoCancel(false)
                .setOnlyAlertOnce(true).setContentIntent(pendingContentIntent)
                .addAction(R.drawable.ic_stop, "추적 중지", stopTrackingPendingIntent)
                .setWhen(System.currentTimeMillis()).setShowWhen(true)

            val progress = if (remainingMinutes < 0) 0
                           else if (remainingMinutes == 0) 100
                           else if (remainingMinutes > 30) 0
                           else ((30 - remainingMinutes) * 100 / 30)
            builder.setProgress(100, progress.coerceIn(0, 100), false)

            val notification = builder.build()
            // Use applicationContext
            val notificationManager = NotificationManagerCompat.from(applicationContext)

            if (!isInForeground) {
                 try {
                      startForeground(notificationId, notification)
                      isInForeground = true
                      Log.i(TAG, "🚌 Foreground 서비스 시작됨 (ID: $notificationId)")
                 } catch (e: Exception) {
                      Log.e(TAG, "🚨 Foreground 서비스 시작 오류: ${e.message}", e)
                      stopTrackingForRoute(routeId, monitoredRoutes[routeId]?.first, busNo)
                 }
            } else {
                 notificationManager.notify(notificationId, notification)
                 Log.d(TAG, "🚌 Ongoing 알림 업데이트됨 (ID: $notificationId)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "🚌 Ongoing 알림 생성/업데이트 오류: ${e.message}")
            if (routeId != null) {
                 stopTrackingForRoute(routeId, monitoredRoutes[routeId]?.first, busNo)
            }
        }
    }

    fun showBusArrivingSoon(busNo: String, stationName: String, currentStation: String? = null) {
        Log.d(TAG, "🔔 showBusArrivingSoon 호출됨 -> showBusArrivalNotification 사용")
        showBusArrivalNotification(stationName, busNo, 0)
        serviceScope.launch {
             val ttsMessage = "$busNo 버스가 이전 정류장에 도착했습니다. $stationName 에 곧 도착합니다. 하차 준비하세요."
             speakTts(ttsMessage, earphoneOnly = false)
        }
    }

    fun startTtsTracking(routeId: String, stationId: String, busNo: String, stationName: String) {
        if (!isTtsInitialized || ttsEngine == null) {
             Log.e(TAG, "🔊 TTS 추적 시작 불가 - 초기화 안됨")
             initializeTts()
             return
        }
        if (!::busApiService.isInitialized) {
             Log.e(TAG,"🔊 TTS 추적 시작 불가 - BusApiService 초기화 안됨")
             return
        }
        if (!useTextToSpeech) {
            Log.d(TAG, "🔊 TTS 설정 비활성화 - TTS 추적 시작 안 함.")
            return
        }
        if (ttsJob?.isActive == true) {
            Log.d(TAG, "🔊 기존 TTS 추적 작업 중지 시도")
            stopTtsTracking(routeId = routeId, stationId = stationId, forceStop = true)
        }
        val notificationKey = "${routeId}_${stationId}_$busNo"
        arrivingSoonNotified.remove(notificationKey)
        Log.d(TAG, "🔊 새 TTS 추적 시작, '$notificationKey' 곧 도착 플래그 초기화")

        isTtsTrackingActive = true
        ttsJob = serviceScope.launch {
            Log.i(TAG, "🔊 TTS 추적 시작: Bus=$busNo ($routeId), Station=$stationName ($stationId)")
            while (isTtsTrackingActive && isActive) {
                 var ttsMessage: String? = null
                 var shouldTriggerArrivingSoon = false
                 var currentBusNoForSoon = busNo
                 var currentStationForSoon = "정보 없음"
                 var remainingStopsForSoon = -1
                 var apiError = false
                 try {
                     if (!useTextToSpeech) {
                         Log.d(TAG, "🔊 TTS 추적 중 설정 비활성화 감지. 루프 중지.")
                         break
                     }
                     val arrivalInfoResult = withContext(Dispatchers.IO) {
                         try {
                             Log.d(TAG, "🚌 [TTS API] 정보 조회 중... ($routeId @ $stationId)")
                             busApiService.getBusArrivalInfoByRouteId(stationId, routeId)
                         } catch (e: Exception) {
                              Log.e(TAG, "❌ [TTS API] 정보 조회 오류: ${e.message}")
                              null
                         }
                     }
                     if (arrivalInfoResult == null) {
                          apiError = true
                          ttsMessage = "$busNo 번 버스 정보 조회에 실패했습니다."
                     } else {
                         val firstBus = arrivalInfoResult.bus.firstOrNull { it.busNumber == busNo }
                         if (firstBus != null) {
                             val busInfo = BusInfo( busNumber = firstBus.busNumber, routeId = routeId,
                                 estimatedTime = firstBus.estimatedTime, currentStation = firstBus.currentStation,
                                 remainingStations = firstBus.remainingStations
                             )
                             val remainingMinutes = busInfo.getRemainingMinutes()
                             val currentStation = busInfo.currentStation ?: "정보 없음"
                             val busStopCount = busInfo.remainingStations.replace("[^0-9]".toRegex(), "").toIntOrNull() ?: -1
                             currentBusNoForSoon = busNo
                             currentStationForSoon = currentStation
                             remainingStopsForSoon = busStopCount
                             ttsMessage = generateTtsMessage(busNo, stationName, remainingMinutes, currentStation, busStopCount)
                             shouldTriggerArrivingSoon = (busStopCount == 1 && remainingMinutes in 0..3)
                             Log.d(TAG,"🔊 [TTS] 처리 완료: Mins=$remainingMinutes, Stops=$busStopCount, Soon=$shouldTriggerArrivingSoon")
                         } else {
                             ttsMessage = "$busNo 번 버스 도착 정보가 없습니다."
                             Log.d(TAG,"🔊 [TTS] $busNo 번 버스 정보 없음 (API 결과)")
                         }
                     }
                     if (ttsMessage != null) {
                         speakTts(ttsMessage, earphoneOnly = false)
                         if (shouldTriggerArrivingSoon) {
                             val notifyKey = "${routeId}_${stationId}_$currentBusNoForSoon"
                             if (arrivingSoonNotified.add(notifyKey)) {
                                 Log.i(TAG, "✅ [TTS] '곧 도착' 조건 만족 & 첫 알림 발동: $notifyKey")
                                 showBusArrivingSoon(currentBusNoForSoon, stationName, currentStationForSoon)
                                 break
                             } else {
                                 Log.d(TAG, "☑️ [TTS] '곧 도착' 조건 만족했으나 이미 알림: $notifyKey")
                             }
                         }
                     }
                     if (apiError) delay(60_000)
                     else delay(30_000)
                 } catch (e: CancellationException) {
                     Log.d(TAG, "🔊 TTS 추적 작업 명시적으로 취소됨 ($busNo @ $stationName)")
                     break
                 } catch (e: Exception) {
                     Log.e(TAG, "❌ TTS 추적 루프 내 오류: ${e.message}", e)
                     delay(15_000)
                 }
            }
            Log.i(TAG, "🔊 TTS 추적 루프 종료: Bus=$busNo ($routeId), Station=$stationName ($stationId)")
            isTtsTrackingActive = false
            ttsJob = null
        }
    }

    fun cancelNotification(id: Int) {
        try {
            // 컨텍스트 가져오기
            val context = getAppContext()
            NotificationManagerCompat.from(context).cancel(id)
            Log.d(TAG, "🔔 알림 취소 완료 (ID: $id)")
        } catch (e: Exception) {
            Log.e(TAG, "🔔 알림 취소 오류 (ID: $id): ${e.message}", e)
        }
    }

    fun cancelOngoingTracking() {
        Log.d(TAG,"cancelOngoingTracking 호출됨 (ID: $ONGOING_NOTIFICATION_ID)")
        try {
            // 컨텍스트 가져오기
            val context = getAppContext()
            NotificationManagerCompat.from(context).cancel(ONGOING_NOTIFICATION_ID)
            Log.d(TAG,"Ongoing notification (ID: $ONGOING_NOTIFICATION_ID) 취소 완료.")
            if (isInForeground) {
                Log.d(TAG, "Service is in foreground, calling stopForeground(true).")
                stopForeground(true)
                isInForeground = false
            }
        } catch (e: Exception) {
            Log.e(TAG, "🚌 Ongoing 알림 취소/Foreground 중지 오류: ${e.message}", e)
        }
    }

    fun cancelAllNotifications() {
        try {
            // 컨텍스트 가져오기
            val context = getAppContext()
            NotificationManagerCompat.from(context).cancelAll()
            Log.i(TAG, "🔔 모든 알림 취소 완료 (cancelAllNotifications)")
            if (isInForeground) {
                stopForeground(true)
                isInForeground = false
                 Log.d(TAG,"Foreground 서비스 중단됨 (cancelAllNotifications)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "🔔 모든 알림 취소 오류: ${e.message}", e)
        }
    }

    fun stopTracking() {
        Log.i(TAG, "--- BusAlertService 전체 추적 중지 시작 ---")
        serviceScope.launch {
             try {
                stopMonitoringTimer()
                stopTtsTracking(forceStop = true)
                monitoredRoutes.clear()
                cachedBusInfo.clear()
                arrivingSoonNotified.clear()
                Log.d(TAG, "모니터링 노선 및 관련 캐시/플래그 초기화됨")
                cancelOngoingTracking()
                _methodChannel?.invokeMethod("onBusMonitoringStopped", null)
                Log.i(TAG,"모든 작업 중지됨. 서비스는 유지됨.")
                // stopSelf() 호출 제거 - 서비스를 종료하지 않고 유지
             } catch (e: Exception) {
                 Log.e(TAG, "stopTracking 중 심각한 오류: ${e.message}", e)
                 // stopSelf() 호출 제거 - 오류 발생해도 서비스 유지
             } finally {
                 Log.i(TAG, "--- BusAlertService 전체 추적 중지 완료 ---")
             }
        }
    }

    fun stopTrackingForRoute(routeId: String?, stationId: String?, busNo: String?) {
         serviceScope.launch {
             if (routeId == null) {
                 Log.w(TAG, "stopTrackingForRoute 호출됨 - routeId 없음, 중단.")
                 return@launch
             }
             Log.i(TAG, "stopTrackingForRoute 시작: Route=$routeId, Station=$stationId, Bus=$busNo")
             // TTS 추적 중지
             stopTtsTracking(routeId = routeId, stationId = stationId, forceStop = true)

             // 포그라운드 알림 취소 - 여기서 추가
             cancelOngoingTracking()
             Log.d(TAG, "포그라운드 알림 취소 완료 (stopTrackingForRoute)")
             // 모니터링 노선 제거
             val removedRouteInfo = monitoredRoutes.remove(routeId)
             if (removedRouteInfo != null) {
                 Log.d(TAG, "모니터링 목록에서 $routeId 제거됨 (Station: ${removedRouteInfo.first})")
             } else {
                 Log.d(TAG, "모니터링 목록에 $routeId 없음")
             }
             // 도착 임박 플래그 제거
             if (stationId != null && busNo != null) {
                  val notificationKey = "${routeId}_${stationId}_$busNo"
                  if (arrivingSoonNotified.remove(notificationKey)) {
                      Log.d(TAG, "'곧 도착' 플래그 제거됨: $notificationKey")
                  }
             }
             // 모니터링 노선이 없으면 전체 추적 중지, 있으면 알림 업데이트
             if (monitoredRoutes.isEmpty()) {
                 Log.i(TAG, "$routeId 제거 후 남은 노선 없음. 전체 추적 중지 호출.")
                 stopTracking()
             } else {
                 Log.i(TAG, "$routeId 제거 후 ${monitoredRoutes.size}개 노선 남음. 알림 업데이트 필요.")
                 checkBusArrivals()
             }
         }
    }

    fun stopTtsTracking(forceStop: Boolean = false, routeId: String? = null, stationId: String? = null) {
        serviceScope.launch {
            if (!isTtsTrackingActive && !forceStop) {
                Log.d(TAG, "🔊 TTS 추적이 이미 중지된 상태입니다 (forceStop=false).")
                return@launch
            }
            Log.d(TAG, "🔊 TTS 추적 중지 시도 (forceStop=$forceStop, routeId=$routeId, stationId=$stationId)")
            try {
                if (ttsJob?.isActive == true) {
                    ttsJob?.cancel(CancellationException("TTS 추적 중지 요청됨 (stopTtsTracking)"))
                    Log.d(TAG, "🔊 TTS 코루틴 작업 취소됨")
                }
                ttsJob = null
                if (isTtsInitialized && ttsEngine != null) {
                     ttsEngine?.stop()
                     Log.d(TAG, "🔊 TTS 엔진 stop() 호출됨")
                     audioManager?.abandonAudioFocus(audioFocusListener)
                }
                isTtsTrackingActive = false
                Log.d(TAG, "🔊 isTtsTrackingActive 플래그 false로 설정됨")
                 if (routeId != null && stationId != null) {
                     val prefixKey = "${routeId}_${stationId}"
                     val keysToRemove = arrivingSoonNotified.filter { it.startsWith(prefixKey) }
                     if (keysToRemove.isNotEmpty()) {
                         arrivingSoonNotified.removeAll(keysToRemove)
                         Log.d(TAG, "🔊 TTS 추적 중지, '$prefixKey' 관련 '곧 도착' 알림 플래그 제거됨 (${keysToRemove.size}개)")
                     }
                 }
                Log.i(TAG, "🔊 TTS 추적 중지 완료 (forceStop: $forceStop)")
            } catch (e: Exception) {
                Log.e(TAG, "❌ TTS 추적 중지 오류: ${e.message}", e)
                isTtsTrackingActive = false
                ttsJob = null
            }
        }
    }

    override fun onDestroy() {
        Log.i(TAG, "🔔 BusAlertService onDestroy 시작")
        serviceScope.launch { // Ensure cleanup runs on main scope
             // 서비스 종료 시 추적 중지만 하고 자원 해제
             stopMonitoringTimer()
             stopTtsTracking(forceStop = true)
             cancelOngoingTracking()

             // TTS 자원 해제
             ttsEngine?.stop()
             ttsEngine?.shutdown()
             ttsEngine = null
             isTtsInitialized = false

             // 인스턴스 유지 - 서비스가 재시작될 때 사용하기 위해
             // instance = null

             Log.d(TAG,"TTS 엔진 종료 및 자원 해제 완료")
        }.invokeOnCompletion {
             serviceScope.cancel() // Cancel the scope itself after cleanup
             super.onDestroy()
             Log.i(TAG, "🔔 BusAlertService onDestroy 완료")
        }
    }

    fun getCachedBusInfo(busNo: String, routeId: String): BusInfo? {
        val cacheKey = "$busNo-$routeId"
        val cachedInfo = cachedBusInfo[cacheKey]
        if (cachedInfo != null) {
            val lastUpdateTime = cachedInfo.lastUpdateTime ?: 0L
            val currentTime = System.currentTimeMillis()
            val elapsedMinutes = (currentTime - lastUpdateTime) / (1000 * 60)
            val cacheValidityMinutes = 2
            if (elapsedMinutes > cacheValidityMinutes) {
                Log.d(TAG, "🚌 캐시 만료됨 ($elapsedMinutes 분 경과): $cacheKey")
                cachedBusInfo.remove(cacheKey)
                return null
            }
            Log.d(TAG,"🚌 유효한 캐시 사용 ($elapsedMinutes 분 전): $cacheKey")
            return cachedInfo
        }
        return null
    }

    private fun loadSettings() {
        try {
            // 컨텍스트 가져오기
            val context = getAppContext()
            val prefs = context.getSharedPreferences("bus_alert_settings", Context.MODE_PRIVATE)
            currentAlarmSound = prefs.getString(PREF_ALARM_SOUND_FILENAME, DEFAULT_ALARM_SOUND) ?: DEFAULT_ALARM_SOUND
            useTextToSpeech = prefs.getBoolean(PREF_ALARM_USE_TTS, true)
            audioOutputMode = prefs.getInt(PREF_SPEAKER_MODE, OUTPUT_MODE_AUTO)
            notificationDisplayMode = prefs.getInt(PREF_NOTIFICATION_DISPLAY_MODE_KEY, DISPLAY_MODE_ALARMED_ONLY)
            ttsVolume = prefs.getFloat(PREF_TTS_VOLUME, 1.0f).coerceIn(0f, 1f)
            Log.d(TAG, "⚙️ 설정 로드 완료 - TTS: $useTextToSpeech, 알람음: $currentAlarmSound, 모드: $notificationDisplayMode, 출력: $audioOutputMode, 볼륨: ${ttsVolume * 100}%")
             if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                  val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                  updateChannelSound(notificationManager, CHANNEL_BUS_ALERTS)
             }
        } catch (e: Exception) {
            Log.e(TAG, "⚙️ 설정 로드 중 오류: ${e.message}")
        }
    }

    fun setAlarmSound(filename: String, useTts: Boolean = false) {
         serviceScope.launch {
             try {
                 currentAlarmSound = filename.ifBlank { "" }
                 useTextToSpeech = useTts
                 // 컨텍스트 가져오기
                 val context = getAppContext()
                 val sharedPreferences = context.getSharedPreferences("bus_alert_settings", Context.MODE_PRIVATE)
                 sharedPreferences.edit()
                    .putString(PREF_ALARM_SOUND_FILENAME, currentAlarmSound)
                    .putBoolean(PREF_ALARM_USE_TTS, useTextToSpeech)
                    .apply()
                 if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    // 컨텍스트 가져오기
                    val context = getAppContext()
                    val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    updateChannelSound(notificationManager, CHANNEL_BUS_ALERTS)
                 }
                 Log.i(TAG, "🔔 알람음 설정 저장됨: '$currentAlarmSound', TTS 사용: $useTextToSpeech")
             } catch (e: Exception) {
                 Log.e(TAG, "🔔 알람음 설정 오류: ${e.message}", e)
             }
         }
    }

    fun setAudioOutputMode(mode: Int) {
         serviceScope.launch {
             try {
                if (mode in OUTPUT_MODE_HEADSET..OUTPUT_MODE_AUTO) {
                    audioOutputMode = mode
                    // 컨텍스트 가져오기
                    val context = getAppContext()
                    val prefs = context.getSharedPreferences("bus_alert_settings", Context.MODE_PRIVATE)
                    prefs.edit().putInt(PREF_SPEAKER_MODE, audioOutputMode).apply()
                    Log.i(TAG, "🔔 오디오 출력 모드 설정 저장됨: $audioOutputMode")
                } else {
                    Log.e(TAG, "🔔 잘못된 오디오 출력 모드 값: $mode")
                }
             } catch (e: Exception) {
                 Log.e(TAG, "🔔 오디오 출력 모드 설정 오류: ${e.message}", e)
             }
         }
    }

    fun getAudioOutputMode(): Int = audioOutputMode

    private fun isHeadsetConnected(): Boolean {
        if (audioManager == null) {
             Log.w(TAG,"AudioManager null in isHeadsetConnected")
             return false
        }
        try {
             val isWired = audioManager?.isWiredHeadsetOn ?: false
             val isA2dp = audioManager?.isBluetoothA2dpOn ?: false
             val isSco = audioManager?.isBluetoothScoOn ?: false
             val isConnected = isWired || isA2dp || isSco
             Log.d(TAG, "🎧 이어폰 연결 상태: 유선=$isWired, BT(A2DP)=${isA2dp}, BT(SCO)=${isSco} -> 연결됨=$isConnected")
            return isConnected
        } catch (e: Exception) {
            Log.e(TAG, "🎧 이어폰 연결 상태 확인 오류: ${e.message}", e)
            return false
        }
    }

    fun speakTts(text: String, earphoneOnly: Boolean = false) {
        if (!isTtsInitialized || ttsEngine == null) {
             Log.e(TAG, "🔊 TTS 발화 불가 - 엔진 초기화 안됨")
             initializeTts()
             return
        }
        if (!useTextToSpeech) {
            Log.d(TAG, "🔊 TTS 설정 비활성화됨. 발화 건너뜀.")
            return
        }
        if (text.isBlank()) {
             Log.w(TAG, "🔊 TTS 발화 불가 - 메시지 비어있음")
             return
        }
        serviceScope.launch {
             try {
                val message = text
                if (audioManager == null) audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val isHeadsetConnected = isHeadsetConnected()
                val useSpeaker = when (audioOutputMode) {
                    OUTPUT_MODE_SPEAKER -> true
                    OUTPUT_MODE_HEADSET -> false
                    OUTPUT_MODE_AUTO -> !isHeadsetConnected
                    else -> !isHeadsetConnected
                }
                val streamType = if (useSpeaker) AudioManager.STREAM_ALARM else AudioManager.STREAM_MUSIC
                Log.d(TAG, "🔊 TTS 발화 준비: Stream=${if(streamType == AudioManager.STREAM_ALARM) "ALARM" else "MUSIC"}, 스피커사용=$useSpeaker, 볼륨=${ttsVolume * 100}%")
                val utteranceId = "tts_${System.currentTimeMillis()}"
                val params = Bundle().apply {
                    putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
                    putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, streamType)
                    putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, ttsVolume)
                }
                val focusResult: Int
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                     val audioAttributes = AudioAttributes.Builder()
                        .setUsage(if (useSpeaker) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                        .build()
                     val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
                        .setAudioAttributes(audioAttributes)
                        .setAcceptsDelayedFocusGain(true)
                        .setOnAudioFocusChangeListener(audioFocusListener)
                        .build()
                     focusResult = audioManager?.requestAudioFocus(focusRequest) ?: AudioManager.AUDIOFOCUS_REQUEST_FAILED
                } else {
                     @Suppress("DEPRECATION")
                     focusResult = audioManager?.requestAudioFocus(
                        audioFocusListener, streamType, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT
                     ) ?: AudioManager.AUDIOFOCUS_REQUEST_FAILED
                }
                if (focusResult == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                    Log.d(TAG, "🔊 오디오 포커스 획득 성공. TTS 발화 시작.")
                    ttsEngine?.setOnUtteranceProgressListener(createTtsListener())
                    ttsEngine?.speak(message, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
                } else {
                    Log.e(TAG, "🔊 오디오 포커스 획득 실패 ($focusResult). TTS 발화 취소.")
                }
             } catch (e: Exception) {
                 Log.e(TAG, "❌ TTS 발화 중 오류 발생: ${e.message}", e)
                 audioManager?.abandonAudioFocus(audioFocusListener)
             }
        }
    }

    private fun generateTtsMessage(busNo: String, stationName: String, remainingMinutes: Int?, currentStation: String?, remainingStops: Int?): String {
         return when {
             remainingMinutes == null || remainingMinutes < 0 -> "$busNo 번 버스 도착 정보를 알 수 없습니다."
             remainingStops == 1 && (remainingMinutes) in 0..3 -> "$busNo 버스가 이전 정류장에 도착했습니다. $stationName 에 곧 도착하니 하차 준비하세요."
             remainingMinutes == 0 -> "$busNo 버스가 $stationName 에 도착했습니다. 하차하세요."
             else -> {
                 val locationInfo = if (!currentStation.isNullOrEmpty() && currentStation != "정보 없음") " 현재 $currentStation" else ""
                 "$busNo 버스가$locationInfo 에서 출발하여, $stationName 에 약 ${remainingMinutes}분 후 도착 예정입니다."
             }
        }
    }

    private fun formatAllArrivalsForNotification(arrivals: List<Triple<String, String, BusInfo>>): String {
        if (arrivals.isEmpty()) return "도착 예정 버스 정보가 없습니다."
        val soonestPerRoute = arrivals
            .groupBy { it.first }
            .mapValues { (_, busList) -> busList.minByOrNull { it.third.getRemainingMinutes().let { t -> if (t < 0) Int.MAX_VALUE else t} } }
            .values.filterNotNull()
            .sortedBy { it.third.getRemainingMinutes().let { t -> if (t < 0) Int.MAX_VALUE else t} }
        return buildString {
            val displayCount = min(soonestPerRoute.size, 4)
            for (i in 0 until displayCount) {
                val (busNo, _, busInfo) = soonestPerRoute[i]
                val timeStr = busInfo.estimatedTime
                append("${busNo}번: $timeStr")
                if (i < displayCount - 1) append("\n")
            }
            if (soonestPerRoute.size > displayCount) {
                if (displayCount > 0) append("\n")
                append("외 ${soonestPerRoute.size - displayCount}대 더 있음")
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
         if (!::busApiService.isInitialized) { // Ensure critical components are ready
            Log.w(TAG, "onStartCommand: BusApiService 재초기화 시도")
            busApiService = BusApiService(this)
         }

        val action = intent?.action
        Log.i(TAG, "onStartCommand 수신: Action=$action, StartId=$startId")
        serviceScope.launch {
            try {
                 when (action) {
                    ACTION_START_TRACKING_FOREGROUND, ACTION_UPDATE_TRACKING -> {
                        val busNo = intent.getStringExtra("busNo") ?: ""
                        val stationName = intent.getStringExtra("stationName") ?: ""
                        val remainingMinutes = intent.getIntExtra("remainingMinutes", -1)
                        val currentStation = intent.getStringExtra("currentStation")
                        val isUpdate = action == ACTION_UPDATE_TRACKING
                        val allBusesSummary = intent.getStringExtra("allBusesSummary")
                        val routeId = intent.getStringExtra("routeId")
                        val stationId = intent.getStringExtra("stationId")
                        if (routeId == null || busNo.isBlank() || stationName.isBlank()) {
                             Log.e(TAG, "$action 처리 중단: 필수 정보 부족")
                             stopTrackingIfIdle()
                             return@launch
                        }
                        if (action == ACTION_START_TRACKING_FOREGROUND) {
                             if (!stationId.isNullOrBlank()) {
                                 addMonitoredRoute(routeId, stationId, stationName)
                             } else {
                                  Log.w(TAG, "모니터링 추가 건너뜀 - $routeId @ $stationName (StationID 없음)")
                             }
                        }
                        showOngoingBusTracking(
                            busNo = busNo, stationName = stationName, remainingMinutes = remainingMinutes,
                            currentStation = currentStation, isUpdate = isUpdate,
                            notificationId = ONGOING_NOTIFICATION_ID, allBusesSummary = allBusesSummary,
                            routeId = routeId
                        )
                    }
                    ACTION_STOP_BUS_ALERT_TRACKING -> {
                         val routeId = intent.getStringExtra("routeId")
                         val stationId = intent.getStringExtra("stationId")
                         val busNo = intent.getStringExtra("busNo")
                         val stationName = intent.getStringExtra("stationName")
                         Log.i(TAG, "알림 Action '$action' 수신: Route=$routeId, Station=$stationId, Bus=$busNo, StationName=$stationName")

                         // Flutter 측에 알람 취소 알림 전송
                         if (busNo != null && routeId != null) {
                             try {
                                 val alarmCancelData = mapOf(
                                     "busNo" to busNo,
                                     "routeId" to routeId,
                                     "stationName" to (stationName ?: "")
                                 )
                                 // 메인 메서드 채널로 전송
                                 _methodChannel?.invokeMethod("onAlarmCanceledFromNotification", alarmCancelData)
                                 Log.i(TAG, "Flutter 측에 알람 취소 알림 전송 완료: $busNo, $routeId")

                                 // 앱 컨텍스트를 통해 이벤트 발생
                                 val intent = Intent("com.example.daegu_bus_app.ALARM_CANCELED")
                                 intent.putExtra("busNo", busNo)
                                 intent.putExtra("routeId", routeId)
                                 intent.putExtra("stationName", stationName ?: "")
                                 applicationContext.sendBroadcast(intent)
                                 Log.i(TAG, "Broadcast 이벤트 발생: ALARM_CANCELED")
                             } catch (e: Exception) {
                                 Log.e(TAG, "Flutter 측에 알람 취소 알림 전송 오류: ${e.message}")
                             }
                         }

                         // 추적 중지 실행
                         stopTrackingForRoute(routeId, stationId, busNo)
                    }
                    else -> {
                         Log.w(TAG, "처리되지 않은 Action 수신: $action")
                          stopTrackingIfIdle()
                    }
                 }
            } catch (e: Exception) {
                 Log.e(TAG, "onStartCommand Action 처리 중 오류 (Action: $action): ${e.message}", e)
                 stopTrackingIfIdle()
            }
        }
        return START_STICKY
    }

     private fun stopTrackingIfIdle() {
         serviceScope.launch {
             if (monitoredRoutes.isEmpty() && !isTtsTrackingActive) {
                 Log.i(TAG, "서비스 유휴 상태 감지. 전체 추적 중지 호출.")
                 stopTracking()
             } else {
                  Log.d(TAG,"서비스 유휴 상태 아님 (모니터링: ${monitoredRoutes.size}, TTS: $isTtsTrackingActive).")
             }
         }
     }

    fun setTtsVolume(volume: Double) {
        serviceScope.launch {
            try {
                ttsVolume = volume.toFloat().coerceIn(0f, 1f)
                // 컨텍스트 가져오기
                val context = getAppContext()
                val prefs = context.getSharedPreferences("bus_alert_settings", Context.MODE_PRIVATE)
                prefs.edit().putFloat(PREF_TTS_VOLUME, ttsVolume).apply()
                Log.i(TAG, "🔊 TTS 볼륨 설정됨: ${ttsVolume * 100}%")
            } catch (e: Exception) {
                Log.e(TAG, "🔊 TTS 볼륨 설정 오류: ${e.message}", e)
            }
        }
    }

} // End of BusAlertService class


class NotificationDismissReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val notificationId = intent.getIntExtra("NOTIFICATION_ID", -1)
        if (notificationId != -1) {
            Log.d("NotificationDismiss", "🔔 일반 알림 해제됨 (ID: $notificationId)")
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

fun BusAlertService.BusInfo.toMap(): Map<String, Any?> {
    val isLowFloor = false
    val isOutOfService = estimatedTime == "운행종료"
    return mapOf(
        "busNumber" to busNumber, "routeId" to routeId, "estimatedTime" to estimatedTime,
        "currentStation" to currentStation, "remainingStations" to remainingStations,
        "lastUpdateTime" to lastUpdateTime, "isLowFloor" to isLowFloor,
        "isOutOfService" to isOutOfService, "remainingMinutes" to getRemainingMinutes()
    )
}

fun StationArrivalOutput.BusInfo.toMap(): Map<String, Any?> {
    return mapOf(
        "busNumber" to busNumber, "currentStation" to currentStation,
        "remainingStations" to remainingStations, "estimatedTime" to estimatedTime
    )
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