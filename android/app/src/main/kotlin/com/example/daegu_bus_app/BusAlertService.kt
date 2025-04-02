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
            
            ttsEngine = android.speech.tts.TextToSpeech(context) { status ->
                if (status == android.speech.tts.TextToSpeech.SUCCESS) {
                    try {
                        val result = ttsEngine?.setLanguage(java.util.Locale.KOREAN)
                        when (result) {
                            android.speech.tts.TextToSpeech.LANG_MISSING_DATA -> 
                                Log.e(TAG, "❌ 한국어 언어 데이터 없음")
                            android.speech.tts.TextToSpeech.LANG_NOT_SUPPORTED -> 
                                Log.e(TAG, "❌ 한국어가 지원되지 않음")
                            else -> 
                                Log.d(TAG, "🔊 한국어 설정 성공: $result")
                        }
                        
                        ttsEngine?.setSpeechRate(1.0f)
                        Log.d(TAG, "🔊 TTS 엔진 초기화 성공")
                        
                        // 여기서 TTS 엔진이 제대로 작동하는지 테스트
                        ttsEngine?.speak("테스트 발화", android.speech.tts.TextToSpeech.QUEUE_FLUSH, null, "TTS_TEST")
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
                
                val busAlertsChannel = NotificationChannel(
                    CHANNEL_BUS_ALERTS,
                    "Bus Alerts",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "버스 도착 알림"
                    enableLights(true)
                    lightColor = Color.RED
                    enableVibration(true)
                    val soundUri = Uri.parse("android.resource://${context.packageName}/raw/alarm_sound")
                    val audioAttributes = AudioAttributes.Builder()
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_EVENT)
                        .build()
                    setSound(soundUri, audioAttributes)
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
        try {
            if (monitoredRoutes.isEmpty()) {
                Log.d(TAG, "🔔 모니터링할 노선이 없습니다")
                return
            }

            for ((routeId, pair) in monitoredRoutes) {
                val (stationId, stationName) = pair
                Log.d(TAG, "🔔 버스 도착 정보 확인: routeId=$routeId, stationId=$stationId")

                val arrivalInfo = busApiService.getBusArrivalInfoByRouteId(stationId, routeId)
                if (arrivalInfo != null && arrivalInfo.bus.isNotEmpty()) {
                    val busInfo = arrivalInfo.bus[0]
                    val busNo = arrivalInfo.name
                    val currentStation = busInfo.currentStation
                    val remainingTime = parseEstimatedTime(busInfo.estimatedTime)

                    val correctBusInfo = BusInfo(
                        busNumber = busNo,
                        currentStation = currentStation,
                        remainingStops = "",
                        estimatedTime = busInfo.estimatedTime,
                        isLowFloor = false,
                        isOutOfService = false
                    )

                    val cacheKey = "$busNo-$routeId"
                    cachedBusInfo[cacheKey] = correctBusInfo

                    Log.d(TAG, "🔔 도착 정보: $busNo, $stationName, 남은 시간: $remainingTime 분, 현재 위치: $currentStation")
                    Log.d(TAG, "🔔 Cache Key: $cacheKey")
                    Log.d(TAG, "🔔 Cached BusInfo: $correctBusInfo")

                    val lastTime = lastRemainingTimes[routeId] ?: -100
                    val timeDifference = Math.abs(remainingTime - lastTime)

                    Log.d(TAG, "🔊 TTS 추적 상태: 추적 활성화=$isTtsTrackingActive, 남은 시간=$remainingTime, 이전 시간=$lastTime, 시간 차이=$timeDifference")

                    if (remainingTime in 0..2) {
                        withContext(Dispatchers.Main) {
                            showBusArrivingSoon(busNo, stationName, currentStation)
                            _methodChannel?.invokeMethod(
                                "onBusArrival",
                                mapOf(
                                    "busNumber" to busNo,
                                    "stationName" to stationName,
                                    "currentStation" to currentStation,
                                    "routeId" to routeId
                                ).toString()
                            )
                            Log.d(TAG, "🔊 도착 임박 TTS 발화 시도: $busNo 버스")
                            speakTts("$busNo 버스가 곧 도착합니다.")
                            lastRemainingTimes[routeId] = remainingTime
                        }
                    } else if (remainingTime > 2) {
                        withContext(Dispatchers.Main) {
                            showNotification(
                                ONGOING_NOTIFICATION_ID,
                                busNo,
                                stationName,
                                remainingTime,
                                currentStation,
                                "bus_tracking_$busNo",
                                true,
                                routeId
                            )
                            _methodChannel?.invokeMethod(
                                "onBusLocationUpdate",
                                mapOf(
                                    "busNumber" to busNo,
                                    "stationName" to stationName,
                                    "currentStation" to currentStation,
                                    "remainingMinutes" to remainingTime,
                                    "routeId" to routeId
                                ).toString()
                            )

                            if (timeDifference >= 2 || lastTime == -100 ||
                                (lastRemainingTimes.containsKey(routeId) &&
                                System.currentTimeMillis() - (lastTimestamps[routeId] ?: 0L) > 120_000)) {
                                
                                Log.d(TAG, "🔊 남은 시간 TTS 발화 시도: $busNo 버스, $remainingTime 분 남음")
                                speakTts("$busNo 버스가 약 ${remainingTime}분 후 도착 예정입니다.")
                                
                                lastRemainingTimes[routeId] = remainingTime
                                lastTimestamps[routeId] = System.currentTimeMillis()
                            }
                        }
                    }
                } else {
                    Log.d(TAG, "🔔 도착 정보가 없습니다: routeId=$routeId, stationId=$stationId")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "🔔 버스 도착 정보 확인 오류: ${e.message}", e)
        }
    }

    private fun speakTts(text: String) {
        try {
            Log.d(TAG, "🔊 TTS 발화 시도: $text")
            
            if (ttsEngine == null) {
                Log.d(TAG, "🔊 TTS 엔진 초기화 필요")
                initializeTts()
                Thread.sleep(200) // 초기화에 더 많은 시간 부여
            }
            
            val result = if (text.length > 20) {
                // 문장 분할
                val sentences = splitIntoSentences(text)
                for (sentence in sentences) {
                    val utteranceId = "BUS_TTS_TRACKING_${sentences.indexOf(sentence)}"
                    Log.d(TAG, "🔊 TTS 분할 발화 시도 (${sentences.indexOf(sentence) + 1}/${sentences.size}): $sentence, ID: $utteranceId")
                    
                    val speakResult = ttsEngine?.speak(sentence, android.speech.tts.TextToSpeech.QUEUE_ADD, null, utteranceId)
                    Log.d(TAG, "🔊 TTS 분할 발화 결과: $speakResult (0은 성공)")
                    
                    Thread.sleep(500) // 문장 사이에 더 긴 지연 시간 부여
                }
                0 // 성공으로 간주
            } else {
                val utteranceId = "BUS_TTS_TRACKING_${System.currentTimeMillis()}"
                Log.d(TAG, "🔊 TTS 단일 발화 시도: $text, ID: $utteranceId")
                ttsEngine?.speak(text, android.speech.tts.TextToSpeech.QUEUE_FLUSH, null, utteranceId)
            }
            
            Log.d(TAG, "🔊 TTS 발화 명령 완료: $text (결과: $result, 0은 성공)")
            
            // 디버깅을 위한 TTS 엔진 상태 로깅
            if (ttsEngine?.isSpeaking == true) {
                Log.d(TAG, "🔊 TTS 엔진이 현재 말하는 중")
            } else {
                Log.d(TAG, "🔊 TTS 엔진이 현재 말하지 않음")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ TTS 발화 오류: ${e.message}", e)
            // 오류 발생 시 다시 초기화 시도
            try {
                Log.d(TAG, "🔊 TTS 엔진 재초기화 시도")
                ttsEngine?.shutdown()
                ttsEngine = null
                initializeTts()
            } catch (e2: Exception) {
                Log.e(TAG, "❌ TTS 엔진 재초기화 실패: ${e2.message}", e2)
            }
        }
    }
    
    // 문장 분할 헬퍼 메서드
    private fun splitIntoSentences(text: String): List<String> {
        val sentences = mutableListOf<String>()
        
        // 문장 구분자
        val sentenceDelimiters = "[.!?]".toRegex()
        val parts = text.split(sentenceDelimiters)
        
        if (parts.size > 1) {
            // 문장 구분자가 있으면 그대로 분할
            for (part in parts) {
                if (part.trim().isNotEmpty()) {
                    sentences.add(part.trim())
                }
            }
        } else {
            // 쉼표로 분할 시도
            val commaDelimited = text.split(",")
            if (commaDelimited.size > 1) {
                for (part in commaDelimited) {
                    if (part.trim().isNotEmpty()) {
                        sentences.add(part.trim())
                    }
                }
            } else {
                // 길이에 따라 임의로 분할
                val maxLength = 20
                var remaining = text
                while (remaining.length > maxLength) {
                    // 공백을 기준으로 적절한 분할 지점 찾기
                    var cutPoint = maxLength
                    while (cutPoint > 0 && remaining[cutPoint] != ' ') {
                        cutPoint--
                    }
                    // 공백을 찾지 못했으면 그냥 maxLength에서 자르기
                    if (cutPoint == 0) cutPoint = maxLength
                    
                    sentences.add(remaining.substring(0, cutPoint).trim())
                    remaining = remaining.substring(cutPoint).trim()
                }
                if (remaining.isNotEmpty()) {
                    sentences.add(remaining)
                }
            }
        }
        
        return sentences.filter { it.isNotEmpty() }
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
                    .setSound(Uri.parse("android.resource://${context.packageName}/raw/alarm_sound"))
                    .setVibrate(longArrayOf(0, 500, 200, 500, 200, 500))
                    .addAction(R.drawable.ic_dismiss, "알람 종료", dismissPendingIntent)
                    .setFullScreenIntent(pendingIntent, true)

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
            val title = "$busNo 번 버스 곧 도착"
            var body = "$stationName 정류장에 곧 도착합니다."
            if (!currentStation.isNullOrEmpty()) {
                body += " (현재 위치: $currentStation)"
            }
            val intent = Intent(context, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            val pendingIntent = PendingIntent.getActivity(
                context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val builder = NotificationCompat.Builder(context, CHANNEL_BUS_ALERTS)
                .setSmallIcon(R.drawable.ic_bus_notification)
                .setContentTitle(title)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setAutoCancel(true)
                .setContentIntent(pendingIntent)
            NotificationManagerCompat.from(context).notify(System.currentTimeMillis().toInt(), builder.build())
            Log.d(TAG, "🔔 버스 곧 도착 알림 표시 완료")
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

                    val message = when {
                        remaining == -1 -> "도착 정보가 없습니다."
                        remaining == 0 -> "$busNo 버스가 $stationName 에 곧 도착합니다. 탑승 준비하세요."
                        remaining > 0 -> "$busNo 버스가 $stationName 에 약 ${remaining}분 후 도착 예정입니다. 현재 위치: $currentStation"
                        else -> null
                    }

                    if (message != null) {
                        withContext(Dispatchers.Main) {
                            speakTts(message)
                            if (remaining == 0) {
                                showBusArrivingSoon(busNo, stationName, currentStation) // stationName 올바르게 사용
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