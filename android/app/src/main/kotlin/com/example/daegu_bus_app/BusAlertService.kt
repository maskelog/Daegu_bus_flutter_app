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
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import androidx.work.*
import java.util.concurrent.TimeUnit

/**
 * BusAlertService: Android 네이티브 알림 서비스
 * Flutter의 NotificationHelper를 대체하는 Kotlin 구현체
 */
class BusAlertService : Service() {
    companion object {
        private const val TAG = "BusAlertService"
        
        // 알림 채널 ID
        private const val CHANNEL_BUS_ALERTS = "bus_alerts"
        private const val CHANNEL_BUS_ONGOING = "bus_ongoing"
        
        // 지속적인 알림을 위한 고정 ID
        const val ONGOING_NOTIFICATION_ID = 10000
        
        // 싱글톤 인스턴스
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
    private val serviceScope = CoroutineScope(Dispatchers.Main)
    private lateinit var context: Context

    override fun onBind(intent: Intent?): IBinder? {
        return null
    }
    
    /**
    * 알림 서비스 초기화
    * 알림 채널 생성 및 권한 체크
    */
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
            
            // 메서드 채널 초기화 (네이티브 서비스와의 통신)
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
        
    /**
     * 알림 채널 생성
     */
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
    
    /**
     * 알림 권한 체크
     */
    private fun checkNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Log.d(TAG, "Android 13+ 알림 권한 확인 필요")
        }
    }
    
    /**
     * 즉시 알림 전송
     */
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
    
    /**
     * 지속적인 버스 위치 추적 알림 시작/업데이트
     */
    fun showOngoingBusTracking(
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String? = null,
        isUpdate: Boolean = false
    ) {
        serviceScope.launch {
            try {
                Log.d(TAG, "🚌 버스 추적 알림 ${if (isUpdate) "업데이트" else "시작"}: $busNo, $remainingMinutes 분")
                val title = "${busNo}번 버스 실시간 추적"
                val body = if (remainingMinutes <= 0) {
                    "$stationName 정류장에 곧 도착합니다!"
                } else {
                    "$stationName 정류장까지 약 ${remainingMinutes}분 남았습니다." + 
                    if (!currentStation.isNullOrEmpty()) " 현재 위치: $currentStation" else ""
                }
                val intent = Intent(context, MainActivity::class.java).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                    putExtra("NOTIFICATION_ID", ONGOING_NOTIFICATION_ID)
                    putExtra("PAYLOAD", "bus_tracking_$busNo")
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
                    .setPriority(NotificationCompat.PRIORITY_DEFAULT)
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
                with(NotificationManagerCompat.from(context)) {
                    try {
                        notify(ONGOING_NOTIFICATION_ID, builder.build())
                        Log.d(TAG, "🚌 버스 추적 알림 표시 완료")
                    } catch (e: SecurityException) {
                        Log.e(TAG, "🚌 알림 권한 없음: ${e.message}", e)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "🚌 버스 추적 알림 오류: ${e.message}", e)
            }
        }
    }
    
    /**
     * 버스 도착 임박 알림 (중요도 높음)
     */
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
    
    /**
     * 알림 취소
     */
    fun cancelNotification(id: Int) {
        try {
            NotificationManagerCompat.from(context).cancel(id)
            Log.d(TAG, "🔔 알림 취소 완료: $id")
        } catch (e: Exception) {
            Log.e(TAG, "🔔 알림 취소 오류: ${e.message}", e)
        }
    }
    
    /**
     * 지속적인 추적 알림 취소
     */
    fun cancelOngoingTracking() {
        try {
            // 지속적인 추적 알림 취소
            NotificationManagerCompat.from(context).cancel(ONGOING_NOTIFICATION_ID)
            
            // 관련된 버스 알림도 모두 취소 (선택적)
            // 주의: 모든 알림을 취소하면 다른 앱의 알림에 영향을 줄 수 있으므로,
            // 이 앱에서 생성한 알림만 취소하는 것이 바람직합니다.
            // NotificationManagerCompat.from(context).cancelAll()
            
            // 메서드 채널을 통해 Flutter에 알림 취소를 알림
            _methodChannel?.invokeMethod("onTrackingCancelled", null)
            
            Log.d(TAG, "🚌 지속적인 추적 알림 및 관련 알림 취소 완료")
        } catch (e: Exception) {
            Log.e(TAG, "🚌 지속적인 추적 알림 취소 오류: ${e.message}", e)
        }
    }
    
    /**
     * 모든 알림 취소
     */
    fun cancelAllNotifications() {
        try {
            NotificationManagerCompat.from(context).cancelAll()
            Log.d(TAG, "🔔 모든 알림 취소 완료")
        } catch (e: Exception) {
            Log.e(TAG, "🔔 모든 알림 취소 오류: ${e.message}", e)
        }
    }
    
    /**
     * 테스트 알림 전송
     */
    fun showTestNotification() {
        showNotification(
            id = 9999,
            busNo = "테스트",
            stationName = "테스트 정류장",
            remainingMinutes = 3,
            currentStation = "테스트 중"
        )
    }
    
    /**
     * 네이티브 서비스 중지 명령: 추적 중지 버튼 클릭 시 호출됩니다.
     * 지속적인 추적 알림을 취소하고, 네이티브 BusAlertService를 중지합니다.
     */
    fun stopTracking() {
        cancelOngoingTracking()
        try {
            // 네이티브 BusAlertService 중지 명령 전달 (예: MethodChannel을 통한 호출)
            _methodChannel?.invokeMethod("stopBusMonitoringService", null)
        } catch (e: Exception) {
            Log.e(TAG, "버스 모니터링 서비스 중지 오류: ${e.message}", e)
        }
        Log.d(TAG, "stopTracking() 호출됨: 버스 추적 서비스 중지됨")
    }
}

/**
 * 알림 닫기 버튼에 대한 BroadcastReceiver
 */
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

/**
 * 알림 채널 목록 가져오기
 */
fun getNotificationChannels(context: Context): List<NotificationChannel>? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val notificationManager = 
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        notificationManager.notificationChannels
    } else {
        null
    }
}
