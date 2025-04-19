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
                    it.initialize(context)
                    instance = it
                }
            }
        }
    }

    // 서비스 상태 및 설정
    private var _methodChannel: MethodChannel? = null
    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var context: Context
    private lateinit var busApiService: BusApiService
    private var monitoringJob: Job? = null
    private val monitoredRoutes = mutableMapOf<String, Pair<String, String>>()
    private var timer = Timer()
    private var ttsJob: Job? = null
    private var ttsEngine: TextToSpeech? = null
    private var isTtsTrackingActive = false
    private var isInTrackingModePrivate = false
    private var currentAlarmSound = DEFAULT_ALARM_SOUND
    private var useTextToSpeech = false
    private var audioOutputMode = OUTPUT_MODE_AUTO
    private var notificationDisplayMode = DISPLAY_MODE_ALARMED_ONLY
    private var ttsVolume: Float = 1.0f
    private var audioManager: AudioManager? = null

    // 추가: isInTrackingMode getter
    val isInTrackingMode: Boolean
        get() = isInTrackingModePrivate || monitoredRoutes.isNotEmpty()

    // 캐시 및 상태 추적
    private val lastRemainingTimes = mutableMapOf<String, Int>()
    private val lastTimestamps = mutableMapOf<String, Long>()
    private val cachedBusInfo = mutableMapOf<String, BusInfo>()
    private val arrivingSoonNotified = mutableSetOf<String>()

    // BusInfo 데이터 클래스
    data class BusInfo(
        val busNumber: String,
        val routeId: String,
        val estimatedTime: String,
        val currentStation: String?,
        val remainingStations: String,
        var lastUpdateTime: Long? = null
    )

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        if (!::busApiService.isInitialized) {
            busApiService = BusApiService(this)
        }
    }

    fun initialize(context: Context? = null, flutterEngine: FlutterEngine? = null) {
        try {
            val actualContext = context ?: this.context
            if (actualContext == null) {
                Log.e(TAG, "🔔 컨텍스트가 없어 알림 서비스를 초기화할 수 없습니다")
                return
            }
            this.context = actualContext.applicationContext
            Log.d(TAG, "🔔 알림 서비스 초기화")

            if (!::busApiService.isInitialized) {
                busApiService = BusApiService(actualContext)
                Log.d(TAG, "🚌 BusApiService 초기화 완료")
            }

            loadSettings()
            createNotificationChannels()
            checkNotificationPermission()
            initializeMethodChannel(flutterEngine)
            initializeTts()

            // 서비스가 이미 실행 중인지 확인
            if (isInTrackingMode) {
                Log.d(TAG, "🔔 서비스가 이미 실행 중입니다. 알림 채널 재생성")
                createNotificationChannels()
            }

            Log.d(TAG, "✅ BusAlertService 초기화 완료")
        } catch (e: Exception) {
            Log.e(TAG, "🔔 알림 서비스 초기화 중 오류 발생: ${e.message}", e)
        }
    }

    private fun initializeMethodChannel(flutterEngine: FlutterEngine?) {
        _methodChannel = if (flutterEngine != null) {
            MethodChannel(
                flutterEngine.dartExecutor.binaryMessenger,
                "com.example.daegu_bus_app/bus_api"
            ).also {
                Log.d(TAG, "🔌 메서드 채널 초기화 완료 (FlutterEngine 사용)")
            }
        } else {
            val messenger = FlutterEngine(context).dartExecutor.binaryMessenger
            MethodChannel(
                messenger,
                "com.example.daegu_bus_app/bus_api"
            ).also {
                Log.d(TAG, "🔌 메서드 채널 초기화 완료 (기본 메시지 채널 사용)")
            }
        }
    }

    private fun initializeTts() {
        Log.d(TAG, "🔊 TTS 엔진 초기화 시작")
        try {
            ttsEngine?.shutdown()
            ttsEngine = TextToSpeech(context) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    configureTts()
                } else {
                    Log.e(TAG, "❌ TTS 엔진 초기화 실패: $status")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ TTS 엔진 초기화 중 오류 발생: ${e.message}", e)
        }
    }

    private fun configureTts() {
        try {
            val result = ttsEngine?.setLanguage(Locale.KOREAN)
            when (result) {
                TextToSpeech.LANG_MISSING_DATA -> Log.e(TAG, "❌ 한국어 언어 데이터 없음")
                TextToSpeech.LANG_NOT_SUPPORTED -> Log.e(TAG, "❌ 한국어가 지원되지 않음")
                else -> {
                    ttsEngine?.apply {
                        setSpeechRate(1.0f)
                        setPitch(1.0f)
                        setOnUtteranceProgressListener(createTtsListener())
                    }
                    Log.d(TAG, "🔊 TTS 엔진 초기화 성공")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ TTS 언어 및 속성 설정 중 오류: ${e.message}", e)
        }
    }

    private fun createTtsListener() = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String?) {
            Log.d(TAG, "🔊 TTS 발화 시작: $utteranceId")
        }

        override fun onDone(utteranceId: String?) {
            Log.d(TAG, "🔊 TTS 발화 완료: $utteranceId")
        }

        override fun onError(utteranceId: String?, errorCode: Int) {
            Log.e(TAG, "❌ TTS 발화 오류: $utteranceId, errorCode: $errorCode")
        }

        override fun onError(utteranceId: String?) {
            Log.e(TAG, "❌ TTS 발화 오류 (Deprecated): $utteranceId")
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                
                // 기존 채널 삭제
                notificationManager.deleteNotificationChannel(CHANNEL_BUS_ALERTS)
                notificationManager.deleteNotificationChannel(CHANNEL_BUS_ONGOING)

                // 알림 채널 생성
                createBusAlertsChannel(notificationManager)
                createBusOngoingChannel(notificationManager)
                
                Log.d(TAG, "🔔 알림 채널 생성 완료")
            } catch (e: Exception) {
                Log.e(TAG, "🔔 알림 채널 생성 오류: ${e.message}", e)
            }
        }
    }

    private fun createBusAlertsChannel(notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_BUS_ALERTS,
                "Bus Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "버스 도착 알림"
                enableLights(true)
                lightColor = Color.RED
                enableVibration(true)
                
                if (currentAlarmSound.isNotEmpty()) {
                    setSound(
                        Uri.parse("android.resource://${context.packageName}/raw/$currentAlarmSound"),
                        AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                }
            }
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun createBusOngoingChannel(notificationManager: NotificationManager) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_BUS_ONGOING,
                "Bus Tracking",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "버스 위치 실시간 추적"
                enableLights(true)
                lightColor = ContextCompat.getColor(context, R.color.tracking_color)
                enableVibration(true)
                setShowBadge(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setSound(null, null)  // 소리 없음
                vibrationPattern = longArrayOf(0, 250, 250, 250)  // 짧은 진동
            }
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "🔔 지속적인 추적 알림 채널 생성됨: $CHANNEL_BUS_ONGOING")
        }
    }

    private fun checkNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Log.d(TAG, "Android 13+ 알림 권한 확인 필요")
        }
    }

    fun registerBusArrivalReceiver() {
        try {
            Log.d(TAG, "🔔 버스 도착 이벤트 리시버 등록 시작")

            if (monitoredRoutes.isEmpty()) {
                Log.e(TAG, "🔔 모니터링할 노선이 없습니다. 서비스를 시작하지 않습니다.")
                return
            }

            monitoringJob?.cancel()
            timer.cancel()
            timer = Timer()

            // 새 모니터링 작업 시작
            monitoringJob = serviceScope.launch {
                timer.scheduleAtFixedRate(object : TimerTask() {
                    override fun run() {
                        serviceScope.launch {
                            checkBusArrivals()
                        }
                    }
                }, 0, 10000) // 10초마다 업데이트
            }

            isInTrackingModePrivate = true
            _methodChannel?.invokeMethod("onBusMonitoringStarted", null)
            Log.d(TAG, "🔔 버스 도착 이벤트 리시버 등록 완료 (10초 간격 업데이트)")
        } catch (e: Exception) {
            handleMonitoringError(e)
        }
    }

    private fun handleMonitoringError(e: Exception) {
        Log.e(TAG, "🔔 버스 도착 이벤트 리시버 등록 오류: ${e.message}", e)
        try {
            timer.cancel()
            timer = Timer()
            monitoringJob = serviceScope.launch {
                timer.scheduleAtFixedRate(object : TimerTask() {
                    override fun run() {
                        serviceScope.launch {
                            checkBusArrivals()
                        }
                    }
                }, 1000, 10000) // 1초 후 시작, 10초마다 업데이트
            }
            isInTrackingModePrivate = true
            Log.d(TAG, "🔔 버스 도착 이벤트 리시버 재시도 성공")
        } catch (retryError: Exception) {
            Log.e(TAG, "🔔 버스 도착 이벤트 리시버 재시도 실패: ${retryError.message}", retryError)
            throw retryError
        }
    }

    private suspend fun checkBusArrivals() {
        if (monitoredRoutes.isEmpty()) {
            Log.d(TAG, "🚌 [Timer] 모니터링 노선 없음, 확인 중단")
            return
        }

        try {
            val allBusInfos = collectBusArrivals()
            updateNotifications(allBusInfos)
        } catch (e: Exception) {
            Log.e(TAG, "❌ [Timer] 버스 도착 확인 중 오류: ${e.message}", e)
        }
    }

    private suspend fun collectBusArrivals(): List<Triple<String, String, BusInfo>> {
        val allBusInfos = mutableListOf<Triple<String, String, BusInfo>>()
        
        for ((routeId, stationInfo) in monitoredRoutes) {
            val (stationId, stationName) = stationInfo
            try {
                val arrivalInfo = busApiService.getBusArrivalInfoByRouteId(stationId, routeId)
                
                if (arrivalInfo?.bus?.isNotEmpty() == true) {
                    processBusArrivals(arrivalInfo.bus, routeId, stationName, allBusInfos)
                } else {
                    Log.d(TAG, "🚌 [Timer Check] $routeId @ $stationName: 도착 예정 버스 정보 없음")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ [Timer] $routeId 노선 정보 조회 중 오류: ${e.message}")
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
            val remainingTime = parseEstimatedTime(bus.estimatedTime)
            val busNo = bus.busNumber
            val currentStation = bus.currentStation
            val remainingStops = bus.remainingStations.replace("[^0-9]".toRegex(), "").toIntOrNull() ?: -1

            // BusInfo 객체 생성
            val busInfo = BusInfo(
                busNumber = busNo,
                routeId = routeId,
                estimatedTime = bus.estimatedTime,
                currentStation = currentStation,
                remainingStations = bus.remainingStations,
                lastUpdateTime = System.currentTimeMillis()
            )

            updateBusCache(busNo, routeId, busInfo)
            allBusInfos.add(Triple(busNo, stationName, busInfo))

            checkArrivingSoon(
                routeId = routeId,
                stationId = monitoredRoutes[routeId]?.first ?: "",
                busNo = busNo,
                stationName = stationName,
                remainingTime = remainingTime,
                remainingStops = remainingStops,
                currentStation = currentStation
            )

            Log.d(TAG, "🚌 [Timer Check] $busNo @ $stationName: 남은 시간 $remainingTime 분, 현재 위치 $currentStation, 남은 정류장 $remainingStops")
        }
    }

    private fun updateBusCache(busNo: String, routeId: String, bus: BusInfo) {
        val cacheKey = "$busNo-$routeId"
        cachedBusInfo[cacheKey] = bus.copy(lastUpdateTime = System.currentTimeMillis())
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
        val shouldTriggerArrivingSoon = (remainingStops == 1 && remainingTime <= 3)
        val currentNotificationKey = "${routeId}_${stationId}_$busNo"

        if (shouldTriggerArrivingSoon && !arrivingSoonNotified.contains(currentNotificationKey)) {
            Log.d(TAG, "✅ [Timer] '곧 도착' 조건 만족 & 첫 알림: $currentNotificationKey")
            arrivingSoonNotified.add(currentNotificationKey)
            showBusArrivingSoon(busNo, stationName, currentStation)
        }
    }

    private fun updateNotifications(allBusInfos: List<Triple<String, String, BusInfo>>) {
        if (allBusInfos.isEmpty()) {
            updateEmptyNotification()
            return
        }

        val sortedBusInfos = allBusInfos.sortedBy {
            val time = parseEstimatedTime(it.third.estimatedTime)
            if (time < 0) Int.MAX_VALUE else time
        }

        val firstBus = sortedBusInfos.first()
        val (busNo, stationName, busInfo) = firstBus
        val remainingTime = parseEstimatedTime(busInfo.estimatedTime)

        val allBusesSummary = if (notificationDisplayMode == DISPLAY_MODE_ALL_BUSES) {
            formatAllArrivals(sortedBusInfos)
        } else null

        showOngoingBusTracking(
            busNo = busNo,
            stationName = stationName,
            remainingMinutes = remainingTime,
            currentStation = busInfo.currentStation,
            isUpdate = true,
            notificationId = ONGOING_NOTIFICATION_ID,
            allBusesSummary = allBusesSummary
        )

        updateFlutterUI(busNo, busInfo.routeId, remainingTime, busInfo.currentStation)
    }

    private fun updateEmptyNotification() {
        if (monitoredRoutes.isNotEmpty()) {
            val firstRoute = monitoredRoutes.entries.first()
            val routeId = firstRoute.key
            val stationName = firstRoute.value.second

            showOngoingBusTracking(
                busNo = routeId,
                stationName = stationName,
                remainingMinutes = -1,
                currentStation = "도착 정보 없음",
                isUpdate = true,
                notificationId = ONGOING_NOTIFICATION_ID
            )
        }
    }

    private fun updateFlutterUI(busNo: String, routeId: String, remainingTime: Int, currentStation: String?) {
        try {
            _methodChannel?.invokeMethod("onBusLocationUpdated", mapOf(
                "busNo" to busNo,
                "routeId" to routeId,
                "remainingMinutes" to remainingTime,
                "currentStation" to (currentStation ?: "정보 없음")
            ))
        } catch (e: Exception) {
            Log.e(TAG, "❌ Flutter 업데이트 오류: ${e.message}")
        }
    }

    private fun parseEstimatedTime(estimatedTime: String): Int {
        return when {
            estimatedTime == "-" || estimatedTime == "운행종료" -> -1
            estimatedTime.contains("분") -> {
                val minutesStr = estimatedTime.replace("[^0-9]".toRegex(), "")
                minutesStr.toIntOrNull() ?: -1
            }
            else -> -1
        }
    }

    private fun showBusArrivalNotification(stationName: String, busNo: String, remainingTime: Int) {
        try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channelId = CHANNEL_BUS_ALERTS
            val notificationId = System.currentTimeMillis().toInt()

            val title = "🚌 $busNo 번 버스가 곧 도착합니다!"
            val content = "$stationName 정류장\n" +
                    (if (remainingTime == 0) "⏰ 곧 도착" else "⏰ 남은 시간: $remainingTime 분")

            val style = NotificationCompat.BigTextStyle()
                .setBigContentTitle(title)
                .bigText(content)

            val notification = NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.drawable.ic_bus_notification)
                .setContentTitle(title)
                .setContentText(content)
                .setStyle(style)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setVibrate(longArrayOf(0, 500, 200, 500))
                .build()

            notificationManager.notify(notificationId, notification)
            Log.d(TAG, "🔔 알림 표시됨: $busNo 번 버스 (남은 시간: $remainingTime 분)")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 알림 표시 중 오류: ${e.message}")
        }
    }

    fun addMonitoredRoute(routeId: String, stationId: String, stationName: String) {
        Log.d(TAG, "🔔 모니터링 노선 추가 요청: routeId=$routeId, stationId=$stationId, stationName=$stationName")

        if (routeId.isEmpty() || stationId.isEmpty() || stationName.isEmpty()) {
            Log.e(TAG, "🔔 유효하지 않은 파라미터: routeId=$routeId, stationId=$stationId, stationName=$stationName")
            return
        }

        monitoredRoutes[routeId] = Pair(stationId, stationName)
        Log.d(TAG, "🔔 모니터링 노선 추가 완료: routeId=$routeId, stationId=$stationId, stationName=$stationName")
        Log.d(TAG, "🔔 현재 모니터링 중인 노선 수: ${monitoredRoutes.size}개")

        if (!isInTrackingMode) { // 수정: _isInTrackingMode 대신 getter 사용
            registerBusArrivalReceiver()
        }
    }

    fun getMonitoredRoutesCount(): Int {
        return monitoredRoutes.size
    }

    fun showNotification(
        id: Int,
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String? = null,
        payload: String? = null,
        isOngoing: Boolean = false,
        routeId: String? = null, // routeId 추가
        allBusesSummary: String? = null // 모든 버스 정보 요약 (allBuses 모드에서만 사용)
    ) {
        serviceScope.launch {
            try {
                Log.d(TAG, "🔔 알림 표시 시도: $busNo, $stationName, ${remainingMinutes}분, ID: $id")

                // 캐시된 버스 정보 가져오기
                val cacheKey = "$busNo-$routeId"
                val cachedInfo = cachedBusInfo[cacheKey]

                // Add these logs:
                Log.d(TAG, "🔔 Notification Cache Key: $cacheKey")
                Log.d(TAG, "🔔 Cached BusInfo: $cachedInfo")

                // 캐시된 정보가 있으면 남은 시간을 업데이트
                val displayMinutes = cachedInfo?.estimatedTime?.replace("[^0-9]".toRegex(), "")?.toIntOrNull() ?: remainingMinutes

                // 알림 표시 모드에 따라 제목 설정
                val title = if (allBusesSummary != null) {
                    "$stationName 정류장 버스 정보"
                } else if (isOngoing) {
                    "${busNo}번 버스 실시간 추적"
                } else {
                    "${busNo}번 버스 승차 알림"
                }

                // 알림 내용 설정
                var body = if (allBusesSummary != null) {
                    // allBuses 모드일 때는 첫 번째 버스 정보만 표시 (축소된 뷰용)
                    "${busNo}번: ${if (displayMinutes <= 0) "곧 도착" else "약 ${displayMinutes}분 후 도착"}"
                } else if (isOngoing) {
                    if (displayMinutes <= 0) {
                        "$stationName 정류장에 곧 도착합니다!"
                    } else {
                        "$stationName 정류장까지 약 ${displayMinutes}분 남았습니다." +
                        if (!currentStation.isNullOrEmpty()) " (현재 위치: $currentStation)" else ""
                    }
                } else {
                    "$stationName 정류장 - 약 ${displayMinutes}분 후 도착" +
                    if (!currentStation.isNullOrEmpty()) " (현재 위치: $currentStation)" else ""
                }

                // TTS 사용이 설정되어 있고 알람 상황이면 TTS 발화 (지속적인 추적이 아닌 경우)
                if (useTextToSpeech && !isOngoing) {
                    val ttsMessage = if (displayMinutes <= 0) {
                        "$busNo 번 버스가 $stationName 정류장에 곧 도착합니다."
                    } else {
                        "$busNo 번 버스가 $stationName 정류장에 약 ${displayMinutes}분 후 도착 예정입니다."
                    }

                    // 버스 정보를 맵으로 구성
                    val busInfoMap = mapOf<String, Any?>(
                        "busNo" to busNo,
                        "stationName" to stationName,
                        "remainingMinutes" to displayMinutes,
                        "currentStation" to currentStation,
                        "routeId" to routeId
                    )

                    Log.d(TAG, "🔊 TTS 알람 발화 시도: $ttsMessage")
                    // 이어폰 전용 모드로 설정 (TTS 알람은 이어폰에서만 동작)
                    speakTts(ttsMessage, earphoneOnly = true, showNotification = true, busInfo = busInfoMap)
                }

                val intent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                    putExtra("NOTIFICATION_ID", id)
                    putExtra("PAYLOAD", payload)
                }
                val pendingIntent = PendingIntent.getActivity(
                    context,
                    id,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                val dismissIntent = Intent(context, NotificationDismissReceiver::class.java).apply {
                    putExtra("NOTIFICATION_ID", id)
                }
                val dismissPendingIntent = PendingIntent.getBroadcast(
                    context,
                    id + 1000,
                    dismissIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                val builder = NotificationCompat.Builder(context, CHANNEL_BUS_ALERTS)
                    .setSmallIcon(R.drawable.ic_bus_notification)
                    .setContentTitle(title)
                    .setContentText(body)
                    .setStyle(NotificationCompat.BigTextStyle().bigText(
                        if (allBusesSummary != null) {
                            // allBuses 모드일 때는 모든 버스 정보 표시 (확장된 뷰용)
                            "정류장: $stationName\n\n🚌 도착 예정 버스 정보\n$allBusesSummary"
                        } else {
                            body
                        }
                    ))
                    .setPriority(if (isOngoing) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_MAX)
                    .setCategory(if (allBusesSummary != null) NotificationCompat.CATEGORY_STATUS else if (isOngoing) NotificationCompat.CATEGORY_SERVICE else NotificationCompat.CATEGORY_ALARM)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setColor(ContextCompat.getColor(context, R.color.notification_color))
                    .setColorized(true)
                    .setAutoCancel(!isOngoing)
                    .setOngoing(isOngoing)
                    .setContentIntent(pendingIntent)
                    .addAction(R.drawable.ic_dismiss, "알람 종료", dismissPendingIntent)
                    .setFullScreenIntent(pendingIntent, true)

                // TTS를 사용하지 않을 때만 소리 설정
                if (!useTextToSpeech) {
                    builder.setSound(Uri.parse("android.resource://${context.packageName}/raw/$currentAlarmSound"))
                }

                // 진동 설정은 항상 유지
                builder.setVibrate(longArrayOf(0, 500, 200, 500, 200, 500))

                if (isOngoing) {
                    val progress = 100 - (if (displayMinutes > 30) 0 else displayMinutes * 3)
                    builder.setProgress(100, progress, false)
                        .setUsesChronometer(true)
                        .setWhen(System.currentTimeMillis())
                }

                with(NotificationManagerCompat.from(context)) {
                    try {
                        notify(id, builder.build())
                        Log.d(TAG, "🔔 알림 표시 완료: $id")
                    } catch (e: SecurityException) {
                        Log.e(TAG, "🔔 알림 권한 없음: ${e.message}", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "🔔 알림 표시 오류: ${e.message}", e)
            }
        }
    }

    /**
     * 버스가 지정된 정류장에 곧 도착할 때 표시되는 표준 알림입니다.
     * (예: 1정거장 전, 3분 이내 도착 시)
     */
    fun showOngoingBusTracking(
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String?,
        isUpdate: Boolean = false,
        notificationId: Int = ONGOING_NOTIFICATION_ID,
        allBusesSummary: String? = null
    ) {
        try {
            Log.d(TAG, "🚌 버스 추적 알림 표시 시도: $busNo, $stationName, ${remainingMinutes}분")

            val currentTime = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
            val title = "$busNo 번 버스 실시간 추적"
            val bodyText = if (remainingMinutes < 0) {
                "$busNo 번 버스 - 도착 정보 없음"
            } else if (remainingMinutes == 0) {
                "$busNo 번 버스가 $stationName 정류장에 곧 도착합니다!"
            } else {
                "$busNo 번 버스가 $stationName 정류장까지 약 $remainingMinutes 분 남았습니다." +
                (if (!currentStation.isNullOrEmpty()) "\n현재 위치: $currentStation" else "")
            }

            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                putExtra("NOTIFICATION_ID", notificationId)
                putExtra("BUS_NUMBER", busNo)
                putExtra("STATION_NAME", stationName)
            }

            val pendingIntent = PendingIntent.getActivity(
                context,
                notificationId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val stopTrackingIntent = Intent(context, StationTrackingService::class.java).apply {
                action = StationTrackingService.ACTION_STOP_TRACKING
            }
            val stopTrackingPendingIntent = PendingIntent.getService(
                context,
                notificationId + 1,
                stopTrackingIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = NotificationCompat.Builder(context, CHANNEL_BUS_ONGOING)
                .setSmallIcon(R.drawable.ic_bus_notification)
                .setContentTitle(title)
                .setContentText(bodyText)
                .setStyle(NotificationCompat.BigTextStyle().bigText(bodyText))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setColor(ContextCompat.getColor(context, R.color.tracking_color))
                .setColorized(true)
                .setOngoing(true)
                .setAutoCancel(false)
                .setOnlyAlertOnce(true)
                .setContentIntent(pendingIntent)
                .addAction(R.drawable.ic_stop, "추적 중지", stopTrackingPendingIntent)
                .setWhen(System.currentTimeMillis())
                .setShowWhen(true)

            // 진행률 표시 (0-100)
            val progress = if (remainingMinutes < 0) {
                0
            } else if (remainingMinutes > 30) {
                0
            } else if (remainingMinutes == 0) {
                100
            } else {
                ((30 - remainingMinutes).toDouble() / 30 * 100).toInt()
            }
            builder.setProgress(100, progress, false)

            val notificationManager = NotificationManagerCompat.from(context)
            try {
                if (isUpdate) {
                    notificationManager.notify(notificationId, builder.build())
                    Log.d(TAG, "🚌 버스 추적 알림 업데이트: $busNo, 위치: ${currentStation ?: "정보 없음"}")
                } else {
                    startForeground(notificationId, builder.build())
                    Log.d(TAG, "🚌 버스 추적 알림 시작: $busNo")
                }
            } catch (e: SecurityException) {
                Log.e(TAG, "🚌 알림 권한 없음: ${e.message}")
                throw e
            }
        } catch (e: Exception) {
            Log.e(TAG, "🚌 버스 추적 알림 오류: ${e.message}", e)
            throw e
        }
    }

    /**
     * 버스가 지정된 정류장에 곧 도착할 때 표시되는 표준 알림입니다.
     * (예: 1정거장 전, 3분 이내 도착 시)
     */
    fun showBusArrivingSoon(busNo: String, stationName: String, currentStation: String? = null) {
        try {
            Log.d(TAG, "🔔 [실행] 버스 곧 도착 알림 표시: $busNo, $stationName") // Log when this function is actually called
            val notificationId = System.currentTimeMillis().toInt()
            val title = "⚠️ $busNo 번 버스 정류장 도착 알림"
            var body = "🚏 $stationName 정류장에 도착했습니다. 곧 $stationName 에 도착합니다."
            if (!currentStation.isNullOrEmpty()) {
                body += " (현재 위치: $currentStation)"
            }

            // 기본 인텐트 설정
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                putExtra("NOTIFICATION_ID", notificationId)
                putExtra("BUS_NUMBER", busNo)
                putExtra("STATION_NAME", stationName)
                putExtra("SHOW_ARRIVING", true)
            }

            val pendingIntent = PendingIntent.getActivity(
                context, notificationId, intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = NotificationCompat.Builder(context, CHANNEL_BUS_ALERTS)
                .setSmallIcon(R.drawable.ic_bus_notification)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setAutoCancel(true)
                .setColor(ContextCompat.getColor(context, android.R.color.holo_red_light))
                .setColorized(true)
                .setContentIntent(pendingIntent)

            // TTS 사용하지 않을 경우만 소리 및 진동 설정
            if (!useTextToSpeech) {
                builder.setSound(Uri.parse("android.resource://${context.packageName}/raw/$currentAlarmSound"))
                builder.setVibrate(longArrayOf(0, 500, 200, 500, 200, 500))
            }

            NotificationManagerCompat.from(context).notify(notificationId, builder.build())
            Log.d(TAG, "🔔 버스 곧 도착 알림 표시 완료: $notificationId")
        } catch (e: Exception) {
            Log.e(TAG, "🔔 버스 곧 도착 알림 표시 오류: ${e.message}")
        }
    }

    /**
     * 지정된 노선 및 정류장에 대한 버스 도착 정보를 TTS로 안내하고,
     * 알람 설정된 버스 또는 모든 버스 모드에 따라 정보를 조회하고 알림을 업데이트합니다.
     */
    fun startTtsTracking(routeId: String, stationId: String, busNo: String, stationName: String) {
        // BusApiService 초기화 확인
        if (!::busApiService.isInitialized) {
            Log.d(TAG, "🚌 BusApiService 초기화 시도 (startTtsTracking)")
            try {
                busApiService = BusApiService(context)
                Log.d(TAG, "🚌 BusApiService 초기화 성공")
            } catch (e: Exception) {
                Log.e(TAG, "🚌 BusApiService 초기화 실패: ${e.message}")
                return
            }
        }

        if (isTtsTrackingActive) {
            Log.d(TAG, "🔊 기존 TTS 추적 작업이 실행 중입니다. 중지 후 재시작합니다.")
            stopTtsTracking(routeId = routeId, stationId = stationId) // Pass IDs to clear flag if needed
        }

        // Foreground 서비스 시작 확인
        if (!isInTrackingMode) {
            registerBusArrivalReceiver()
        }

        // TTS 추적 시작 전, 해당 알림 플래그 초기화 (선택적, 새 추적 시작 시 초기화)
        val notificationKey = "${routeId}_${stationId}"
        // arrivingSoonNotified.remove(notificationKey) // Start fresh for new tracking session
        // Log.d(TAG, "🔊 새 추적 시작, '${notificationKey}' 곧 도착 알림 플래그 초기화")

        ttsJob = serviceScope.launch(Dispatchers.IO) {
            isTtsTrackingActive = true
            Log.d(TAG, "🔊 TTS 추적 시작: $busNo, $stationName (모드: $notificationDisplayMode)")

            while (isTtsTrackingActive && isActive) {
                try {
                    var busDataForNotification: Map<String, Any?>? = null
                    var ttsMessage: String? = null
                    var shouldTriggerArrivingSoon = false
                    var currentBusNoForSoon = busNo // Default to the alarmed bus
                    var currentStationForSoon = "정보 없음" // Default

                    // Reload settings in each loop iteration to catch changes
                    loadSettings()

                    // BusApiService 초기화 확인
                    if (!::busApiService.isInitialized) {
                        Log.e(TAG, "🚌 BusApiService가 초기화되지 않았습니다. TTS 추적을 중단합니다.")
                        stopTtsTracking(forceStop = true)
                        break
                    }

                    if (notificationDisplayMode == DISPLAY_MODE_ALL_BUSES) {
                        // --- 모든 버스 모드 ---
                        Log.d(TAG, "🚌 [모든 버스 모드] 정보 조회 중... ($stationId)")
                        val stationInfoJson = busApiService.getStationInfo(stationId) // Fetch all buses for the station
                        val allArrivals = parseStationInfo(stationInfoJson)

                        if (allArrivals.isNotEmpty()) {
                             // Find the soonest arriving bus for primary display
                            val soonestBus = allArrivals.minByOrNull { it.estimatedMinutes ?: Int.MAX_VALUE }
                            if (soonestBus != null) {
                                // 모든 버스 정보 요약 생성
                                val allBusesSummary = formatParsedArrivals(allArrivals)

                                busDataForNotification = mapOf(
                                    "busNo" to soonestBus.routeNo, // Use soonest bus no
                                    "stationName" to stationName,
                                    "remainingMinutes" to (soonestBus.estimatedMinutes ?: -1),
                                    "currentStation" to soonestBus.currentStation,
                                    "allBusesSummary" to allBusesSummary,
                                    "isAllBusesMode" to true
                                )
                                currentBusNoForSoon = soonestBus.routeNo
                                currentStationForSoon = soonestBus.currentStation ?: "정보 없음"

                                // Generate TTS for the soonest bus
                                ttsMessage = generateTtsMessage(soonestBus.routeNo, stationName, soonestBus.estimatedMinutes, soonestBus.currentStation, soonestBus.remainingStops)
                                shouldTriggerArrivingSoon = (soonestBus.remainingStops == 1 && (soonestBus.estimatedMinutes ?: -1) <= 3)
                            } else {
                                busDataForNotification = createNoInfoData(routeId, stationName)
                                ttsMessage = "$stationName 에 도착 예정인 버스 정보가 없습니다."
                            }
                        } else {
                            busDataForNotification = createNoInfoData(routeId, stationName)
                            ttsMessage = "$stationName 에 도착 예정인 버스 정보가 없습니다."
                        }

                    } else {
                        // --- 알람 설정된 버스 모드 (기존 로직) ---
                        Log.d(TAG, "🚌 [알람 버스 모드] 정보 조회 중... ($routeId @ $stationId)")
                        try {
                            val arrivalInfo = busApiService.getBusArrivalInfoByRouteId(stationId, routeId)
                            val firstBus = arrivalInfo?.bus?.firstOrNull()

                            if (firstBus != null) {
                                val remaining = firstBus.estimatedTime.filter { it.isDigit() }.toIntOrNull() ?: -1
                                val currentStation = firstBus.currentStation ?: "정보 없음"
                                val busStopCount = firstBus.remainingStations.replace("[^0-9]".toRegex(), "").toIntOrNull() ?: -1

                                busDataForNotification = mapOf(
                                    "busNo" to busNo, // Use the alarmed bus no
                                    "stationName" to stationName,
                                    "remainingMinutes" to remaining,
                                    "currentStation" to currentStation
                                )
                                currentBusNoForSoon = busNo
                                currentStationForSoon = currentStation

                                ttsMessage = generateTtsMessage(busNo, stationName, remaining, currentStation, busStopCount)
                                shouldTriggerArrivingSoon = (busStopCount == 1 && remaining <= 3)
                            } else {
                                busDataForNotification = createNoInfoData(busNo, stationName)
                                ttsMessage = "$busNo 번 버스 도착 정보가 없습니다."
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ TTS 추적 중 오류: ${e.message}", e)
                            busDataForNotification = createNoInfoData(busNo, stationName)
                            ttsMessage = "$busNo 번 버스 정보 조회 중 오류가 발생했습니다."
                        }
                    }

                    // --- 공통 로직: 알림 업데이트 및 TTS 발화 ---
                    if (busDataForNotification != null) {
                        val bNo = busDataForNotification["busNo"] as? String ?: ""
                        val sName = busDataForNotification["stationName"] as? String ?: ""
                        val rMins = busDataForNotification["remainingMinutes"] as? Int ?: -1
                        val cStation = busDataForNotification["currentStation"] as? String
                        val isAllBusesMode = busDataForNotification["isAllBusesMode"] as? Boolean ?: false
                        val allBusesSummary = if (isAllBusesMode) busDataForNotification["allBusesSummary"] as? String else null

                        // Update the single ongoing notification
                        showOngoingBusTracking(
                            busNo = bNo,
                            stationName = sName,
                            remainingMinutes = rMins,
                            currentStation = cStation,
                            isUpdate = true,
                            notificationId = ONGOING_NOTIFICATION_ID,
                            allBusesSummary = allBusesSummary
                        )
                        Log.d(TAG, "🚌 진행 중 알림 업데이트: $bNo, 남은 시간: $rMins, 현재 위치: $cStation")
                    }

                    if (ttsMessage != null) {
                        val currentNotificationKey = "${routeId}_${stationId}" // Key for arriving soon flag

                        withContext(Dispatchers.Main) {
                            speakTts(ttsMessage, earphoneOnly = false, showNotification = false, busInfo = null)

                            if (shouldTriggerArrivingSoon) {
                                if (!arrivingSoonNotified.contains(currentNotificationKey)) {
                                    Log.d(TAG, "✅ '곧 도착' 조건 만족 & 첫 알림: $currentNotificationKey (버스: $currentBusNoForSoon)")
                                    arrivingSoonNotified.add(currentNotificationKey)
                                    showBusArrivingSoon(currentBusNoForSoon, stationName, currentStationForSoon)
                                    stopTtsTracking(routeId = routeId, stationId = stationId)
                                } else {
                                    Log.d(TAG, "☑️ '곧 도착' 조건 만족했으나 이미 알림: $currentNotificationKey")
                                }
                            }
                        }
                    } else {
                        Log.d(TAG, "🔊 TTS 메시지 생성 안됨")
                    }

                    delay(30_000) // Check every 30 seconds

                } catch (e: Exception) {
                    if (e is CancellationException) {
                       Log.d(TAG, "🔊 TTS 추적 작업 취소됨")
                       isTtsTrackingActive = false // Ensure state is updated on cancellation
                    } else {
                       Log.e(TAG, "❌ TTS 추적 중 오류: ${e.message}", e)
                    }
                    // Don't stop tracking automatically on general errors, let it retry or be stopped manually
                    // Removed: stopTtsTracking(routeId = routeId, stationId = stationId)
                    isTtsTrackingActive = false // Ensure tracking stops if error is unrecoverable or on cancellation
                    break // Exit loop on error or cancellation
                }
            }
             Log.d(TAG, "🔊 TTS 추적 루프 종료: $busNo, $stationName")
             isTtsTrackingActive = false // Ensure state is correct after loop finishes
        }
    }

    fun cancelNotification(id: Int) {
        try {
            NotificationManagerCompat.from(context).cancel(id)
            Log.d(TAG, "🔔 알림 취소 완료: $id")
        } catch (e: Exception) {
            Log.e(TAG, "🔔 알림 취소 오류: ${e.message}", e)
        }
    }

    fun cancelOngoingTracking() {
        try {
            NotificationManagerCompat.from(context).cancel(ONGOING_NOTIFICATION_ID)
            _methodChannel?.invokeMethod("onTrackingCancelled", null)
            Log.d(TAG, "🚌 지속적인 추적 알림 취소 완료")
        } catch (e: Exception) {
            Log.e(TAG, "🚌 지속적인 추적 알림 취소 오류: ${e.message}", e)
        }
    }

    fun cancelAllNotifications() {
        try {
            NotificationManagerCompat.from(context).cancelAll()
            Log.d(TAG, "🔔 모든 알림 취소 완료")
        } catch (e: Exception) {
            Log.e(TAG, "🔔 모든 알림 취소 오류: ${e.message}", e)
        }
    }

    fun stopTracking() {
        cancelOngoingTracking()
        try {
            _methodChannel?.invokeMethod("stopBusMonitoringService", null)
            monitoringJob?.cancel()
            monitoredRoutes.clear()
            timer.cancel()
            isInTrackingModePrivate = false // 수정: _isInTrackingMode 대신 사용
            Log.d(TAG, "stopTracking() 호출됨: 버스 추적 서비스 중지됨")
        } catch (e: Exception) {
            Log.e(TAG, "버스 모니터링 서비스 중지 오류: ${e.message}", e)
        }
    }

    /**
     * 강제로 TTS 추적을 중지할지 여부
     * routeId: 추적 중인 노선 ID (곧 도착 플래그 제거용)
     * stationId: 추적 중인 정류장 ID (곧 도착 플래그 제거용)
     */
    fun stopTtsTracking(forceStop: Boolean = false, routeId: String? = null, stationId: String? = null) {
        if (!isTtsTrackingActive && !forceStop) {
            Log.d(TAG, "🔊 TTS 추적이 이미 중지된 상태입니다. 강제 중지 옵션 없음.")
            return
        }

        try {
            ttsJob?.cancel() // Cancel the coroutine job first
            ttsEngine?.stop()
            isTtsTrackingActive = false
            ttsJob = null

            // 플래그 제거 로직 추가
            if (routeId != null && stationId != null) {
                val notificationKey = "${routeId}_${stationId}"
                if (arrivingSoonNotified.remove(notificationKey)) {
                    Log.d(TAG, "🔊 TTS 추적 중지, '${notificationKey}' 곧 도착 알림 플래그 제거됨")
                }
            } else {
                 Log.d(TAG, "🔊 TTS 추적 중지 (routeId/stationId 정보 없음, 플래그 제거 안함)")
            }

            Log.d(TAG, "🔊 TTS 추적 중지 완료 (강제 중지: $forceStop)")
        } catch (e: Exception) {
            Log.e(TAG, "❌ TTS 추적 중지 오류: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        stopTtsTracking()
        ttsEngine?.shutdown()
        ttsEngine = null
        monitoringJob?.cancel()
        timer.cancel()
        serviceScope.cancel()
        Log.d(TAG, "🔔 BusAlertService 종료")
    }

    // 캐시된 버스 정보를 가져오는 메서드
    fun getCachedBusInfo(busNo: String, routeId: String): BusInfo? {
        val cacheKey = "$busNo-$routeId"
        val cachedInfo = cachedBusInfo[cacheKey]

        // 캐시된 정보가 있고, 최신 정보인지 확인 (10분 이내)
        if (cachedInfo != null) {
            val lastUpdateTime = cachedInfo.lastUpdateTime ?: System.currentTimeMillis()
            val currentTime = System.currentTimeMillis()
            val elapsedMinutes = (currentTime - lastUpdateTime) / (1000 * 60)

            // 10분 이상 지난 정보는 만료된 것으로 간주
            if (elapsedMinutes > 10) {
                Log.d(TAG, "🚌 캐시된 버스 정보 만료됨: $cacheKey, 경과 시간: ${elapsedMinutes}분")
                return null
            }

            // 남은 시간 계산 (경과 시간만큼 차감)
            val originalEstimatedTime = cachedInfo.estimatedTime
            if (originalEstimatedTime.isNotEmpty() && originalEstimatedTime != "-" && originalEstimatedTime != "운행종료") {
                val originalMinutes = originalEstimatedTime.replace("[^0-9]".toRegex(), "").toIntOrNull() ?: 0
                if (originalMinutes > 0) {
                    val adjustedMinutes = (originalMinutes - elapsedMinutes).coerceAtLeast(0)
                    val adjustedEstimatedTime = if (adjustedMinutes <= 0) "곧 도착" else "${adjustedMinutes}분"

                    // 조정된 시간으로 새 BusInfo 객체 생성
                    return BusInfo(
                        busNumber = cachedInfo.busNumber,
                        routeId = cachedInfo.routeId,
                        estimatedTime = adjustedEstimatedTime,
                        currentStation = cachedInfo.currentStation,
                        remainingStations = cachedInfo.remainingStations,
                        lastUpdateTime = lastUpdateTime
                    )
                }
            }
        }

        return cachedInfo
    }

    // Renamed from loadAlarmSoundSettings to loadSettings for clarity
    private fun loadSettings() {
        try {
            val prefs = context.getSharedPreferences("bus_alert_settings", Context.MODE_PRIVATE)
            currentAlarmSound = prefs.getString(PREF_ALARM_SOUND_FILENAME, DEFAULT_ALARM_SOUND) ?: DEFAULT_ALARM_SOUND
            useTextToSpeech = prefs.getBoolean(PREF_ALARM_USE_TTS, true)
            audioOutputMode = prefs.getInt(PREF_SPEAKER_MODE, OUTPUT_MODE_AUTO)
            notificationDisplayMode = prefs.getInt(PREF_NOTIFICATION_DISPLAY_MODE_KEY, DISPLAY_MODE_ALARMED_ONLY)
            ttsVolume = prefs.getFloat(PREF_TTS_VOLUME, 1.0f)
            
            // AudioManager 초기화
            audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            
            Log.d(TAG, "설정 로드 완료 - 알람음: $currentAlarmSound, TTS: $useTextToSpeech, 볼륨: ${ttsVolume * 100}%")
        } catch (e: Exception) {
            Log.e(TAG, "설정 로드 중 오류: ${e.message}")
        }
    }

    // 알람음 설정
    fun setAlarmSound(filename: String, useTts: Boolean = false) {
        try {
            currentAlarmSound = if (filename.isBlank()) {
                // 빈 파일명은 무음 또는 진동만 사용
                ""
            } else {
                filename
            }

            useTextToSpeech = useTts

            // SharedPreferences에 저장
            val sharedPreferences = context.getSharedPreferences(PREF_ALARM_SOUND, Context.MODE_PRIVATE)
            sharedPreferences.edit()
                .putString(PREF_ALARM_SOUND_FILENAME, currentAlarmSound)
                .putBoolean(PREF_ALARM_USE_TTS, useTextToSpeech)
                .apply()

            // 알림 채널 재생성 (알람음 변경을 적용하기 위함)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                createNotificationChannels()
            }

            Log.d(TAG, "🔔 알람음 설정 완료: $currentAlarmSound, TTS 사용: $useTextToSpeech")
        } catch (e: Exception) {
            Log.e(TAG, "🔔 알람음 설정 오류: ${e.message}", e)
        }
    }

    // 오디오 모드 설정 함수 추가
    fun setAudioOutputMode(mode: Int) {
        try {
            if (mode in OUTPUT_MODE_HEADSET..OUTPUT_MODE_AUTO) {
                audioOutputMode = mode

                // SharedPreferences에 저장
                val sharedPreferences = context.getSharedPreferences(PREF_ALARM_SOUND, Context.MODE_PRIVATE)
                sharedPreferences.edit()
                    .putInt(PREF_SPEAKER_MODE, audioOutputMode)
                    .apply()

                Log.d(TAG, "🔔 오디오 출력 모드 설정 완료: $audioOutputMode")
            } else {
                Log.e(TAG, "🔔 잘못된 오디오 출력 모드: $mode")
            }
        } catch (e: Exception) {
            Log.e(TAG, "🔔 오디오 출력 모드 설정 오류: ${e.message}", e)
        }
    }

    // 오디오 모드 가져오기 함수 추가 (MainActivity에서 로깅용으로 사용)
    fun getAudioOutputMode(): Int {
        return audioOutputMode
    }

    // 이어폰 연결 상태 확인 함수
    private fun isHeadsetConnected(): Boolean {
        try {
            val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as android.media.AudioManager
            val isWiredHeadsetOn = audioManager.isWiredHeadsetOn
            val isBluetoothA2dpOn = audioManager.isBluetoothA2dpOn

            val isConnected = isWiredHeadsetOn || isBluetoothA2dpOn
            Log.d(TAG, "🎧 이어폰 연결 상태: 유선=${isWiredHeadsetOn}, 블루투스=${isBluetoothA2dpOn}")

            return isConnected
        } catch (e: Exception) {
            Log.e(TAG, "🎧 이어폰 연결 상태 확인 오류: ${e.message}", e)
            return false  // 오류 시 연결되지 않은 것으로 간주
        }
    }

    // TTS 발화 함수 수정 (private -> public)
    fun speakTts(text: String, earphoneOnly: Boolean = false, showNotification: Boolean = false, busInfo: Map<String, Any?>? = null) {
        if (ttsEngine != null && ttsEngine?.isLanguageAvailable(Locale.KOREAN) == TextToSpeech.LANG_AVAILABLE) {
            try {
                val message = text

                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                
                // 자동 알람인지 확인 (busInfo가 null이 아니고 isAutoAlarm이 true인 경우)
                val isAutoAlarm = busInfo?.get("isAutoAlarm") as? Boolean ?: false
                
                Log.d(TAG, "🔊 TTS 발화 시도: \"$message\", 자동 알람: $isAutoAlarm")
                
                // 이어폰 전용 모드인 경우 이어폰 연결 상태 확인
                val isHeadsetConnected = isHeadsetConnected()
                
                // 일반 승차 알람에서 earphoneOnly가 true인 경우 이어폰이 연결되어 있지 않으면 발화 중지
                if (earphoneOnly && !isAutoAlarm && !isHeadsetConnected) {
                    Log.d(TAG, "🎧 이어폰이 연결되어 있지 않아 일반 승차 알람 TTS 발화를 중지합니다.")
                    return
                }
                
                // 자동 알람인 경우 스피커로 강제 설정, 그 외에는 설정된 모드 사용
                val useSpeaker = if (isAutoAlarm) {
                    Log.d(TAG, "🔊 자동 알람 감지! 스피커 모드로 강제 설정")
                    true // 자동 알람은 항상 스피커 사용
                } else if (earphoneOnly) {
                    false // 이어폰 전용 모드는 항상 이어폰 사용 (이어폰이 연결되어 있는 경우만 여기까지 옴)
                } else {
                    when (audioOutputMode) {
                        OUTPUT_MODE_SPEAKER -> true
                        OUTPUT_MODE_HEADSET -> false
                        OUTPUT_MODE_AUTO -> !isHeadsetConnected
                        else -> !isHeadsetConnected
                    }
                }

                // 자동 알람인 경우 STREAM_ALARM을 사용하여 볼륨이 무음 모드에서도 들리도록 함
                val streamType = if (isAutoAlarm || useSpeaker) AudioManager.STREAM_ALARM else AudioManager.STREAM_MUSIC

                // 자동 알람일 경우 볼륨 최대로 설정
                val actualVolume = if (isAutoAlarm) {
                    Log.d(TAG, "🔊 자동 알람 - 볼륨 최대로 설정 (100%)")
                    1.0f // 최대 볼륨으로 설정
                } else {
                    ttsVolume
                }

                // 볼륨 값 조정 시도 (자동 알람일 때)
                if (isAutoAlarm) {
                    try {
                        // 현재 오디오 스트림의 최대 볼륨 가져오기
                        val maxVolume = audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)
                        
                        // 자동 알람인 경우 최대 볼륨으로 설정
                        audioManager.setStreamVolume(
                            AudioManager.STREAM_ALARM,
                            maxVolume,
                            0  // 볼륨 변경 시 사운드 재생하지 않음
                        )
                        
                        Log.d(TAG, "🔊 자동 알람 시스템 볼륨 조정: $maxVolume/$maxVolume (100%)")
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ 볼륨 조정 오류: ${e.message}")
                    }
                }

                Log.d(TAG, "🔊 TTS 발화 시도: \"$message\" (Stream: ${if(streamType == AudioManager.STREAM_ALARM) "ALARM" else "MUSIC"}, 볼륨: ${actualVolume * 100}%, 자동알람: $isAutoAlarm, 스피커 사용: $useSpeaker, 이어폰 연결됨: $isHeadsetConnected)")

                val params = Bundle().apply {
                    putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, "tts_${System.currentTimeMillis()}")
                    putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, streamType)
                    putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, actualVolume) // 볼륨 설정 적용
                }

                // 추가: 포커스 관련 처리
                val audioFocusRequest = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    val focusDuration = if (isAutoAlarm) AudioManager.AUDIOFOCUS_GAIN_TRANSIENT else AudioManager.AUDIOFOCUS_GAIN
                    
                    AudioFocusRequest.Builder(focusDuration)
                        .setAudioAttributes(AudioAttributes.Builder()
                            .setUsage(if (isAutoAlarm) AudioAttributes.USAGE_ALARM else AudioAttributes.USAGE_ASSISTANCE_ACCESSIBILITY)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                            .build())
                        .setAcceptsDelayedFocusGain(true)
                        .setOnAudioFocusChangeListener {
                            when (it) {
                                AudioManager.AUDIOFOCUS_LOSS -> {
                                    ttsEngine?.stop()
                                    Log.d(TAG, "🔊 오디오 포커스 손실로 TTS 중지")
                                }
                                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                                    ttsEngine?.stop()
                                    Log.d(TAG, "🔊 일시적 오디오 포커스 손실로 TTS 중지")
                                }
                            }
                        }
                        .build()
                } else null

                // 오디오 포커스 요청
                val focusResult = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && audioFocusRequest != null) {
                    audioManager.requestAudioFocus(audioFocusRequest)
                } else {
                    val onAudioFocusChangeListener = OnAudioFocusChangeListener { focusChange ->
                        when (focusChange) {
                            AudioManager.AUDIOFOCUS_LOSS -> {
                                ttsEngine?.stop()
                                Log.d(TAG, "🔊 오디오 포커스 손실로 TTS 중지")
                            }
                            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT -> {
                                ttsEngine?.stop()
                                Log.d(TAG, "🔊 일시적 오디오 포커스 손실로 TTS 중지")
                            }
                        }
                    }
                    audioManager.requestAudioFocus(
                        onAudioFocusChangeListener,
                        streamType,
                        if (isAutoAlarm) AudioManager.AUDIOFOCUS_GAIN_TRANSIENT else AudioManager.AUDIOFOCUS_GAIN
                    )
                }

                if (focusResult == AudioManager.AUDIOFOCUS_REQUEST_GRANTED) {
                    val utteranceId = params.getString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID)
                    ttsEngine?.speak(message, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
                    Log.d(TAG, "🔊 TTS speak() 호출됨. utteranceId: $utteranceId")

                    // 자동 알람인 경우 호출자에게 TTS 발화 성공 알림
                    // ...existing code...
                } else {
                    Log.e(TAG, "🔊 오디오 포커스 획득 실패: $focusResult")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ TTS 발화 중 오류 발생: ${e.message}", e)
            }
        } else {
            Log.e(TAG, "🔊 TTS 엔진 준비 안됨 또는 한국어 미지원")
        }
    }

    // Helper to generate TTS message
    private fun generateTtsMessage(busNo: String, stationName: String, remainingMinutes: Int?, currentStation: String?, remainingStops: Int?): String {
         return when {
            remainingMinutes == null || remainingMinutes < 0 -> "$busNo 번 버스 도착 정보가 없습니다."
            remainingStops == 1 && remainingMinutes <= 3 -> "$busNo 버스가 $stationName 정류장 앞 정류장에 도착했습니다. 곧 $stationName 에 도착합니다. 탑승 준비하세요."
            remainingMinutes == 0 -> "$busNo 버스가 $stationName 에 도착했습니다. 탑승하세요."
            else -> {
                val locationInfo = if (!currentStation.isNullOrEmpty() && currentStation != "정보 없음") " 현재 $currentStation 위치에서" else ""
                "$busNo 버스가$locationInfo $stationName 에 약 ${remainingMinutes}분 후 도착 예정입니다."
            }
        }
    }

    // Helper to create data when no bus info is found
    private fun createNoInfoData(defaultBusNo: String, stationName: String): Map<String, Any?> {
        return mapOf(
            "busNo" to defaultBusNo, // Show original bus/route if no info
            "stationName" to stationName,
            "remainingMinutes" to -1,
            "currentStation" to "정보 없음" // 도착 정보 없음 -> 정보 없음
        )
    }

    // Helper structure for parsed station info
    private data class ParsedArrivalInfo(
        val routeNo: String,
        val routeId: String,
        val estimatedMinutes: Int?,
        val currentStation: String?,
        val remainingStops: Int?
    )

    // Helper to parse the result of getStationInfo
    private fun parseStationInfo(jsonString: String): List<ParsedArrivalInfo> {
        val results = mutableListOf<ParsedArrivalInfo>()
        try {
            val jsonArray = JSONArray(jsonString) // Assuming getStationInfo returns a JSON array string
            for (i in 0 until jsonArray.length()) {
                val routeObj = jsonArray.getJSONObject(i)
                val arrList = routeObj.optJSONArray("arrList") ?: continue
                for (j in 0 until arrList.length()) {
                    val busObj = arrList.getJSONObject(j)
                    val minutes = busObj.optString("arrState", "").filter { it.isDigit() }.toIntOrNull()
                    val stops = busObj.optString("bsGap", "").filter { it.isDigit() }.toIntOrNull()
                    results.add(
                        ParsedArrivalInfo(
                            routeNo = busObj.optString("routeNo", routeObj.optString("routeNo")), // Use routeNo from bus or parent
                            routeId = busObj.optString("routeId", ""),
                            estimatedMinutes = minutes,
                            currentStation = busObj.optString("bsNm", null),
                            remainingStops = stops
                        )
                    )
                }
            }
            Log.d(TAG, "[parseStationInfo] 파싱 완료: ${results.size}개 도착 정보")
        } catch (e: Exception) {
            Log.e(TAG, "[parseStationInfo] JSON 파싱 오류: ${e.message}")
        }
        return results
    }

    // Helper to format all arrivals
    private fun formatAllArrivals(arrivals: List<Triple<String, String, BusInfo>>): String {
        if (arrivals.isEmpty()) return "도착 예정 버스 정보가 없습니다."

        return buildString {
            val displayCount = minOf(arrivals.size, 5)
            for (i in 0 until displayCount) {
                val (busNo, _, busInfo) = arrivals[i]
                val timeStr = when {
                    busInfo.estimatedTime == "-" || busInfo.estimatedTime == "운행종료" -> "정보 없음"
                    busInfo.estimatedTime.contains("곧") -> "곧 도착"
                    else -> busInfo.estimatedTime
                }
                append("${busNo}번: $timeStr")
                if (i < displayCount - 1) append("\n")
            }

            if (arrivals.size > displayCount) {
                append("\n외 ${arrivals.size - displayCount}대 더 있음")
            }
        }
    }

    // ParsedArrivalInfo 리스트를 포맷팅하는 함수
    private fun formatParsedArrivals(arrivals: List<ParsedArrivalInfo>): String {
        if (arrivals.isEmpty()) return "도착 예정 버스 정보가 없습니다."

        return buildString {
            val displayCount = minOf(arrivals.size, 5)
            for (i in 0 until displayCount) {
                val bus = arrivals[i]
                val timeStr = when (bus.estimatedMinutes) {
                    null -> "정보 없음"
                    0 -> "곧 도착"
                    else -> "${bus.estimatedMinutes}분"
                }
                append("${bus.routeNo}번: $timeStr")
                if (i < displayCount - 1) append("\n")
            }

            if (arrivals.size > displayCount) {
                append("\n외 ${arrivals.size - displayCount}대 더 있음")
            }
        }
    }

    // 볼륨 설정 함수 추가
    fun setTtsVolume(volume: Double) {
        try {
            // 볼륨 값을 0.0 ~ 1.0 범위로 제한
            ttsVolume = volume.toFloat().coerceIn(0f, 1f)
            
            // 현재 오디오 스트림의 최대 볼륨 가져오기
            val maxVolume = audioManager?.getStreamMaxVolume(AudioManager.STREAM_MUSIC) ?: 15
            
            // 설정된 볼륨 비율을 실제 볼륨 값으로 변환
            val targetVolume = (maxVolume * ttsVolume).toInt()
            
            // 오디오 스트림 볼륨 설정
            audioManager?.setStreamVolume(
                AudioManager.STREAM_MUSIC,
                targetVolume,
                0  // 볼륨 변경 시 사운드 재생하지 않음
            )
            
            // 설정 저장
            context.getSharedPreferences("bus_alert_settings", Context.MODE_PRIVATE)
                .edit()
                .putFloat(PREF_TTS_VOLUME, ttsVolume)
                .apply()
            
            Log.d(TAG, "TTS 볼륨 설정: ${ttsVolume * 100}% (시스템 볼륨: $targetVolume/$maxVolume)")
        } catch (e: Exception) {
            Log.e(TAG, "볼륨 설정 오류: ${e.message}")
        }
    }
}

class NotificationDismissReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val notificationId = intent.getIntExtra("NOTIFICATION_ID", -1)
        val stopTracking = intent.getBooleanExtra("STOP_TRACKING", false)

        if (notificationId != -1) {
            val busAlertService = BusAlertService.getInstance(context)
            busAlertService.cancelNotification(notificationId)
            if (stopTracking) {
                busAlertService.stopTracking()
            }
            Log.d("NotificationDismiss", "알림 ID: $notificationId 해제됨")
        }
    }
}

fun getNotificationChannels(context: Context): List<NotificationChannel>? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notificationChannels
    } else {
        null
    }
}

fun BusInfo.toMap(): Map<String, Any?> {
    return mapOf(
        "busNumber" to busNumber,
        "currentStation" to currentStation,
        "remainingStops" to remainingStops,
        "estimatedTime" to estimatedTime,
        "isLowFloor" to isLowFloor,
        "isOutOfService" to isOutOfService
    )
}

fun StationArrivalOutput.BusInfo.toMap(): Map<String, Any?> {
    return mapOf(
        "busNumber" to busNumber,
        "currentStation" to currentStation,
        "remainingStations" to remainingStations,
        "estimatedTime" to estimatedTime
    )
}

fun StationArrivalOutput.toMap(): Map<String, Any?> {
    return mapOf(
        "name" to name,
        "sub" to sub,
        "id" to id,
        "forward" to forward,
        "bus" to bus.map { it.toMap() }
    )
}

fun RouteStation.toMap(): Map<String, Any?> {
    return mapOf(
        "stationId" to stationId,
        "stationName" to stationName,
        "sequenceNo" to sequenceNo,
        "direction" to direction
    )
}