package com.example.daegu_bus_app

import io.flutter.plugin.common.MethodChannel
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
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
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.media.AudioManager
import android.os.Bundle


class BusAlertService : Service() {
    companion object {
        private const val TAG = "BusAlertService"
        private const val CHANNEL_BUS_ALERTS = "bus_alerts"
        private const val CHANNEL_BUS_ONGOING = "bus_ongoing"
        const val ONGOING_NOTIFICATION_ID = 10000
        
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
        
        // 알람음 설정 관련 상수
        private const val PREF_ALARM_SOUND = "alarm_sound_preference"
        private const val PREF_ALARM_SOUND_FILENAME = "alarm_sound_filename"
        private const val PREF_ALARM_USE_TTS = "alarm_use_tts"
        private const val DEFAULT_ALARM_SOUND = "alarm_sound"
        
        // 오디오 출력 모드 상수
        private const val PREF_SPEAKER_MODE = "speaker_mode"
        private const val OUTPUT_MODE_HEADSET = 0   // 이어폰 전용
        private const val OUTPUT_MODE_SPEAKER = 1   // 스피커 전용
        private const val OUTPUT_MODE_AUTO = 2      // 자동 감지 (기본값)
    }
    
    private var _methodChannel: MethodChannel? = null
    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var context: Context
    private lateinit var busApiService: BusApiService
    private var monitoringJob: Job? = null
    private val monitoredRoutes = mutableMapOf<String, Pair<String, String>>() // routeId -> (stationId, stationName)
    private val timer = Timer()
    private var ttsJob: Job? = null
    private var ttsEngine: android.speech.tts.TextToSpeech? = null
    private var isTtsTrackingActive = false // TTS 추적 상태 변수
    private val lastRemainingTimes = mutableMapOf<String, Int>()
    private val lastTimestamps = mutableMapOf<String, Long>()
    private val cachedBusInfo = mutableMapOf<String, BusInfo>() // 캐시된 버스 정보 (busNo + routeId -> BusInfo)

    // 추적 모드 상태 변수
    private var isInTrackingModePrivate = false
    val isInTrackingMode: Boolean
        get() = isInTrackingModePrivate || monitoredRoutes.isNotEmpty()

    // 현재 설정된 알람음
    private var currentAlarmSound = DEFAULT_ALARM_SOUND
    private var useTextToSpeech = false // TTS 사용 여부 플래그

