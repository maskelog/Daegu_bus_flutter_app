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
    
    // 추적 모드 상태 변수 추가
    private var _isInTrackingMode = false
    val isInTrackingMode: Boolean
        get() = _isInTrackingMode || monitoredRoutes.isNotEmpty()

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
        } catch (e: Exception) {
            Log.e(TAG, "🔔 알림 서비스 초기화 중 오류 발생: ${e.message}", e)
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
            
            // 현재 모니터링 중인 노선 로깅
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
            
            _isInTrackingMode = true
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
                    val busInfo = arrivalInfo.bus[0] // 첫 번째 버스 정보 사용
                    val busNo = arrivalInfo.name
                    val currentStation = busInfo.currentStation
                    val remainingTime = parseEstimatedTime(busInfo.estimatedTime)

                    Log.d(TAG, "🔔 도착 정보: $busNo, $stationName, 남은 시간: $remainingTime 분, 현재 위치: $currentStation")
                    
                    // 도착 임박 알림 (0~2분)
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
                        }
                    } 
                    // 실시간 추적 알림 업데이트 (2분 이상)
                    else if (remainingTime > 2) {
                        withContext(Dispatchers.Main) {
                            // isUpdate를 true로 설정하여 기존 알림 업데이트
                            showOngoingBusTracking(busNo, stationName, remainingTime, currentStation, true)
                            
                            // 앱에도 업데이트된 정보 전달
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

    fun addMonitoredRoute(routeId: String, stationId: String, stationName: String) {
        // 로그 추가
        Log.d(TAG, "🔔 모니터링 노선 추가 요청: routeId=$routeId, stationId=$stationId, stationName=$stationName")
        
        if (routeId.isEmpty() || stationId.isEmpty() || stationName.isEmpty()) {
            Log.e(TAG, "🔔 유효하지 않은 파라미터: routeId=$routeId, stationId=$stationId, stationName=$stationName")
            return
        }
        
        monitoredRoutes[routeId] = Pair(stationId, stationName)
        Log.d(TAG, "🔔 모니터링 노선 추가 완료: routeId=$routeId, stationId=$stationId, stationName=$stationName")
        Log.d(TAG, "🔔 현재 모니터링 중인 노선 수: ${monitoredRoutes.size}개")
        
        // 모니터링 노선 추가 후 즉시 서비스 상태 확인
        if (!_isInTrackingMode) {
            registerBusArrivalReceiver()
        }
    }
    
    // 추가 도우미 메서드
    fun getMonitoredRoutesCount(): Int {
        return monitoredRoutes.size
    }

    fun showNotification(
        id: Int,
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String? = null,
        payload: String? = null
    ) {
        serviceScope.launch {
            try {
                Log.d(TAG, "🔔 알림 표시 시도: $busNo, $stationName, ${remainingMinutes}분, ID: $id")
                val title = "${busNo}번 버스 승차 알림"
                var body = "${stationName} 정류장 - 약 ${remainingMinutes}분 후 도착"
                if (!currentStation.isNullOrEmpty()) {
                    body += " (현재 위치: $currentStation)"
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
                    .setPriority(NotificationCompat.PRIORITY_MAX)
                    .setCategory(NotificationCompat.CATEGORY_ALARM)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setColor(ContextCompat.getColor(context, R.color.notification_color))
                    .setColorized(true)
                    .setAutoCancel(false)
                    .setOngoing(true)
                    .setContentIntent(pendingIntent)
                    .setSound(Uri.parse("android.resource://${context.packageName}/raw/alarm_sound"))
                    .setVibrate(longArrayOf(0, 500, 200, 500, 200, 500))
                    .addAction(R.drawable.ic_dismiss, "알람 종료", dismissPendingIntent)
                    .setFullScreenIntent(pendingIntent, true)
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
    
    fun showOngoingBusTracking(
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String? = null,
        isUpdate: Boolean = false
    ) {
        try {
            // 기록 남기기 - 디버그용
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
                // 추가 정보도 Intent에 포함
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

            // 남은 시간에 따라 진행률 계산 (최대 30분을 100%로 설정)
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
                .setOnlyAlertOnce(false) // 알림 변경 시 소리/진동 설정 (false면 매번 알림)
                .setContentIntent(pendingIntent)
                .setProgress(100, progress, false)
                .addAction(R.drawable.ic_stop, "추적 중지", stopTrackingPendingIntent)
                // 타이머 표시 - 추적 시작 시간부터 경과 시간을 보여줌
                .setUsesChronometer(true)
                // 알림 시간 설정 - 매번 현재 시간으로 업데이트하여 최신 정보임을 표시
                .setWhen(System.currentTimeMillis())

            NotificationManagerCompat.from(context).notify(ONGOING_NOTIFICATION_ID, builder.build())
            Log.d(TAG, "🚌 버스 추적 알림 표시 완료: 남은 시간 $remainingMinutes 분, 현재 위치: $currentStation")
        } catch (e: SecurityException) {
            Log.e(TAG, "🚌 알림 권한 없음: ${e.message}", e)
        } catch (e: Exception) {
            Log.e(TAG, "🚌 버스 추적 알림 오류: ${e.message}", e)
        }
    }

    fun showBusArrivingSoon(
        busNo: String,
        stationName: String,
        currentStation: String? = null
    ) {
        serviceScope.launch {
            try {
                Log.d(TAG, "🚨 버스 도착 임박 알림 표시 시도: $busNo")
                val title = "⚠️ ${busNo}번 버스 곧 도착!"
                var body = "$stationName 정류장에 곧 도착합니다! 탑승 준비하세요."
                if (!currentStation.isNullOrEmpty()) {
                    body += " 현재 위치: $currentStation"
                }
                val intent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                }
                val pendingIntent = PendingIntent.getActivity(
                    context, 
                    busNo.hashCode(), 
                    intent, 
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
                    .setColor(Color.RED)
                    .setColorized(true)
                    .setAutoCancel(false)
                    .setContentIntent(pendingIntent)
                    .setSound(Uri.parse("android.resource://${context.packageName}/raw/alarm_sound"))
                    .setVibrate(longArrayOf(0, 500, 200, 500, 200, 500))
                    .setLights(Color.RED, 1000, 500)
                    .setFullScreenIntent(pendingIntent, true)
                with(NotificationManagerCompat.from(context)) {
                    try {
                        notify(busNo.hashCode(), builder.build())
                        Log.d(TAG, "🚨 버스 도착 임박 알림 표시 완료: $busNo")
                    } catch (e: SecurityException) {
                        Log.e(TAG, "🚨 알림 권한 없음: ${e.message}", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "🚨 버스 도착 임박 알림 오류: ${e.message}", e)
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
    
    fun showTestNotification() {
        showNotification(
            id = 9999,
            busNo = "테스트",
            stationName = "테스트 정류장",
            remainingMinutes = 3,
            currentStation = "테스트 중"
        )
    }
    
    fun stopTracking() {
        cancelOngoingTracking()
        try {
            _methodChannel?.invokeMethod("stopBusMonitoringService", null)
            monitoringJob?.cancel()
            monitoredRoutes.clear()
            timer.cancel()
            _isInTrackingMode = false
            Log.d(TAG, "stopTracking() 호출됨: 버스 추적 서비스 중지됨")
        } catch (e: Exception) {
            Log.e(TAG, "버스 모니터링 서비스 중지 오류: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        monitoringJob?.cancel()
        timer.cancel()
        serviceScope.cancel()
        Log.d(TAG, "🔔 BusAlertService 종료")
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