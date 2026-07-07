package com.devground.daegubus

import android.os.Bundle
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import java.util.Locale
import android.content.Context
import android.media.AudioDeviceInfo
import android.speech.tts.UtteranceProgressListener
import android.app.NotificationManager
import android.widget.Toast
import android.os.Handler
import android.os.Looper
import androidx.annotation.NonNull
import android.os.Build
import android.app.NotificationChannel
import android.graphics.Color
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.IntentFilter
import android.content.ServiceConnection
import android.os.IBinder
import io.flutter.plugins.GeneratedPluginRegistrant
import android.app.Notification
import com.devground.daegubus.channels.BusApiChannelHandler
import com.devground.daegubus.channels.BusTrackingChannelHandler
import com.devground.daegubus.channels.PermissionChannelHandler
import com.devground.daegubus.channels.StationTrackingChannelHandler
import com.devground.daegubus.channels.TtsChannelHandler
import com.devground.daegubus.services.BusApiService
import com.devground.daegubus.services.BusAlertService
import com.devground.daegubus.services.TTSService
import com.devground.daegubus.utils.NotificationHandler
import android.webkit.WebView

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    companion object {
        internal const val ALARM_NOTIFICATION_CHANNEL_ID = "bus_alarm_channel"

        // 싱글톤 인스턴스
        private var instance: MainActivity? = null

        fun getInstance(): MainActivity? = instance

        // 정적 메서드를 통한 Flutter 이벤트 전송
        fun sendFlutterEvent(methodName: String, arguments: Any?) {
            try {
                instance?._methodChannel?.invokeMethod(methodName, arguments)
                Log.d("MainActivity", "✅ Flutter 이벤트 전송 완료: $methodName")
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ Flutter 이벤트 전송 실패: $methodName, ${e.message}")
            }
        }
    }

    private val BUS_API_CHANNEL = "com.devground.daegubus/bus_api"
    private val NOTIFICATION_CHANNEL = "com.devground.daegubus/notification"
    private val TTS_CHANNEL = "com.devground.daegubus/tts"
    private val STATION_TRACKING_CHANNEL = "com.devground.daegubus/station_tracking"
    private val BUS_TRACKING_CHANNEL = "com.devground.daegubus/bus_tracking"
    private val PERMISSION_CHANNEL = "com.devground.daegubus/permission"
    private val TAG = "MainActivity"

    internal lateinit var busApiService: BusApiService
    internal var busAlertService: BusAlertService? = null

    internal lateinit var notificationHandler: NotificationHandler

    // Make _methodChannel public for BusAlertService access
    var _methodChannel: MethodChannel? = null
        private set

    // TTS 채널
    private var _ttsMethodChannel: MethodChannel? = null
    private var _permissionMethodChannel: MethodChannel? = null

    // 서비스 바인딩을 위한 커넥션 객체
    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val binder = service as BusAlertService.LocalBinder
            busAlertService = binder.getService()
            busAlertService?.initialize()
            Log.d(TAG, "BusAlertService 바인딩 성공")
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            busAlertService = null
            Log.d(TAG, "BusAlertService 연결 해제")
        }
    }
    private val NOTIFICATION_PERMISSION_REQUEST_CODE = 123
    private val LOCATION_PERMISSION_REQUEST_CODE = 124
    private lateinit var audioManager: AudioManager
    private lateinit var tts: TextToSpeech
    private var alarmCancelReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        try {
            super.configureFlutterEngine(flutterEngine)
            GeneratedPluginRegistrant.registerWith(flutterEngine)

            Log.d(TAG, "🔧 Flutter 엔진 설정 시작")

            val messenger = flutterEngine.dartExecutor.binaryMessenger

            _methodChannel = MethodChannel(messenger, BUS_API_CHANNEL)
            _ttsMethodChannel = MethodChannel(messenger, TTS_CHANNEL)
            _permissionMethodChannel = MethodChannel(messenger, PERMISSION_CHANNEL)

            // 채널별 핸들러는 channels/ 패키지로 분리되어 있음
            _methodChannel?.setMethodCallHandler(BusApiChannelHandler(this))
            _ttsMethodChannel?.setMethodCallHandler(TtsChannelHandler(this))
            _permissionMethodChannel?.setMethodCallHandler(PermissionChannelHandler(this))
            MethodChannel(messenger, STATION_TRACKING_CHANNEL)
                .setMethodCallHandler(StationTrackingChannelHandler(this))
            MethodChannel(messenger, BUS_TRACKING_CHANNEL)
                .setMethodCallHandler(BusTrackingChannelHandler(this))

            Log.d(TAG, "✅ MethodChannel 생성 완료 (BUS_API, TTS, PERMISSION, STATION_TRACKING, BUS_TRACKING)")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Flutter 엔진 설정 오류: ${e.message}", e)
        }

        // 초기화 시도
        try {
            // BusAlertService 인스턴스 가져오기 (onCreate에서 이미 생성됨)
            busAlertService = BusAlertService.getInstance()
            busAlertService?.initialize()
            Log.d(TAG, "✅ BusAlertService 초기화 완료")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 알림 서비스 초기화 오류: ${e.message}", e)
        }

        Log.d(TAG, "✅ Flutter 엔진 설정 완료")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            // Edge-to-edge: Flutter 앱은 FlutterActivity → android.app.Activity 상속으로
            // ComponentActivity 확장함수인 enableEdgeToEdge() 불가.
            // WindowCompat + WindowInsetsControllerCompat 으로 동등하게 처리.
            WindowCompat.setDecorFitsSystemWindows(window, false)
            val insetsController = WindowInsetsControllerCompat(window, window.decorView)
            insetsController.isAppearanceLightStatusBars = false
            insetsController.isAppearanceLightNavigationBars = false
            // Android 10+: 내비게이션 바 컨트라스트 강제 적용 해제
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                window.isNavigationBarContrastEnforced = false
            }

            super.onCreate(savedInstanceState)

            // WebView 디버깅 활성화 (개발 중에만)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                WebView.setWebContentsDebuggingEnabled(true)
            }

            // 싱글톤 인스턴스 설정
            instance = this

            Log.d(TAG, "🚀 MainActivity 생성 시작")

            // UI 스레드에서 안전하게 초기화
            runOnUiThread {
                initializeEssentialComponents()
            }

            // 알람 취소 브로드캐스트 리시버 등록
            val filter = IntentFilter("cancel_alarm")
            registerReceiver(alarmCancelReceiver, filter)

        } catch (e: Exception) {
            Log.e(TAG, "❌ MainActivity onCreate 오류: ${e.message}", e)
        }
    }

    private fun initializeEssentialComponents() {
        try {
            Log.d(TAG, "🔧 필수 컴포넌트 초기화 시작")

            // 필수 초기화만 먼저 수행
            busApiService = BusApiService(this)
            audioManager = getSystemService(AUDIO_SERVICE) as AudioManager

            notificationHandler = NotificationHandler(this)

            // Create Notification Channels (Live Update "실시간 정보" 토글이 설정에 표시되려면 앱 시작 시 채널이 존재해야 함)
            notificationHandler.createNotificationChannels()

            // Create Notification Channel for Alarms
            createAlarmNotificationChannel()

            Log.d(TAG, "✅ 필수 컴포넌트 초기화 완료")

            // 나머지 초기화는 더 긴 지연으로 실행 (UI 완전 렌더링 후)
            Handler(Looper.getMainLooper()).postDelayed({
                initializeDelayedComponents()
            }, 500) // 500ms 지연으로 증가

        } catch (e: Exception) {
            Log.e(TAG, "❌ 필수 컴포넌트 초기화 오류: ${e.message}", e)
        }
    }

    private fun initializeDelayedComponents() {
        try {
            Log.d(TAG, "🔄 지연 초기화 시작")

            // 승차 완료 액션 처리
            if (intent?.action == "com.devground.daegubus.BOARDING_COMPLETE") {
                handleBoardingComplete()
            }

            // TTS 초기화
            try {
                tts = TextToSpeech(this, this)
            } catch (e: Exception) {
                Log.e(TAG, "TTS 초기화 오류: ${e.message}", e)
            }

            // 알림 취소 이벤트 수신을 위한 브로드캐스트 리시버 등록
            registerNotificationCancelReceiver()

            // 서비스 시작 및 바인딩
            startAndBindBusAlertService()

            Log.d(TAG, "✅ 지연 초기화 완료")

        } catch (e: Exception) {
            Log.e(TAG, "❌ 지연 초기화 오류: ${e.message}", e)
        }
    }

    /** BusAlertService를 시작하고 바인딩한다. 채널 핸들러에서 서비스가 null일 때도 호출된다. */
    internal fun startAndBindBusAlertService() {
        try {
            val serviceIntent = Intent(this, BusAlertService::class.java)
            startService(serviceIntent)
            bindService(serviceIntent, serviceConnection, Context.BIND_AUTO_CREATE)
            Log.d(TAG, "BusAlertService 시작 및 바인딩 요청 완료")
        } catch (e: Exception) {
            Log.e(TAG, "BusAlertService 초기화 실패: ${e.message}", e)
        }
    }

    /** BusAlertService가 없을 때 사용하는 폴백 TTS 발화. */
    internal fun speakFallbackTts(message: String) {
        if (::tts.isInitialized) {
            tts.speak(message, TextToSpeech.QUEUE_FLUSH, null, message.hashCode().toString())
            Log.d(TAG, "TTS 발화 (대안 방법): $message")
        } else {
            Log.w(TAG, "TTS가 초기화되지 않아 발화 실패")
        }
    }

    /** BusAlertService가 없을 때 사용하는 폴백 TTS 중지. */
    internal fun stopFallbackTts() {
        if (::tts.isInitialized) {
            tts.stop()
            Log.d(TAG, "TTS 중지 (대안 방법)")
        }
    }

    /** BusAlertService가 없을 때 AudioManager로 이어폰 연결 상태를 확인한다. */
    internal fun isHeadphoneConnectedViaAudioManager(): Boolean {
        val audioDevices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
        return audioDevices.any { device ->
            device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
            device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
            device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
            device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            LOCATION_PERMISSION_REQUEST_CODE -> {
                if (grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    Log.d(TAG, "위치 권한 승인됨")
                    // 권한이 승인되면 Flutter 측에 알림
                    _methodChannel?.invokeMethod("onLocationPermissionGranted", null)
                } else {
                    Log.d(TAG, "위치 권한 거부됨")
                    // 권한이 거부되면 Flutter 측에 알림
                    _methodChannel?.invokeMethod("onLocationPermissionDenied", null)
                }
            }
            NOTIFICATION_PERMISSION_REQUEST_CODE -> {
                if (grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    Log.d(TAG, "알림 권한 승인됨")
                } else {
                    Log.d(TAG, "알림 권한 거부됨")
                }
            }
        }
    }

    override fun onInit(status: Int) {
        // MainActivity의 TTS 초기화 로직은 유지 (초기 구동 시 필요할 수 있음)
        try {
            if (status == TextToSpeech.SUCCESS) {
                try {
                    tts.setLanguage(Locale.KOREAN)
                    tts.setSpeechRate(1.2f)
                    tts.setPitch(1.1f)
                    tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {
                            Log.d(TAG, "TTS 발화 시작: $utteranceId")
                        }

                        override fun onDone(utteranceId: String?) {
                            Log.d(TAG, "TTS 발화 완료: $utteranceId")
                        }

                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) {
                            Log.e(TAG, "TTS 발화 오류: $utteranceId")
                        }

                        override fun onError(utteranceId: String?, errorCode: Int) {
                            Log.e(TAG, "TTS 발화 오류 ($errorCode): $utteranceId")
                            onError(utteranceId)
                        }
                    })
                    Log.d(TAG, "MainActivity TTS 초기화 성공")
                } catch (e: Exception) {
                    Log.e(TAG, "TTS 설정 오류: ${e.message}", e)
                }
            } else {
                Log.e(TAG, "MainActivity TTS 초기화 실패: $status")
            }
        } catch (e: Exception) {
            Log.e(TAG, "MainActivity TTS onInit 오류: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        try {
            // 싱글톤 인스턴스 정리
            instance = null

            // TTS 종료
            if (::tts.isInitialized) {
                try {
                    tts.stop()
                    tts.shutdown()
                    Log.d(TAG, "TTS 자원 해제")
                } catch (e: Exception) {
                    Log.e(TAG, "TTS 자원 해제 오류: ${e.message}", e)
                }
            }

            // 서비스 바인딩 해제
            try {
                unbindService(serviceConnection)
                Log.d(TAG, "BusAlertService 바인딩 해제 완료")
            } catch (e: Exception) {
                Log.e(TAG, "서비스 바인딩 해제 오류: ${e.message}")
            }

            // 브로드캐스트 리시버 해제
            unregisterAlarmCancelReceiver()

            // 알람 취소 브로드캐스트 리시버 해제
            unregisterReceiver(alarmCancelReceiver)

            super.onDestroy()
        } catch (e: Exception) {
            Log.e(TAG, "onDestroy 오류: ${e.message}", e)
            super.onDestroy()
        }
    }

    private fun handleBoardingComplete() {
        try {
            // 알림 매니저 가져오기
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            // 진행 중인 알림 모두 제거
            notificationManager.cancelAll()

            // TTS 중지
            _methodChannel?.invokeMethod("stopTTS", null)

            // 승차 완료 메시지 표시
            Toast.makeText(
                this,
                "승차가 완료되었습니다. 알림이 중지되었습니다.",
                Toast.LENGTH_SHORT
            ).show()

            Log.d(TAG, "✅ 승차 완료 처리됨")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 승차 완료 처리 중 오류: ${e.message}")
        }
    }

    private fun unregisterAlarmCancelReceiver() {
        try {
            alarmCancelReceiver?.let {
                unregisterReceiver(it)
                alarmCancelReceiver = null
                Log.d(TAG, "알림 취소 브로드캐스트 리시버 해제 완료")
            }
        } catch (e: Exception) {
            Log.e(TAG, "알림 취소 리시버 해제 오류: ${e.message}", e)
        }
    }

    // Create notification channel for alarms
    private fun createAlarmNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Bus Alarms"
            val descriptionText = "Notifications for scheduled bus alarms"
            val importance = NotificationManager.IMPORTANCE_MAX // 최고 우선순위로 변경
            val channel = NotificationChannel(ALARM_NOTIFICATION_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                enableLights(true)
                lightColor = Color.RED
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 500, 200, 500) // 강력한 진동 패턴
                setShowBadge(true) // 배지 표시
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC // 잠금화면에서 표시
                setBypassDnd(true) // 방해금지 모드에서도 알림 표시
                setSound(null, null) // 기본 소리 사용
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    setAllowBubbles(true) // 버블 알림 허용 (Android 10+)
                }
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "Enhanced alarm notification channel created with maximum lockscreen visibility: $ALARM_NOTIFICATION_CHANNEL_ID")
        }
    }

    private fun handleNotificationAction(action: String, intent: Intent) {
        when (action) {
            "cancel_alarm" -> {
                val alarmId = intent.getIntExtra("alarm_id", -1)
                val busNo = intent.getStringExtra("busNo") ?: ""
                val stationName = intent.getStringExtra("stationName") ?: ""
                val routeId = intent.getStringExtra("routeId") ?: ""

                if (alarmId != -1) {
                    Log.d(TAG, "🔔 노티피케이션에서 알람 취소: ID=$alarmId, 버스=$busNo, 정류장=$stationName, 노선=$routeId")

                    // 알림 취소
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancel(alarmId)

                    // TTS 서비스 중지
                    val ttsIntent = Intent(this, TTSService::class.java)
                    ttsIntent.action = "STOP_TTS"
                    startService(ttsIntent)

                    // 현재 알람만 취소 상태로 저장
                    val prefs = getSharedPreferences("alarm_preferences", Context.MODE_PRIVATE)
                    val editor = prefs.edit()
                    editor.putBoolean("alarm_cancelled_$alarmId", true).apply()

                    // ✅ Flutter 쪽에 알람 취소 정보 전달 (중요!)
                    if (busNo.isNotEmpty() && stationName.isNotEmpty() && routeId.isNotEmpty()) {
                        try {
                            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                                val channel = MethodChannel(messenger, "com.devground.daegubus/bus_api")
                                channel.invokeMethod("cancelAlarmFromNotification", mapOf(
                                    "busNo" to busNo,
                                    "stationName" to stationName,
                                    "routeId" to routeId,
                                    "alarmId" to alarmId
                                ))
                                Log.d(TAG, "✅ Flutter에 알람 취소 정보 전달 완료")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Flutter에 알람 취소 정보 전달 실패: ${e.message}")
                        }
                    }

                    // 토스트 메시지로 알림
                    Toast.makeText(
                        this,
                        "현재 알람이 취소되었습니다",
                        Toast.LENGTH_SHORT
                    ).show()

                    Log.d(TAG, "✅ Alarm notification cancelled: $alarmId (one-time cancel)")
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val action = intent.action
        if (action != null && action != "cancel_alarm") {
            handleNotificationAction(action, intent)
        }
    }

    // 브로드캐스트 리시버 등록 메소드
    private fun registerNotificationCancelReceiver() {
        try {
            val intentFilter = IntentFilter().apply {
                addAction("com.devground.daegubus.NOTIFICATION_CANCELLED")
                addAction("com.devground.daegubus.ALL_TRACKING_CANCELLED")
                addAction("com.devground.daegubus.STOP_AUTO_ALARM") // 자동알람 중지 액션 추가
                // 필요하다면 다른 액션도 추가
            }
            // Android 버전에 따른 리시버 등록 방식 분기 (Exported/Not Exported)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    registerReceiver(notificationCancelReceiver, intentFilter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    registerReceiver(notificationCancelReceiver, intentFilter)
                }
                Log.d(TAG, "NotificationCancelReceiver 등록됨")
            } catch (e: Exception) {
                Log.e(TAG, "NotificationCancelReceiver 등록 오류: ${e.message}", e)
            }
        } catch (e: Exception) {
            Log.e(TAG, "알림 취소 이벤트 수신 리시버 등록 오류: ${e.message}", e)
        }
    }

    // 알림 취소 이벤트를 수신하는 브로드캐스트 리시버
    private val notificationCancelReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            try {
                val action = intent.action
                Log.d(TAG, "NotificationCancelReceiver: 액션 수신: $action")

                when (action) {
                    "com.devground.daegubus.NOTIFICATION_CANCELLED" -> {
                        val routeId = intent.getStringExtra("routeId") ?: ""
                        val busNo = intent.getStringExtra("busNo") ?: ""
                        val stationName = intent.getStringExtra("stationName") ?: ""
                        val source = intent.getStringExtra("source") ?: "unknown"

                        Log.i(TAG, "알림 취소 이벤트 수신: Bus=$busNo, Route=$routeId, Station=$stationName, Source=$source")

                        // Flutter 측에 알림 취소 이벤트 전송
                        val alarmCancelData = mapOf(
                            "busNo" to busNo,
                            "routeId" to routeId,
                            "stationName" to stationName,
                            "source" to "notification"
                        )
                        _methodChannel?.invokeMethod("onAlarmCanceledFromNotification", alarmCancelData)
                        Log.i(TAG, "Flutter 측에 알람 취소 알림 전송 완료 (From BroadcastReceiver)")
                    }
                    "com.devground.daegubus.ALL_TRACKING_CANCELLED" -> {
                        Log.i(TAG, "모든 추적 취소 이벤트 수신")

                        // Flutter 측에 모든 알림 취소 이벤트 전송
                        _methodChannel?.invokeMethod("onAllAlarmsCanceled", mapOf("source" to "notification"))
                        Log.i(TAG, "Flutter 측에 모든 알람 취소 알림 전송 완료")
                    }
                    "com.devground.daegubus.STOP_AUTO_ALARM" -> {
                        val routeId = intent.getStringExtra("routeId") ?: ""
                        val busNo = intent.getStringExtra("busNo") ?: ""
                        val stationName = intent.getStringExtra("stationName") ?: ""

                        Log.i(TAG, "자동알람 중지 브로드캐스트 수신: Bus=$busNo, Route=$routeId, Station=$stationName")

                        // Flutter 측에 자동알람 중지 이벤트 전송
                        try {
                            val autoAlarmCancelData = mapOf(
                                "busNo" to busNo,
                                "stationName" to stationName,
                                "routeId" to routeId
                            )
                            _methodChannel?.invokeMethod("stopAutoAlarmFromBroadcast", autoAlarmCancelData)
                            Log.i(TAG, "✅ Flutter 측에 자동알람 중지 이벤트 전송 완료")
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Flutter 측 자동알람 중지 이벤트 전송 오류: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "알림 취소 이벤트 처리 중 오류: ${e.message}", e)
            }
        }
    }

    private fun unregisterNotificationCancelReceiver() {
        try {
            unregisterReceiver(notificationCancelReceiver)
            Log.d(TAG, "NotificationCancelReceiver 해제됨")
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "NotificationCancelReceiver 해제 시도 중 오류 (이미 해제되었거나 등록되지 않음): ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "NotificationCancelReceiver 해제 중 예외 발생: ${e.message}", e)
        }
    }

    override fun onResume() {
        super.onResume()
        registerNotificationCancelReceiver() // 리시버 등록
    }

    override fun onPause() {
        super.onPause()
        unregisterNotificationCancelReceiver() // 리시버 해제
    }

}

// --- WorkManager Callback ---
// Using object structure as provided by user
object WorkManagerCallback {
    @JvmStatic
    fun callbackDispatcher() {
        Log.d("WorkManagerCallback", "WorkManager callback dispatcher invoked.")
        // WorkManager initialization is best handled in the Application class.
    }
}