    // 클래스 멤버 변수로 추가
    private var audioOutputMode = OUTPUT_MODE_AUTO  // 기본값: 자동 감지

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }

    override fun onCreate() {
        super.onCreate()
        busApiService = BusApiService(this)
    }
    
    fun initialize(context: Context? = null, flutterEngine: io.flutter.embedding.engine.FlutterEngine? = null) {
        try {
            val actualContext = context ?: this.context
            if (actualContext == null) {
                Log.e(TAG, "🔔 컨텍스트가 없어 알림 서비스를 초기화할 수 없습니다")
                return
            }
            this.context = actualContext.applicationContext
            Log.d(TAG, "🔔 알림 서비스 초기화")
            
            // 알람음 설정 불러오기
            loadAlarmSoundSettings()
            
            createNotificationChannels()
            checkNotificationPermission()
            
            if (flutterEngine != null) {
                _methodChannel = MethodChannel(
                    flutterEngine.dartExecutor.binaryMessenger,
                    "com.example.daegu_bus_app/bus_api"
                )
                Log.d(TAG, "🔌 메서드 채널 초기화 완료")
            } else {
                Log.d(TAG, "⚠️ FlutterEngine이 전달되지 않아 메서드 채널을 초기화할 수 없습니다")
            }

            initializeTts()
        } catch (e: Exception) {
            Log.e(TAG, "🔔 알림 서비스 초기화 중 오류 발생: ${e.message}", e)
        }
    }

    private fun initializeTts() {
        Log.d(TAG, "🔊 TTS 엔진 초기화 시작")
        try {
            if (ttsEngine != null) {
                Log.d(TAG, "🔊 기존 TTS 엔진 종료")
                ttsEngine?.shutdown()
                ttsEngine = null
            }
            
            ttsEngine = TextToSpeech(context) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    try {
                        // 한국어 설정
                        val result = ttsEngine?.setLanguage(Locale.KOREAN)
                        when (result) {
                            TextToSpeech.LANG_MISSING_DATA -> 
                                Log.e(TAG, "❌ 한국어 언어 데이터 없음")
                            TextToSpeech.LANG_NOT_SUPPORTED -> 
                                Log.e(TAG, "❌ 한국어가 지원되지 않음")
                            else -> 
                                Log.d(TAG, "🔊 한국어 설정 성공: $result")
                        }
                        
                        // 발화 속도 최적화 (1.0이 기본값)
                        ttsEngine?.setSpeechRate(1.0f)
                        // 피치 최적화 (1.0이 기본값)
                        ttsEngine?.setPitch(1.0f)
                        
                        // TTS 리스너 구현
                        ttsEngine?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
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
                        })
                        
                        Log.d(TAG, "🔊 TTS 엔진 초기화 성공")
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ TTS 언어 및 속성 설정 중 오류: ${e.message}", e)
                    }
                } else {
                    Log.e(TAG, "❌ TTS 엔진 초기화 실패: $status")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ TTS 엔진 초기화 중 오류 발생: ${e.message}", e)
        }
    }
        
    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                
                // 기존 채널 삭제 (알람음 변경 적용을 위해)
                notificationManager.deleteNotificationChannel(CHANNEL_BUS_ALERTS)
                
                val busAlertsChannel = NotificationChannel(
                    CHANNEL_BUS_ALERTS,
                    "Bus Alerts",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "버스 도착 알림"
                    enableLights(true)
                    lightColor = Color.RED
                    enableVibration(true)
                    
                    // 알람음 설정 적용
                    if (currentAlarmSound.isNotEmpty()) {
                        val soundUri = Uri.parse("android.resource://${context.packageName}/raw/$currentAlarmSound")
                        setSound(soundUri, AudioAttributes.Builder()
                            .setUsage(AudioAttributes.USAGE_ALARM)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build())
                    }
                }
                
                val busOngoingChannel = NotificationChannel(
                    CHANNEL_BUS_ONGOING,
                    "Bus Tracking",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "버스 위치 실시간 추적"
                    enableLights(false)
                    enableVibration(false)
                }
                
                notificationManager.createNotificationChannel(busAlertsChannel)
                notificationManager.createNotificationChannel(busOngoingChannel)
                Log.d(TAG, "🔔 알림 채널 생성 완료")
            } catch (e: Exception) {
                Log.e(TAG, "🔔 알림 채널 생성 오류: ${e.message}", e)
            }
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
            
            Log.d(TAG, "🔔 모니터링 중인 노선 목록: ${monitoredRoutes.keys.joinToString()}")
            
            monitoringJob?.cancel()
            monitoringJob = serviceScope.launch {
                timer.scheduleAtFixedRate(object : TimerTask() {
                    override fun run() {
                        serviceScope.launch {
                            checkBusArrivals()
                        }
                    }
                }, 0, 15000)
            }
            
            isInTrackingModePrivate = true // 수정: _isInTrackingMode 대신 사용
            _methodChannel?.invokeMethod("onBusMonitoringStarted", null)
            Log.d(TAG, "🔔 버스 도착 이벤트 리시버 등록 완료")
        } catch (e: Exception) {
            Log.e(TAG, "🔔 버스 도착 이벤트 리시버 등록 오류: ${e.message}", e)
            throw e
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

    private suspend fun checkBusArrivals() {
        Log.d(TAG, "🚌 버스 도착 확인 시작")
        try {
            // Create a copy of keys to avoid ConcurrentModificationException
            val routeIdsToCheck = monitoredRoutes.keys.toList()
            for (routeId in routeIdsToCheck) {
                val stationInfo = monitoredRoutes[routeId] ?: continue // Skip if route was removed concurrently
                val (stationId, stationName) = stationInfo

                // Ensure calls are within the coroutine scope implicitly provided by launch
                val currentBusInfoResult = busApiService.getCurrentBusInfo(stationId, routeId)
                val arrivalsResult = busApiService.getBusArrivals(stationId, routeId)

                Log.d(TAG, "🚌 [$routeId@$stationId] 현재 버스 정보: $currentBusInfoResult")
                Log.d(TAG, "🚌 [$routeId@$stationId] 도착 예정 버스: $arrivalsResult")

                // 도착 예정 버스 처리
                arrivalsResult.forEach { arrival ->
                    // Corrected variable names and added parsing
                    val remainingTimeStr = arrival.estimatedTime
                    val remainingTime = parseEstimatedTime(remainingTimeStr) // Use existing parsing function
                    val busNo = arrival.busNumber // Corrected variable name

                    Log.d(TAG, "🚌 버스 $busNo 도착까지 ${remainingTimeStr} ($remainingTime 분) 남음")

                    // 알림 조건 확인 (Handle cases where remainingTime is -1)
                    if (remainingTime in 0..5) {
                        showBusArrivalNotification(stationName, busNo, remainingTime)
                        // Ensure TTS message uses parsed time
                         val ttsMessage = if (remainingTime == 0) {
                            "$stationName 정류장에 $busNo 번 버스가 곧 도착합니다."
                         } else {
                             "$stationName 정류장에 $busNo 번 버스가 약 ${remainingTime}분 후에 도착합니다."
                         }
                         speakTts(ttsMessage, showNotification = true, busInfo = arrival.toMap()) // Pass parsed info
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ 버스 도착 확인 중 오류: ${e.message}", e)
        }
    }

    private fun showBusArrivalNotification(stationName: String, busNo: String, remainingTime: Int) {
        try {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val channelId = "bus_arrival_channel" // Consider using CHANNEL_BUS_ALERTS constant
            val notificationId = System.currentTimeMillis().toInt()

            // 알림 채널 생성 (Ensure this happens correctly, maybe reuse CHANNEL_BUS_ALERTS)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val existingChannel = notificationManager.getNotificationChannel(channelId)
                if (existingChannel == null) {
                     val channel = NotificationChannel(
                        channelId,
                        "버스 도착 알림", // Use a more descriptive name if creating a new channel
                        NotificationManager.IMPORTANCE_HIGH
                    ).apply {
                        description = "버스 도착 예정 알림"
                        // Corrected syntax
                        enableVibration(true)
                        enableLights(true)
                        lightColor = Color.BLUE
                        setShowBadge(true)
                         // Set sound consistent with main channel setup
                        if (currentAlarmSound.isNotEmpty()) {
                            val soundUri = Uri.parse("android.resource://${context.packageName}/raw/$currentAlarmSound")
                             setSound(soundUri, AudioAttributes.Builder()
                                .setUsage(AudioAttributes.USAGE_ALARM)
                                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                .build())
                         } else {
                             setSound(null, null) // Explicitly null if no sound
                         }
                    }
                    notificationManager.createNotificationChannel(channel)
                    Log.d(TAG, "🔔 알림 채널 생성됨: $channelId")
                } else {
                     Log.d(TAG, "🔔 기존 알림 채널 사용: $channelId")
                }
            }

            // 알림 스타일 설정
            val style = NotificationCompat.BigTextStyle()
                .setBigContentTitle(
                    "🚌 $busNo 번 버스가 곧 도착합니다!"
                )
                .bigText(
                    "$stationName 정류장\n" +
                    (if (remainingTime == 0) "⏰ 곧 도착" else "⏰ 남은 시간: $remainingTime 분") +
                    "\n📍 현재 위치: 정보 없음"
                )

            // 알림 액션 버튼 추가 (Intents seem okay)
            val boardingIntent = Intent(context, MainActivity::class.java).apply {
                action = "com.example.daegu_bus_app.BOARDING_COMPLETE"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val boardingPendingIntent = PendingIntent.getActivity(
                context,
                0,
                boardingIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val viewIntent = Intent(context, MainActivity::class.java).apply {
                action = "com.example.daegu_bus_app.VIEW_BUS_INFO"
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            val viewPendingIntent = PendingIntent.getActivity(
                context,
                1,
                viewIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            // 알림 빌더 설정
            val notification = NotificationCompat.Builder(context, channelId) // Use correct channelId
                .setSmallIcon(R.drawable.ic_bus_notification) // Ensure this drawable exists
                .setStyle(style)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(true)
                .setOngoing(false) // Arrival notifications shouldn't be ongoing typically
                .setVibrate(longArrayOf(0, 500, 200, 500)) // Standard vibration
                .setLights(Color.BLUE, 3000, 3000)
                .setContentIntent(viewPendingIntent) // Set content intent to view details
                .addAction(0, "승차 완료", boardingPendingIntent)
                .build()

            // 알림 표시
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
        routeId: String? = null // routeId 추가
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

                val title = if (isOngoing) "${busNo}번 버스 실시간 추적" else "${busNo}번 버스 승차 알림"
                var body = if (isOngoing) {
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
                    .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                    .setPriority(if (isOngoing) NotificationCompat.PRIORITY_HIGH else NotificationCompat.PRIORITY_MAX)
                    .setCategory(if (isOngoing) NotificationCompat.CATEGORY_SERVICE else NotificationCompat.CATEGORY_ALARM)
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

    // showOngoingBusTracking 메서드에 notificationId 매개변수 추가
    fun showOngoingBusTracking(
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String? = null,
        isUpdate: Boolean = false,
        notificationId: Int = ONGOING_NOTIFICATION_ID // 기본값으로 기존 ID 사용
    ) {
        try {
            Log.d(TAG, "🚌 버스 추적 알림 ${if (isUpdate) "업데이트" else "시작"}: $busNo, $stationName, 남은 시간: $remainingMinutes 분, 현재 위치: $currentStation, 업데이트: $isUpdate")

            val title = "${busNo}번 버스 실시간 추적"
            val body = if (remainingMinutes <= 0) {
                "$stationName 정류장에 곧 도착합니다!"
            } else {
                "$stationName 정류장까지 약 ${remainingMinutes}분 남았습니다." +
                    if (!currentStation.isNullOrEmpty()) " (현재 위치: $currentStation)" else ""
            }

            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                putExtra("NOTIFICATION_ID", ONGOING_NOTIFICATION_ID)
                putExtra("PAYLOAD", "bus_tracking_$busNo")
                putExtra("BUS_NUMBER", busNo)
                putExtra("STATION_NAME", stationName)
                putExtra("REMAINING_MINUTES", remainingMinutes)
                putExtra("CURRENT_STATION", currentStation)
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                ONGOING_NOTIFICATION_ID,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val stopTrackingIntent = Intent(context, NotificationDismissReceiver::class.java).apply {
                putExtra("NOTIFICATION_ID", ONGOING_NOTIFICATION_ID)
                putExtra("STOP_TRACKING", true)
            }
            val stopTrackingPendingIntent = PendingIntent.getBroadcast(
                context,
                ONGOING_NOTIFICATION_ID + 1000,
                stopTrackingIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val progress = 100 - (if (remainingMinutes > 30) 0 else remainingMinutes * 3)

            val builder = NotificationCompat.Builder(context, CHANNEL_BUS_ONGOING)
                .setSmallIcon(R.drawable.ic_bus_notification)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setColor(ContextCompat.getColor(context, R.color.tracking_color))
                .setColorized(true)
                .setAutoCancel(false)
                .setOngoing(true)
                .setOnlyAlertOnce(false)
                .setContentIntent(pendingIntent)
                .setProgress(100, progress, false)
                .addAction(R.drawable.ic_stop, "추적 중지", stopTrackingPendingIntent)
                .setUsesChronometer(true)
                .setWhen(System.currentTimeMillis())

            NotificationManagerCompat.from(context).notify(notificationId, builder.build())
            Log.d(TAG, "🚌 버스 추적 알림 표시 완료: 남은 시간 $remainingMinutes 분, 현재 위치: $currentStation")
        } catch (e: SecurityException) {
            Log.e(TAG, "🚌 알림 권한 없음: ${e.message}", e)
        } catch (e: Exception) {
            Log.e(TAG, "🚌 버스 추적 알림 오류: ${e.message}", e)
        }
    }

    fun showBusArrivingSoon(busNo: String, stationName: String, currentStation: String? = null) {
        try {
            Log.d(TAG, "🔔 버스 곧 도착 알림 표시: $busNo, $stationName")
            val notificationId = System.currentTimeMillis().toInt()
            val title = "⚠️ $busNo 번 버스 곧 도착"
            var body = "🚏 $stationName 정류장에 곧 도착합니다."
            if (!currentStation.isNullOrEmpty()) {
                body += " (현재 위치: $currentStation)"
            }
            
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
            
            // 앱에서 보기 액션 추가
            val viewInAppIntent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK
                putExtra("NOTIFICATION_ID", notificationId)
                putExtra("VIEW_IN_APP", true)
                putExtra("BUS_NUMBER", busNo)
                putExtra("STATION_NAME", stationName)
            }
            
            val viewInAppPendingIntent = PendingIntent.getActivity(
                context, notificationId + 100, viewInAppIntent,
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
                .setVibrate(longArrayOf(0, 500, 200, 500, 200, 500))
                .setLights(Color.RED, 500, 500)
                .setContentIntent(pendingIntent)
                .addAction(R.drawable.ic_bus_notification, "앱에서 보기", viewInAppPendingIntent)
                
            // TTS 사용하지 않을 경우 알람음 설정
            if (!useTextToSpeech) {
                builder.setSound(Uri.parse("android.resource://${context.packageName}/raw/$currentAlarmSound"))
            }
            
            NotificationManagerCompat.from(context).notify(notificationId, builder.build())
            Log.d(TAG, "🔔 버스 곧 도착 알림 표시 완료: $notificationId")
        } catch (e: Exception) {
            Log.e(TAG, "🔔 버스 곧 도착 알림 표시 오류: ${e.message}", e)
        }
    }

    fun startTtsTracking(routeId: String, stationId: String, busNo: String, stationName: String) {
        if (isTtsTrackingActive) {
            Log.d(TAG, "🔊 기존 TTS 추적 작업이 실행 중입니다. 중지 후 재시작합니다.")
            stopTtsTracking()
        }

        // Foreground 서비스 시작 확인
        if (!isInTrackingMode) {
            registerBusArrivalReceiver()
        }

        ttsJob = serviceScope.launch(Dispatchers.IO) {
            isTtsTrackingActive = true
            Log.d(TAG, "🔊 TTS 추적 시작: $busNo, $stationName (routeId: $routeId, stationId: $stationId)")
            
            while (isTtsTrackingActive) {
                try {
                    val arrivalInfo = busApiService.getBusArrivalInfoByRouteId(stationId, routeId)
                    val remaining = arrivalInfo?.bus?.firstOrNull()?.estimatedTime
                        ?.filter { it.isDigit() }?.toIntOrNull() ?: -1
                    val currentStation = arrivalInfo?.bus?.firstOrNull()?.currentStation ?: "정보 없음"

                    // 버스 정보를 맵으로 구성 (노티피케이션에 사용)
                    val busInfoMap = mapOf<String, Any?>(
                        "busNo" to busNo,
                        "stationName" to stationName,
                        "remainingMinutes" to remaining,
                        "currentStation" to currentStation,
                        "routeId" to routeId
                    )

                    val message = when {
                        remaining == -1 -> "도착 정보가 없습니다."
                        remaining == 0 -> "$busNo 버스가 $stationName 에 곧 도착합니다. 탑승 준비하세요."
                        remaining > 0 -> "$busNo 버스가 $stationName 에 약 ${remaining}분 후 도착 예정입니다. 현재 위치: $currentStation"
                        else -> null
                    }

                    if (message != null) {
                        withContext(Dispatchers.Main) {
                            // 자동 알람은 이어폰 전용 모드가 아님 (스피커와 이어폰 모두에서 재생)
                            speakTts(message, earphoneOnly = false, showNotification = true, busInfo = busInfoMap)
                            if (remaining == 0) {
                                showBusArrivingSoon(busNo, stationName, currentStation)
                                stopTtsTracking()
                            }
                        }
                    }
                    delay(60_000)
                } catch (e: Exception) {
                    Log.e(TAG, "❌ TTS 추적 중 오류: ${e.message}", e)
                    withContext(Dispatchers.Main) {
                        stopTtsTracking()
                    }
                    break
                }
            }
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

    fun stopTtsTracking(forceStop: Boolean = false) {
        if (!isTtsTrackingActive && !forceStop) {
            Log.d(TAG, "🔊 TTS 추적이 이미 중지된 상태입니다. 강제 중지 옵션 없음.")
            return
        }

        try {
            ttsJob?.cancel()
            ttsEngine?.stop()
            isTtsTrackingActive = false
            ttsJob = null
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
        return cachedBusInfo[cacheKey]
    }

    // 알람음 설정 불러오기
    private fun loadAlarmSoundSettings() {
        try {
            val sharedPreferences = context.getSharedPreferences(PREF_ALARM_SOUND, Context.MODE_PRIVATE)
            currentAlarmSound = sharedPreferences.getString(PREF_ALARM_SOUND_FILENAME, DEFAULT_ALARM_SOUND) ?: DEFAULT_ALARM_SOUND
            useTextToSpeech = sharedPreferences.getBoolean(PREF_ALARM_USE_TTS, false)
            
            // 오디오 출력 모드 불러오기 추가
            audioOutputMode = sharedPreferences.getInt(PREF_SPEAKER_MODE, OUTPUT_MODE_AUTO)
            
            Log.d(TAG, "🔔 알람음 설정 불러오기 성공: $currentAlarmSound, TTS 사용: $useTextToSpeech, 오디오 모드: $audioOutputMode")
        } catch (e: Exception) {
            Log.e(TAG, "🔔 알람음 설정 불러오기 오류: ${e.message}", e)
            currentAlarmSound = DEFAULT_ALARM_SOUND
            useTextToSpeech = false
            audioOutputMode = OUTPUT_MODE_AUTO
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

    private fun speakTts(text: String, earphoneOnly: Boolean = false, showNotification: Boolean = false, busInfo: Map<String, Any?>? = null) {
        if (ttsEngine != null && ttsEngine?.isLanguageAvailable(Locale.KOREAN) == TextToSpeech.LANG_AVAILABLE) {
            try {
                // Use provided text directly, or construct from busInfo if needed and text is empty/generic
                val message = if (text.isNotBlank()) {
                    text
                } else busInfo?.let {
                    val busNo = it["busNo"] as? String ?: "버스"
                    val stationName = it["stationName"] as? String ?: "정류장"
                    val remainingMinutes = (it["remainingMinutes"] as? Int) ?: -1

                    when {
                        remainingMinutes == 0 -> "$busNo 번이 $stationName 에 곧 도착합니다."
                        remainingMinutes > 0 -> "$busNo 번이 $stationName 에 약 ${remainingMinutes}분 후에 도착합니다."
                        else -> "$busNo 번 도착 정보 없음"
                    }
                } ?: "TTS 메시지 오류"

                // Determine audio stream based on mode and connection status
                val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                val useSpeaker = when (audioOutputMode) {
                    OUTPUT_MODE_SPEAKER -> true
                    OUTPUT_MODE_HEADSET -> false
                    OUTPUT_MODE_AUTO -> !isHeadsetConnected()
                    else -> !isHeadsetConnected()
                }

                val streamType = if (useSpeaker) AudioManager.STREAM_ALARM else AudioManager.STREAM_MUSIC

                Log.d(TAG, "🔊 TTS 발화 시도: \"$message\" (Stream: ${if(useSpeaker) "ALARM" else "MUSIC"}, EarphoneOnly: $earphoneOnly)")

                val params = Bundle().apply {
                    putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, "tts_${System.currentTimeMillis()}")
                    putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, streamType)
                    putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
                }

                val utteranceId = params.getString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID)
                ttsEngine?.speak(message, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
                Log.d(TAG, "🔊 TTS speak() 호출됨. utteranceId: $utteranceId")

                // 알림 표시
                if (showNotification && busInfo != null) {
                    val busNo = busInfo["busNo"] as? String
                    val stationName = busInfo["stationName"] as? String
                    val remainingMinutes = (busInfo["remainingMinutes"] as? Int) ?: -1
                    val currentStation = busInfo["currentStation"] as? String

                    if (busNo != null && stationName != null && remainingMinutes != -1) {
                        showBusArrivingSoon(busNo, stationName, currentStation)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ TTS 발화 중 오류 발생: ${e.message}", e)
            }
        } else {
            Log.e(TAG, "🔊 TTS 엔진 준비 안됨 또는 한국어 미지원")
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