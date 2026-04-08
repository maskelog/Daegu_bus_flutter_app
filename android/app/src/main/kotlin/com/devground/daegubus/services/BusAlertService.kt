package com.devground.daegubus.services

import io.flutter.plugin.common.MethodChannel
import com.devground.daegubus.R
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.net.Uri
import android.widget.RemoteViews
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
import com.devground.daegubus.models.BusInfo
import com.devground.daegubus.utils.NotificationHandler
import com.devground.daegubus.MainActivity
import com.devground.daegubus.services.BusAlertTtsController
import com.devground.daegubus.services.BusAlertNotificationUpdater
import com.devground.daegubus.services.BusAlertTrackingManager

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
        internal const val CHANNEL_ID_AUTO_ALARM_LEGACY = "auto_alarm_lightweight"
        // v3: IMPORTANCE_HIGH + setShowBadge(false) 로 Live Update 조건 충족
        internal const val CHANNEL_ID_AUTO_ALARM_LIVE_UPDATE = "auto_alarm_live_update_v3"
        internal const val CHANNEL_NAME_AUTO_ALARM = "자동 알람 (경량)"

        // 서비스 상태 대한 싱글톤 인스턴스
        private var instance: BusAlertService? = null
        fun getInstance(): BusAlertService? = instance

        // 서비스 상태 플래그
        private var isServiceActive = false

        fun isActive(): Boolean = isServiceActive

        internal fun getAutoAlarmChannelId(): String {
            return if (Build.VERSION.SDK_INT >= 36) {
                CHANNEL_ID_AUTO_ALARM_LIVE_UPDATE
            } else {
                CHANNEL_ID_AUTO_ALARM_LEGACY
            }
        }

        // Notification IDs
        const val ONGOING_NOTIFICATION_ID = NotificationHandler.ONGOING_NOTIFICATION_ID
        const val AUTO_ALARM_NOTIFICATION_ID = 9999 // 자동알람 전용 ID

        // Intent Actions
        const val ACTION_START_TRACKING = "com.devground.daegubus.action.START_TRACKING"
        const val ACTION_STOP_TRACKING = "com.devground.daegubus.action.STOP_TRACKING"
        const val ACTION_STOP_SPECIFIC_ROUTE_TRACKING = "com.devground.daegubus.action.STOP_SPECIFIC_ROUTE_TRACKING"
        const val ACTION_CANCEL_NOTIFICATION = "com.devground.daegubus.action.CANCEL_NOTIFICATION"
        const val ACTION_START_TTS_TRACKING = "com.devground.daegubus.action.START_TTS_TRACKING"
        const val ACTION_STOP_TTS_TRACKING = "com.devground.daegubus.action.STOP_TTS_TRACKING"
        const val ACTION_START_TRACKING_FOREGROUND = "com.devground.daegubus.action.START_TRACKING_FOREGROUND"
        const val ACTION_UPDATE_TRACKING = "com.devground.daegubus.action.UPDATE_TRACKING"
        const val ACTION_STOP_BUS_ALERT_TRACKING = "com.devground.daegubus.action.STOP_BUS_ALERT_TRACKING"
        const val ACTION_START_AUTO_ALARM_LIGHTWEIGHT = "com.devground.daegubus.action.START_AUTO_ALARM_LIGHTWEIGHT"
        const val ACTION_STOP_AUTO_ALARM = "com.devground.daegubus.action.STOP_AUTO_ALARM"
        const val ACTION_SET_ALARM_SOUND = "com.devground.daegubus.action.SET_ALARM_SOUND"
        const val ACTION_SHOW_NOTIFICATION = "com.devground.daegubus.action.SHOW_NOTIFICATION"

        // TTS Output Modes
        const val OUTPUT_MODE_HEADSET = 0  // 이어폰 전용 (현재 AUTO)
        const val OUTPUT_MODE_SPEAKER = 1  // 스피커 전용 (유지)
        const val OUTPUT_MODE_AUTO = 2     // 자동 감지 (현재 HEADSET)

        // Display Modes
        const val DISPLAY_MODE_ALARMED_ONLY = 0

        // Default Values
        const val DEFAULT_ALARM_SOUND = ""
        private const val FLUTTER_DOUBLE_PREFIX = "VGhpcyBpcyB0aGUgcHJlZml4IGZvciBEb3VibGUu"

        // 추가 상수 정의
        private const val MAX_CONSECUTIVE_ERRORS = 3
        private const val ARRIVAL_THRESHOLD_MINUTES = 60

        sealed class ServiceCommand {
            object StopAll : ServiceCommand()
            object StopAutoAlarm : ServiceCommand()
            data class StopRoute(
                val routeId: String,
                val busNo: String,
                val stationName: String,
                val notificationId: Int,
                val isAutoAlarm: Boolean,
                val shouldRemoveFromList: Boolean
            ) : ServiceCommand()
            data class StartTracking(
                val routeId: String,
                val stationId: String,
                val stationName: String,
                val busNo: String,
                val notificationId: Int,
                val isAutoAlarm: Boolean
            ) : ServiceCommand()
            data class StartForegroundTracking(
                val stationId: String?,
                val stationName: String?,
                val busNo: String?
            ) : ServiceCommand()
            object StartAutoAlarmLightweight : ServiceCommand()
            object Unknown : ServiceCommand()
            val isStopCommand: Boolean
                get() = this is StopAll || this is StopAutoAlarm || this is StopRoute
        }
    }

    private val binder = LocalBinder()
    internal val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private lateinit var busApiService: BusApiService
    private lateinit var notificationHandler: NotificationHandler
    private lateinit var notificationUpdater: BusAlertNotificationUpdater
    private lateinit var trackingManager: BusAlertTrackingManager
    private lateinit var ttsController: BusAlertTtsController
    private var useTextToSpeech: Boolean = true
    private var audioOutputMode: Int = OUTPUT_MODE_AUTO
    private var ttsVolume: Float = 1.0f
    internal var isInForeground: Boolean = false

    // Tracking State
    private val monitoringJobs = HashMap<String, Job>()
    private val activeTrackings = HashMap<String, TrackingInfo>()
    private val monitoredRoutes = HashMap<String, Triple<String, String, Job?>>()
    private val cachedBusInfo = HashMap<String, BusInfo>()
    private val arrivingSoonNotified = HashSet<String>()
    private var isTtsTrackingActive = false

    // TTS/Audio variables
    private val ttsInitializationLock = Object()
    private var currentAlarmSound: String = DEFAULT_ALARM_SOUND
    private var notificationDisplayMode: Int = DISPLAY_MODE_ALARMED_ONLY
    private var monitoringTimer: Timer? = null

    // 배터리 최적화를 위한 자동알람 모드
    private var isAutoAlarmMode = false
    private var autoAlarmStartTime = 0L
    private var autoAlarmTimeoutMs = 1800000L // 기본 30분, 설정으로 변경 가능
    private var alertOnArrivalOnly = false // 도착 임박 시에만 알림 (3정거장/3분)

    private val alarmSoundPlayer = BusAlertAlarmSoundPlayer(this)
    private val autoAlarmNotifier = BusAlertAutoAlarmNotifier(this)
    
    // 추적 중지 후 재시작 방지를 위한 플래그
    private var isManuallyStoppedByUser = false
    private var lastManualStopTime = 0L
    private val RESTART_PREVENTION_DURATION = 3000L // 3초간 재시작 방지 (30초 → 3초로 단축)

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service onCreate")
        instance = this
        isServiceActive = true
        busApiService = BusApiService(applicationContext)
        notificationHandler = NotificationHandler(this)
        notificationUpdater = BusAlertNotificationUpdater(this, notificationHandler)
        ttsController = BusAlertTtsController(applicationContext) { /* no-op */ }
        ttsController.initializeTts()
        trackingManager = BusAlertTrackingManager(
            busApiService,
            serviceScope,
            activeTrackings,
            monitoringJobs,
            ::updateBusInfo,
            { b, s, r, c, routeId, summary ->
                showOngoingBusTracking(
                    busNo = b,
                    stationName = s,
                    remainingMinutes = r,
                    currentStation = c,
                    isUpdate = true,
                    notificationId = ONGOING_NOTIFICATION_ID,
                    allBusesSummary = summary,
                    routeId = routeId
                )
            },
            ::updateForegroundNotification,
            ::checkArrivalAndNotify,
            ::checkNextBusAndNotify,
            { routeId, cancelNotification ->
                stopTrackingForRoute(routeId, cancelNotification = cancelNotification)
            },
            ttsController,
            { useTextToSpeech },
            ARRIVAL_THRESHOLD_MINUTES,
        )
        loadSettings()
        notificationHandler.createNotificationChannels()
        Log.i(TAG, "BusAlertService onCreate - 서비스 생성됨")
    }

    private fun loadSettings() {
        try {
            val flutterPrefs = applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

            val flutterAlarmSound = flutterPrefs.getString("flutter.alarm_sound", null)
            val flutterUseTts = flutterPrefs.getBoolean("flutter.use_tts", true)
            currentAlarmSound = flutterAlarmSound ?: DEFAULT_ALARM_SOUND
            useTextToSpeech = flutterUseTts || flutterAlarmSound == "tts"
            ttsController.setUseTts(useTextToSpeech)

            audioOutputMode = flutterPrefs.getLong("flutter.speaker_mode", OUTPUT_MODE_HEADSET.toLong()).toInt()
            ttsController.setAudioOutputMode(audioOutputMode)

            notificationDisplayMode = getFlutterLongPref(flutterPrefs, "notificationDisplayMode", DISPLAY_MODE_ALARMED_ONLY.toLong()).toInt()
            ttsVolume = getFlutterFloatPref(flutterPrefs, "auto_alarm_volume", 1.0f).coerceIn(0f, 1f)
            ttsController.setTtsVolume(ttsVolume)
            autoAlarmTimeoutMs = getFlutterLongPref(flutterPrefs, "auto_alarm_timeout_ms", 1800000L).coerceIn(300000L, 7200000L)
            alertOnArrivalOnly = flutterPrefs.getBoolean("flutter.alert_on_arrival_only", false)
            Log.d(TAG, "⚙️ Settings loaded - TTS: $useTextToSpeech, Sound: $currentAlarmSound, NotifMode: $notificationDisplayMode, Output: $audioOutputMode, Volume: ${ttsVolume * 100}%, FlutterUseTts: $flutterUseTts, FlutterAlarmSound: $flutterAlarmSound, AlertOnArrivalOnly: $alertOnArrivalOnly")
        } catch (e: Exception) {
            Log.e(TAG, "⚙️ Error loading settings: ${e.message}")
        }
    }

    private fun getFlutterLongPref(
        flutterPrefs: android.content.SharedPreferences,
        key: String,
        defaultValue: Long
    ): Long {
        return when (val value = flutterPrefs.all["flutter.$key"]) {
            is Long -> value
            is Int -> value.toLong()
            is String -> value.toLongOrNull() ?: defaultValue
            else -> defaultValue
        }
    }

    private fun getFlutterFloatPref(
        flutterPrefs: android.content.SharedPreferences,
        key: String,
        defaultValue: Float
    ): Float {
        return when (val value = flutterPrefs.all["flutter.$key"]) {
            is Float -> value
            is Double -> value.toFloat()
            is Long -> value.toFloat()
            is Int -> value.toFloat()
            is String -> {
                val normalizedValue = if (value.startsWith(FLUTTER_DOUBLE_PREFIX)) {
                    value.removePrefix(FLUTTER_DOUBLE_PREFIX)
                } else {
                    value
                }
                normalizedValue.toFloatOrNull() ?: defaultValue
            }
            else -> defaultValue
        }
    }

    private fun parseCommand(intent: Intent?): ServiceCommand {
        return when (intent?.action) {
            ACTION_STOP_TRACKING -> ServiceCommand.StopAll
            ACTION_STOP_AUTO_ALARM -> ServiceCommand.StopAutoAlarm
            ACTION_STOP_SPECIFIC_ROUTE_TRACKING -> ServiceCommand.StopRoute(
                routeId = intent.getStringExtra("routeId") ?: return ServiceCommand.Unknown,
                busNo = intent.getStringExtra("busNo") ?: return ServiceCommand.Unknown,
                stationName = intent.getStringExtra("stationName") ?: "",
                notificationId = intent.getIntExtra("notificationId", -1),
                isAutoAlarm = intent.getBooleanExtra("isAutoAlarm", false),
                shouldRemoveFromList = intent.getBooleanExtra("shouldRemoveFromList", true)
            )
            ACTION_START_TRACKING -> ServiceCommand.StartTracking(
                routeId = intent.getStringExtra("routeId") ?: return ServiceCommand.Unknown,
                stationId = intent.getStringExtra("stationId") ?: return ServiceCommand.Unknown,
                stationName = intent.getStringExtra("stationName") ?: "",
                busNo = intent.getStringExtra("busNo") ?: "",
                notificationId = intent.getIntExtra("notificationId", -1),
                isAutoAlarm = intent.getBooleanExtra("isAutoAlarm", false)
            )
            ACTION_START_TRACKING_FOREGROUND, ACTION_UPDATE_TRACKING -> ServiceCommand.StartForegroundTracking(
                stationId = intent.getStringExtra("stationId"),
                stationName = intent.getStringExtra("stationName"),
                busNo = intent.getStringExtra("busNo")
            )
            ACTION_START_AUTO_ALARM_LIGHTWEIGHT -> ServiceCommand.StartAutoAlarmLightweight
            ACTION_CANCEL_NOTIFICATION,
            ACTION_START_TTS_TRACKING,
            ACTION_STOP_TTS_TRACKING,
            ACTION_STOP_BUS_ALERT_TRACKING,
            ACTION_SET_ALARM_SOUND,
            ACTION_SHOW_NOTIFICATION -> ServiceCommand.Unknown
            else -> ServiceCommand.Unknown
        }
    }

override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    Log.i(TAG, "onStartCommand Received: Action = ${intent?.action}, StartId=$startId")

    val command = parseCommand(intent)
    if (!isServiceActive && !command.isStopCommand) {
        Log.w(TAG, "Service not active, ignoring command: $command")
        return START_NOT_STICKY
    }

    loadSettings()

    val action = intent?.action
    val notificationId = intent?.getIntExtra("notificationId", -1) ?: -1
    val remainingMinutes = intent?.getIntExtra("remainingMinutes", -1) ?: -1
    val currentStation = intent?.getStringExtra("currentStation")
    val allBusesSummary = intent?.getStringExtra("allBusesSummary")
    val routeId = intent?.getStringExtra("routeId")
    val isAutoAlarm = intent?.getBooleanExtra("isAutoAlarm", false) ?: false
    val isCommuteAlarm = intent?.getBooleanExtra("isCommuteAlarm", false) ?: false
    val stationId = intent?.getStringExtra("stationId")
    val useTTS = intent?.getBooleanExtra("useTTS", true) ?: true
    val autoAlarmBusNo = intent?.getStringExtra("busNo") ?: ""
    val autoAlarmStationName = intent?.getStringExtra("stationName") ?: ""
    val alarmHour = intent?.getIntExtra("alarmHour", -1) ?: -1
    val alarmMinute = intent?.getIntExtra("alarmMinute", -1) ?: -1

    when (command) {
        is ServiceCommand.StartTracking -> {
            // 🛑 사용자가 수동으로 중지한 직후인지 확인 (재시작 방지)
            if (isManuallyStoppedByUser) {
                val timeSinceStop = System.currentTimeMillis() - lastManualStopTime
                if (timeSinceStop < RESTART_PREVENTION_DURATION) {
                    Log.w(TAG, "⚠️ 사용자가 ${timeSinceStop/1000}초 전에 수동 중지했음 - 추적 시작 거부")
                    return START_NOT_STICKY
                } else {
                    // 30초가 지났으면 플래그 해제
                    isManuallyStoppedByUser = false
                    lastManualStopTime = 0L
                    Log.d(TAG, "✅ 재시작 방지 기간 만료 - 추적 시작 허용")
                }
            }

            Log.i(TAG, "ACTION_START_TRACKING: routeId=${command.routeId}, stationId=${command.stationId}, stationName=${command.stationName}, busNo=${command.busNo}")
            addMonitoredRoute(command.routeId, command.stationId, command.stationName)
            startTracking(command.routeId, command.stationId, command.stationName, command.busNo)
        }
        ServiceCommand.StopAll -> {
            Log.i(TAG, "🛑🛑🛑 ACTION_STOP_TRACKING 수신! 🛑🛑🛑")
            Log.i(TAG, "🛑 Intent Action: $action")
            Log.i(TAG, "🛑 Intent Extras: ${intent?.extras?.keySet()?.joinToString()}")
            Log.i(TAG, "🛑 현재 활성 추적: ${activeTrackings.size}개")
            Log.i(TAG, "🛑 모니터링 작업: ${monitoringJobs.size}개")
            Log.i(TAG, "🛑 포그라운드 상태: $isInForeground")
            Log.i(TAG, "🛑 자동알람 모드: $isAutoAlarmMode")

            // 🛑 사용자가 수동으로 중지했음을 기록 (재시작 방지)
            isManuallyStoppedByUser = true
            lastManualStopTime = System.currentTimeMillis()
            Log.w(TAG, "🛑 사용자 수동 중지 플래그 설정 - 30초간 모든 추적 재시작 차단!")

            // 1단계: 모든 알림 즉시 취소 (최우선)
            try {
                Log.i(TAG, "🛑 1단계: 모든 알림 즉시 취소 시작")
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                
                // 여러 번 시도하여 확실히 취소
                for (attempt in 1..3) {
                    notificationManager.cancel(ONGOING_NOTIFICATION_ID)
                    notificationManager.cancel(AUTO_ALARM_NOTIFICATION_ID)
                    notificationManager.cancelAll()
                    if (attempt < 3) Thread.sleep(50)
                }
                
                Log.i(TAG, "✅ 모든 알림 즉시 취소 완료 (ACTION_STOP_TRACKING)")
            } catch (e: Exception) {
                Log.e(TAG, "❌ 알림 즉시 취소 오류: ${e.message}", e)
            }

            // 2단계: 포그라운드 서비스 즉시 중지
            if (isInForeground) {
                try {
                    Log.i(TAG, "🛑 2단계: 포그라운드 서비스 중지 시작")
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    isInForeground = false
                    Log.d(TAG, "✅ 포그라운드 서비스 중지 완료")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 포그라운드 서비스 중지 오류: ${e.message}", e)
                }
            }

            // 3단계: 자동 알람 WorkManager 작업 취소
            try {
                Log.i(TAG, "🛑 3단계: WorkManager 작업 취소 시작")
                val workManager = androidx.work.WorkManager.getInstance(this)
                workManager.cancelAllWorkByTag("autoAlarmTask")
                Log.d(TAG, "✅ 자동 알람 WorkManager 작업 취소 완료")
            } catch (e: Exception) {
                Log.e(TAG, "❌ 자동 알람 WorkManager 작업 취소 오류: ${e.message}", e)
            }

            // 4단계: 전체 취소 이벤트 발송
            Log.i(TAG, "🛑 4단계: 취소 이벤트 브로드캐스트 시작")
            sendAllCancellationBroadcast()

            // 5단계: 모든 추적 작업과 서비스 중지
            Log.i(TAG, "🛑 5단계: 모든 추적 작업 중지 시작")
            stopAllTracking()
            
            Log.i(TAG, "✅✅✅ ACTION_STOP_TRACKING 처리 완료! ✅✅✅")
            return START_NOT_STICKY
        }
        is ServiceCommand.StopRoute -> {
            Log.i(TAG, "ACTION_STOP_SPECIFIC_ROUTE_TRACKING: routeId=${command.routeId}, busNo=${command.busNo}, stationName=${command.stationName}, notificationId=${command.notificationId}, isAutoAlarm=${command.isAutoAlarm}, shouldRemoveFromList=${command.shouldRemoveFromList}")
                
            // 📌 자동알람인 경우 Flutter 측에 명시적으로 중지 요청
            if (command.isAutoAlarm) {
                Log.d(TAG, "🔔 자동알람 중지 요청: 전체 추적 중지 호출")
                stopAllBusTracking() // 자동알람인 경우 전체 중지
                
                // 자동알람 전용 브로드캐스트 전송
                try {
                    val autoAlarmIntent = Intent("com.devground.daegubus.STOP_AUTO_ALARM")
                    autoAlarmIntent.putExtra("busNo", command.busNo)
                    autoAlarmIntent.putExtra("stationName", command.stationName)
                    autoAlarmIntent.putExtra("routeId", command.routeId)
                    autoAlarmIntent.flags = Intent.FLAG_INCLUDE_STOPPED_PACKAGES
                    sendBroadcast(autoAlarmIntent)
                    Log.d(TAG, "✅ 자동알람 중지 브로드캐스트 전송 완료")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 자동알람 중지 브로드캐스트 전송 실패: ${e.message}")
                }
            } else {
                // 일반 알람인 경우 특정 추적만 중지
                stopSpecificTracking(command.routeId, command.busNo, command.stationName, command.shouldRemoveFromList)
                Log.d(TAG, "노티피케이션 종료: 알람 리스트 유지 여부: ${command.shouldRemoveFromList} (${command.busNo})")
            }

            // 📌 Flutter로 직접 메서드 채널을 통해 이벤트 전송
            try {
                val alarmCancelData = mapOf(
                    "busNo" to command.busNo,
                    "routeId" to command.routeId,
                    "stationName" to command.stationName
                )
                MainActivity.sendFlutterEvent("onAlarmCanceledFromNotification", alarmCancelData)
                Log.d(TAG, "✅ Flutter 메서드 채널로 알람 취소 이벤트 전송 완료")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Flutter 메서드 채널 이벤트 전송 실패: ${e.message}")
            }
        }
        is ServiceCommand.StartForegroundTracking -> {
            // 🛑 새로운 추적 시작인 경우만 재시작 방지 로직 적용 (UPDATE는 제외)
            if (action == ACTION_START_TRACKING_FOREGROUND && isManuallyStoppedByUser) {
                val timeSinceStop = System.currentTimeMillis() - lastManualStopTime
                if (timeSinceStop < RESTART_PREVENTION_DURATION) {
                    Log.w(TAG, "⚠️ 사용자가 ${timeSinceStop/1000}초 전에 수동 중지했음 - 포그라운드 추적 시작 거부")
                    return START_NOT_STICKY
                } else {
                    // 30초가 지났으면 플래그 해제
                    isManuallyStoppedByUser = false
                    lastManualStopTime = 0L
                    Log.d(TAG, "✅ 재시작 방지 기간 만료 - 포그라운드 추적 시작 허용")
                }
            }

            val busNo = command.busNo ?: ""
            val stationName = command.stationName ?: ""
            val isUpdate = action == ACTION_UPDATE_TRACKING
            var resolvedStationId = command.stationId

            Log.d(TAG, "🔔 자동알람 플래그 확인: isAutoAlarm=$isAutoAlarm, busNo=$busNo, stationName=$stationName")
            Log.d(TAG, "🔔 자동알람 상세 정보: routeId=$routeId, stationId=$resolvedStationId, remainingMinutes=$remainingMinutes, currentStation=$currentStation")

            if (routeId == null || busNo.isBlank() || stationName.isBlank()) {
                Log.e(TAG, "$action Aborted: Missing required info")
                stopTrackingIfIdle()
                return START_NOT_STICKY
            }

            // --- stationId 보정 로직 추가 ---
            if (resolvedStationId.isNullOrBlank()) {
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

            // 자동알람인 경우 무조건 추적 시작 (ACTION에 관계없이)
            if (isAutoAlarm && resolvedStationId != null) {
                Log.d(TAG, "🔔 자동알람 감지: 무조건 추적 시작 - $busNo 번, $stationName")
                addMonitoredRoute(routeId, resolvedStationId, stationName)
                
                // 이미 추적 중이어도 자동알람은 강제로 재시작
                if (monitoringJobs.containsKey(routeId)) {
                    Log.d(TAG, "🔔 자동알람: 기존 추적 중지 후 재시작 - $routeId")
                    monitoringJobs[routeId]?.cancel()
                    monitoringJobs.remove(routeId)
                }
                
                startTracking(routeId, resolvedStationId, stationName, busNo, isAutoAlarm = true, isCommuteAlarm = isCommuteAlarm)
            } else if (action == ACTION_START_TRACKING_FOREGROUND && resolvedStationId != null) {
                // 일반 추적 시작
                addMonitoredRoute(routeId, resolvedStationId, stationName)
                startTracking(routeId, resolvedStationId, stationName, busNo)
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
                
                // 📌 중요: 업데이트 시 즉시 노티피케이션 갱신 (기존 로직은 showOngoingBusTracking 호출에 의존)
                // 하지만 showOngoingBusTracking이 아래에서 호출되므로 중복 호출 방지를 위해 여기서는 로그만 남김
                Log.d(TAG, "🔔 업데이트 요청에 따른 노티피케이션 갱신 예정")
            }

            // 자동알람인 경우 강제로 노티피케이션 표시
            if (isAutoAlarm) {
                Log.d(TAG, "🔔 자동알람 노티피케이션 강제 표시: $busNo 번, $stationName")

                // 자동알람의 경우 무조건 포그라운드 서비스 시작
                try {
                    if (!isInForeground) {
                        val notification = notificationHandler.buildOngoingNotification(mapOf())
                        if (Build.VERSION.SDK_INT >= 36) {
                            startForeground(
                                ONGOING_NOTIFICATION_ID,
                                notification,
                                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                            )
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            startForeground(
                                ONGOING_NOTIFICATION_ID,
                                notification,
                                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                            )
                        } else {
                            startForeground(ONGOING_NOTIFICATION_ID, notification)
                        }
                        isInForeground = true
                        Log.d(TAG, "🔔 자동알람: 포그라운드 서비스 시작")
                    }

                    showOngoingBusTracking(
                        busNo = busNo,
                        stationName = stationName,
                        remainingMinutes = remainingMinutes,
                        currentStation = currentStation ?: "정보 없음",
                        isUpdate = false, // 자동알람은 새로운 추적으로 처리
                        notificationId = ONGOING_NOTIFICATION_ID,
                        allBusesSummary = allBusesSummary,
                        routeId = routeId
                    )

                    Log.d(TAG, "✅ 자동알람 노티피케이션 표시 완료")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 자동알람 노티피케이션 표시 오류: ${e.message}", e)
                }
            } else {
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
            // [AUTO ALARM 실시간 정보 즉시 갱신] autoAlarmTask 등 자동알람 진입점에서 실시간 정보 즉시 fetch
            if (!routeId.isBlank() && !resolvedStationId.isNullOrBlank() && stationName.isNotBlank()) {
                updateBusInfo(routeId, resolvedStationId, stationName)
            }
        }
        ServiceCommand.StartAutoAlarmLightweight -> {
            // 🛑 사용자가 수동으로 중지한 직후인지 확인 (재시작 방지)
            if (isManuallyStoppedByUser) {
                val timeSinceStop = System.currentTimeMillis() - lastManualStopTime
                if (timeSinceStop < RESTART_PREVENTION_DURATION) {
                    Log.w(TAG, "⚠️ 사용자가 ${timeSinceStop/1000}초 전에 수동 중지했음 - 자동 알람 시작 거부")
                    return START_NOT_STICKY
                } else {
                    // 30초가 지났으면 플래그 해제
                    isManuallyStoppedByUser = false
                    lastManualStopTime = 0L
                    Log.d(TAG, "✅ 재시작 방지 기간 만료 - 자동 알람 시작 허용")
                }
            }

            val currentStationText = currentStation ?: ""
            val routeIdText = routeId ?: ""
            val stationIdText = stationId ?: ""

            // 이미 같은 노선 자동알람 추적 중이면 재시작 방지 (이중 트리거 차단)
            if (isAutoAlarmMode && currentAutoAlarmRouteId == routeIdText && routeIdText.isNotBlank()) {
                Log.w(TAG, "⚠️ 자동알람 이미 추적 중: $autoAlarmBusNo ($routeIdText) - 중복 시작 무시")
                return START_NOT_STICKY
            }

            Log.d(TAG, "🔔 자동알람 경량화 모드 시작: $autoAlarmBusNo 번, $autoAlarmStationName, TTS=$useTTS")
            handleAutoAlarmLightweight(autoAlarmBusNo, autoAlarmStationName, remainingMinutes, currentStationText, routeIdText, stationIdText, useTTS, isCommuteAlarm, alarmHour, alarmMinute)
        }
        ServiceCommand.StopAutoAlarm -> {
            Log.i(TAG, "🛑 ACTION_STOP_AUTO_ALARM received")

            // 사용자 수동 중지 플래그 설정 (자동 알람 재시작 방지)
            isManuallyStoppedByUser = true
            lastManualStopTime = System.currentTimeMillis()
            Log.w(TAG, "🛑 사용자 수동 중지 플래그 설정 (자동알람 중지)")

            // 자동알람 전체 종료: 경량화 알림 + 모든 추적 중지
            try {
                stopAutoAlarmLightweight()
            } catch (_: Exception) { }

            // Flutter에 취소 이벤트 전달
            try {
                sendAllCancellationBroadcast()
            } catch (_: Exception) { }

            stopAllBusTracking()
            return START_NOT_STICKY
        }
        ServiceCommand.Unknown -> {
            Log.w(TAG, "Unhandled action received: $action")
            return START_NOT_STICKY
        }
    }

    return START_STICKY
}

    // MainActivity에서 호출하는 래퍼 함수들
    fun startBusTracking(busNo: String, stationName: String, routeId: String) {
        val stationId = activeTrackings[routeId]?.stationId ?: ""
        if (stationId.isNotEmpty()) {
            startTracking(routeId, stationId, stationName, busNo)
        } else {
            Log.e(TAG, "Cannot start tracking, stationId not found for routeId: $routeId")
        }
    }

    fun stopBusTracking(busNo: String, stationName: String, routeId: String) {
        stopSpecificTracking(routeId, busNo, stationName, shouldRemoveFromList = true)
    }

    // 모든 추적 중지 (MainActivity 호출용)
    fun stopAllBusTracking() {
        stopAllTracking()
    }

// 특정 버스 추적 중지
    private fun stopSpecificTracking(routeId: String, busNo: String, stationName: String, shouldRemoveFromList: Boolean = true) {
        Log.d(TAG, "🔔 특정 추적 중지 시작: routeId=$routeId, busNo=$busNo, stationName=$stationName")

        if (!isServiceActive) {
            Log.w(TAG, "서비스가 비활성 상태입니다. 특정 추적 중지 무시")
            return
        }

        try {
            // 0. 자동알람 여부 확인 및 WorkManager 작업 취소
            val trackingInfo = activeTrackings[routeId]
            val isAutoAlarmTracking = trackingInfo?.isAutoAlarm ?: false
            
            if (isAutoAlarmTracking) {
                Log.d(TAG, "🔔 자동알람 추적 중지 감지: WorkManager 작업 취소 시작")
                try {
                    val workManager = androidx.work.WorkManager.getInstance(this)
                    
                    // 1. 전체 자동알람 작업 취소
                    workManager.cancelAllWorkByTag("autoAlarmTask")
                    
                    // 2.1. alarmId를 사용하여 특정 WorkManager 작업 취소
                    trackingInfo?.alarmId?.let { alarmId ->
                        workManager.cancelAllWorkByTag("autoAlarmScheduling_${alarmId}")
                        Log.d(TAG, "✅ 특정 자동알람 WorkManager 작업 취소 완료: autoAlarmScheduling_${alarmId}")
                    }
                    
                    // 3. 모든 대기 중인 작업 취소 (백업)
                    workManager.cancelAllWork()
                    
                    Log.d(TAG, "✅ 자동알람 WorkManager 작업 취소 완료: $busNo ($routeId)")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 자동알람 WorkManager 작업 취소 오류: ${e.message}", e)
                }
                
                // 자동알람 모드 비활성화
                isAutoAlarmMode = false
                autoAlarmStartTime = 0L
                
                Log.d(TAG, "✅ 자동알람 상태 초기화 완료")
            }

            // 1. 추적 작업 및 상태 정리 (알람 리스트는 shouldRemoveFromList에 따라 결정)
            Log.d(TAG, "🔔 1단계: 추적 작업 중지 (리스트 삭제: $shouldRemoveFromList)")
            
            // 모니터링 작업은 항상 중지
            monitoringJobs[routeId]?.cancel()
            monitoringJobs.remove(routeId)
            
            // 상태 정리는 항상 수행
            arrivingSoonNotified.remove(routeId)
            hasNotifiedTts.remove(routeId)
            hasNotifiedArrival.remove(routeId)
            
            // 📌 중요: 알람 리스트는 shouldRemoveFromList가 true일 때만 삭제
            if (shouldRemoveFromList) {
                monitoredRoutes.remove(routeId)
                activeTrackings.remove(routeId)
                Log.d(TAG, "✅ 알람 리스트에서 완전 삭제: $routeId")
            } else {
                Log.d(TAG, "✅ 알람 리스트 유지: $routeId (TTS만 중지)")
            }

            // 2. 강화된 알림 취소
            Log.d(TAG, "🔔 2단계: 강화된 알림 취소")
            val notificationManagerCompat = NotificationManagerCompat.from(this)
            val systemNotificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val specificNotificationId = generateNotificationId(routeId)

            // 개별 알림 취소 (이중 보장)
            try {
                notificationManagerCompat.cancel(specificNotificationId)
                systemNotificationManager.cancel(specificNotificationId)
                Log.d(TAG, "✅ 개별 알림 취소됨: ID=$specificNotificationId")
            } catch (e: Exception) {
                Log.e(TAG, "❌ 개별 알림 취소 실패: ID=$specificNotificationId, 오류=${e.message}")
            }

            // 자동알람 전용 알림도 취소 (이중 보장)
            if (isAutoAlarmTracking) {
                try {
                    notificationManagerCompat.cancel(AUTO_ALARM_NOTIFICATION_ID)
                    systemNotificationManager.cancel(AUTO_ALARM_NOTIFICATION_ID)
                    Log.d(TAG, "✅ 자동알람 전용 알림 취소됨: ID=$AUTO_ALARM_NOTIFICATION_ID")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 자동알람 전용 알림 취소 실패: ${e.message}")
                }
            }

            // 강제 알림 취소 (로그에서 보인 모든 ID들)
            try {
                val forceIds = listOf(916311223, 954225315, 1, 10000, specificNotificationId, AUTO_ALARM_NOTIFICATION_ID, ONGOING_NOTIFICATION_ID)
                for (id in forceIds) {
                    systemNotificationManager.cancel(id)
                }
                Log.d(TAG, "✅ 강제 알림 취소 완료: ${forceIds.size}개 ID")
            } catch (e: Exception) {
                Log.e(TAG, "❌ 강제 알림 취소 실패: ${e.message}")
            }

            // 통합 알림 갱신 또는 취소
            if (activeTrackings.isEmpty()) {
                try {
                    // 통합 알림 취소 (이중 보장)
                    notificationManagerCompat.cancel(ONGOING_NOTIFICATION_ID)
                    systemNotificationManager.cancel(ONGOING_NOTIFICATION_ID)
                    
                    // 포그라운드 서비스 강제 중지
                    if (isInForeground) {
                        try {
                            stopForeground(STOP_FOREGROUND_REMOVE)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ stopForeground 실패, 재시도: ${e.message}")
                            try {
                                stopForeground(true) // 레거시 방법으로 재시도
                            } catch (e2: Exception) {
                                Log.e(TAG, "❌ stopForeground 완전 실패: ${e2.message}")
                            }
                        }
                        isInForeground = false
                        Log.d(TAG, "✅ 포그라운드 서비스 강제 중지")
                    }
                    
                    // 모든 알림 강제 취소 (최후 수단)
                    try {
                        systemNotificationManager.cancelAll()
                        Log.d(TAG, "✅ 모든 알림 강제 취소 완료")
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ 모든 알림 강제 취소 실패: ${e.message}")
                    }
                    
                    Log.d(TAG, "✅ 통합 알림 및 포그라운드 서비스 완전 정리")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 통합 알림/포그라운드 중지 실패: ${e.message}")
                }
            } else {
                updateForegroundNotification()
                Log.d(TAG, "📱 다른 추적이 남아있어 포그라운드 알림 갱신")
            }

            // 3. Flutter에 알림 (자동알람인 경우 특별한 이벤트 전송)
            Log.d(TAG, "🔔 3단계: Flutter 이벤트 전송")
            if (isAutoAlarmTracking) {
                // 자동알람 전용 취소 이벤트 전송
                try {
                    val cancelAutoAlarmIntent = Intent("com.devground.daegubus.AUTO_ALARM_CANCELLED").apply {
                        putExtra("busNo", busNo)
                        putExtra("routeId", routeId)
                        putExtra("stationName", stationName)
                        flags = Intent.FLAG_INCLUDE_STOPPED_PACKAGES
                    }
                    sendBroadcast(cancelAutoAlarmIntent)
                    Log.d(TAG, "✅ 자동알람 취소 이벤트 브로드캐스트 전송: $busNo")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 자동알람 취소 이벤트 전송 오류: ${e.message}")
                }
            }
            sendCancellationBroadcast(busNo, routeId, stationName)

            // 4. TTS 중지
            ttsController.stopTtsServiceTracking()
            Log.d(TAG, "✅ TTS 추적 중지: $routeId")

            // 5. 서비스 상태 확인 (shouldRemoveFromList가 true이고 모든 추적이 끝났을 때만 서비스 중지)
            if (shouldRemoveFromList) {
                Log.d(TAG, "🔔 4단계: 서비스 상태 확인 (남은 추적: ${activeTrackings.size}개)")
                // [수정] activeTrackings가 비어있으면 강제로 서비스 중지 시도 (좀 더 적극적인 종료)
                if (activeTrackings.isEmpty()) {
                     Log.i(TAG, "🔔 모든 추적 종료됨. 서비스 중지 요청.")
                     stopAllTracking() // 확실한 정리를 위해 호출
                     stopSelf()
                } else {
                    checkAndStopServiceIfNeeded()
                }
            } else {
                Log.d(TAG, "🔔 4단계: 알람 리스트 유지 모드 - 서비스 계속 실행")
                // 알람이 리스트에 남아있으므로 포그라운드 알림 업데이트
                updateForegroundNotification()
            }

            Log.d(TAG, "✅ 특정 추적 중지 완료: $routeId (자동알람: $isAutoAlarmTracking, 리스트삭제: $shouldRemoveFromList)")

        } catch (e: Exception) {
            Log.e(TAG, "❌ 특정 추적 중지 중 오류 발생: ${e.message}", e)
            try {
                // 오류 복구 (자동알람 관련 정리 포함)
                if (activeTrackings[routeId]?.isAutoAlarm == true) {
                    try {
                        val workManager = androidx.work.WorkManager.getInstance(this)
                        workManager.cancelAllWorkByTag("autoAlarmTask")
                        workManager.cancelAllWorkByTag("autoAlarm_$busNo")
                        isAutoAlarmMode = false
                        Log.d(TAG, "⚠️ 오류 복구: 자동알람 WorkManager 작업 취소")
                    } catch (cleanupError: Exception) {
                        Log.e(TAG, "❌ 자동알람 오류 복구 실패: ${cleanupError.message}")
                    }
                }
                
                monitoringJobs[routeId]?.cancel()
                monitoringJobs.remove(routeId)
                activeTrackings.remove(routeId)
                monitoredRoutes.remove(routeId)
                NotificationManagerCompat.from(this).cancel(generateNotificationId(routeId))
                NotificationManagerCompat.from(this).cancel(AUTO_ALARM_NOTIFICATION_ID)
                updateForegroundNotification()
                checkAndStopServiceIfNeeded()
                Log.d(TAG, "⚠️ 오류 복구: 최소한의 정리 작업 완료")
            } catch (cleanupError: Exception) {
                Log.e(TAG, "❌ 오류 복구 실패: ${cleanupError.message}")
            }
        }
    }

    // 노티피케이션 ID 생성
    private fun generateNotificationId(routeId: String): Int {
        return routeId.hashCode()
    }

    // UPDATE_TRACKING 처리
    private fun handleUpdateTracking(intent: Intent?) {
        val busNo = intent?.getStringExtra("busNo") ?: ""
        val remainingTime = intent?.getStringExtra("remainingTime") ?: ""
        val currentLocation = intent?.getStringExtra("currentLocation") ?: ""
        val routeId = intent?.getStringExtra("routeId") ?: ""
        val stationName = intent?.getStringExtra("stationName") ?: ""
        val remainingMinutes = intent?.getIntExtra("remainingMinutes", -1) ?: -1

        Log.d(TAG, "UPDATE_TRACKING 처리: $busNo, $remainingTime, $currentLocation")

        // 업데이트 로직 처리
        if (routeId.isNotEmpty() && busNo.isNotEmpty()) {
            updateTrackingInfoFromFlutter(
                routeId = routeId,
                busNo = busNo,
                stationName = stationName,
                remainingMinutes = remainingMinutes,
                currentStation = currentLocation
            )
        }
    }
    override fun onDestroy() {
        Log.i(TAG, "BusAlertService onDestroy - 서비스 종료됨")

        isServiceActive = false
        instance = null

        // 알람 사운드 정리
        alarmSoundPlayer.stop()

        // 모든 리소스 정리
        stopAllTracking()
        ttsController.cleanupTts()

        super.onDestroy()
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    inner class LocalBinder : Binder() {
        fun getService(): BusAlertService = this@BusAlertService
    }

    private fun startTracking(routeId: String, stationId: String, stationName: String, busNo: String, isAutoAlarm: Boolean = false, alarmId: Int? = null, isCommuteAlarm: Boolean = false) {
        serviceScope.launch {
            try {
                Log.d(TAG, "🚀 startTracking 코루틴 시작: $busNo ($routeId), stationId=$stationId, isAutoAlarm=$isAutoAlarm")
                var realStationId = stationId
                if (stationId.length < 10 || !stationId.startsWith("7")) {
                    // 변환 필요
                    realStationId = busApiService.getStationIdFromBsId(stationId) ?: stationId
                    Log.d(TAG, "stationId 변환: $stationId → $realStationId")
                }
                startTrackingInternal(routeId, realStationId, stationName, busNo, isAutoAlarm, alarmId, isCommuteAlarm)
            } catch (e: Exception) {
                Log.e(TAG, "❌ startTracking 코루틴 오류: $busNo ($routeId): ${e.message}", e)
            }
        }
    }

    private suspend fun startTrackingInternal(routeId: String, stationId: String, stationName: String, busNo: String, isAutoAlarm: Boolean = false, alarmId: Int? = null, isCommuteAlarm: Boolean = false) {
        trackingManager.startTrackingInternal(routeId, stationId, stationName, busNo, isAutoAlarm, alarmId, isCommuteAlarm)
        // 백업 타이머 시작 - 메인 업데이트 실패 대비
        startBackupUpdateTimer()
    }

    // 경량화된 백업 업데이트 (메모리 효율적)
    private fun startBackupUpdateTimer() {
        // 기존 타이머가 있으면 정리
        stopMonitoringTimer()

        monitoringTimer = Timer("BackupUpdateTimer")
        monitoringTimer?.schedule(object : TimerTask() {
            override fun run() {
                // 메인 스레드에서만 activeTrackings 접근 (동시성 안전)
                Handler(Looper.getMainLooper()).post {
                    try {
                        if (activeTrackings.isEmpty()) {
                            Log.d(TAG, "백업 타이머: 활성 추적 없음, 타이머 종료")
                            stopMonitoringTimer()
                            return@post
                        }

                        // 60초로 변경하여 리소스 사용량 감소
                        Log.d(TAG, "🔄 백업 타이머: 알림 갱신 (${activeTrackings.size}개)")
                        updateForegroundNotification()
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ 백업 타이머 알림 업데이트 실패: ${e.message}")
                    }
                }
            }
        }, 30000, 60000)  // 30초 후 시작, 60초마다 반복 (리소스 절약)

        Log.d(TAG, "✅ 경량화된 백업 타이머 시작됨")
    }
    // 버스 업데이트 함수 개선
    private fun updateBusInfo(routeId: String, stationId: String, stationName: String) {
        try {
            serviceScope.launch {
                try {
                    val jsonString = busApiService.getStationInfo(stationId)
                    val busInfoList = parseJsonBusArrivals(jsonString, routeId)

                    // 운행종료가 아닌 버스 중에서 첫 번째 선택
                    val firstBus = busInfoList.firstOrNull { bus ->
                        !bus.isOutOfService &&
                        !bus.estimatedTime.contains("운행종료") &&
                        bus.estimatedTime != "-"
                    }

                    Log.d(TAG, "🔍 [updateBusInfo] 버스 목록: ${busInfoList.size}개, 유효한 버스: ${firstBus != null}")
                    busInfoList.forEachIndexed { index, bus ->
                        Log.d(TAG, "  [$index] ${bus.busNumber}: ${bus.estimatedTime} (운행종료: ${bus.isOutOfService})")
                    }
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

    // Flutter에서 버스 정보 업데이트 수신 (공개 함수)
    fun updateBusInfoFromFlutter(
        routeId: String,
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String?,
        estimatedTime: String?,
        isLowFloor: Boolean
    ) {
        try {
            Log.d(TAG, "🔄 Flutter에서 버스 정보 업데이트 수신: $busNo, $stationName, ${remainingMinutes}분")
            
            // 추적 정보가 없으면 무시
            val trackingInfo = activeTrackings[routeId]
            if (trackingInfo == null) {
                Log.w(TAG, "⚠️ 추적 정보 없음 (routeId: $routeId). 업데이트 무시")
                return
            }
            
            // BusInfo 업데이트
            val updatedBusInfo = BusInfo(
                currentStation = currentStation ?: "정보 없음",
                estimatedTime = estimatedTime ?: "${remainingMinutes}분",
                remainingStops = trackingInfo.lastBusInfo?.remainingStops ?: "0",
                busNumber = busNo,
                isLowFloor = isLowFloor
            )
            
            trackingInfo.lastBusInfo = updatedBusInfo
            trackingInfo.consecutiveErrors = 0 // 성공적으로 업데이트되었으므로 오류 카운트 리셋
            
            // 노티피케이션 즉시 갱신
            updateForegroundNotification()
            
            Log.d(TAG, "✅ Flutter 버스 정보 업데이트 완료: $busNo, 현재 위치: ${updatedBusInfo.currentStation}, 예상 시간: ${updatedBusInfo.estimatedTime}")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Flutter 버스 정보 업데이트 오류: ${e.message}", e)
        }
    }

    fun initialize() {
        Log.d(TAG, "Service initialize called")
        busApiService = BusApiService(applicationContext)
        notificationHandler = NotificationHandler(this)
        notificationUpdater = BusAlertNotificationUpdater(this, notificationHandler)
        if (!::ttsController.isInitialized) {
            ttsController = BusAlertTtsController(applicationContext) { /* no-op */ }
            ttsController.initializeTts()
        }
        trackingManager = BusAlertTrackingManager(
            busApiService,
            serviceScope,
            activeTrackings,
            monitoringJobs,
            ::updateBusInfo,
            { b, s, r, c, routeId, summary ->
                showOngoingBusTracking(
                    busNo = b,
                    stationName = s,
                    remainingMinutes = r,
                    currentStation = c,
                    isUpdate = true,
                    notificationId = ONGOING_NOTIFICATION_ID,
                    allBusesSummary = summary,
                    routeId = routeId
                )
            },
            ::updateForegroundNotification,
            ::checkArrivalAndNotify,
            ::checkNextBusAndNotify,
            { routeId, cancelNotification ->
                stopTrackingForRoute(routeId, cancelNotification = cancelNotification)
            },
            ttsController,
            { useTextToSpeech },
            ARRIVAL_THRESHOLD_MINUTES,
        )
        loadSettings()
        notificationHandler.createNotificationChannels()
    }

    fun addMonitoredRoute(routeId: String, stationId: String, stationName: String) {
        monitoredRoutes[routeId] = Triple(stationId, stationName, monitoringJobs[routeId])
        Log.d(TAG, "Added route to monitored list: $routeId at $stationName ($stationId)")
    }

    // stationId 보정 함수 (정류장 이름 매핑 우선)
    private suspend fun resolveStationIdIfNeeded(routeId: String, stationName: String, stationId: String, wincId: String?): String {
        if (stationId.length == 10 && stationId.startsWith("7")) return stationId

        // 1. 정류장 이름 기반 매핑 우선 사용
        val mappedStationId = getStationIdFromName(stationName)
        if (mappedStationId.isNotEmpty() && mappedStationId != routeId) {
            Log.d(TAG, "resolveStationIdIfNeeded: stationName=$stationName → mappedStationId=$mappedStationId")
            return mappedStationId
        }

        // 2. wincId가 있으면 사용
        if (!wincId.isNullOrBlank()) {
            val fixed = busApiService.getStationIdFromBsId(wincId)
            if (!fixed.isNullOrBlank()) {
                Log.d(TAG, "resolveStationIdIfNeeded: wincId=$wincId → stationId=$fixed")
                return fixed
            }
        }
        // 3. routeId로 노선 정류장 리스트 조회 후, stationName 유사 매칭(보조)
        val stations = busApiService.getBusRouteMap(routeId)
        val found = stations.find { normalize(it.stationName) == normalize(stationName) }
        if (found != null && found.stationId.isNotBlank()) {
            Log.d(TAG, "resolveStationIdIfNeeded: routeId=$routeId, stationName=$stationName → stationId=${found.stationId}")
            return found.stationId
        }
        // 4. 그래도 안되면 stationName을 wincId로 간주
        val fallback = busApiService.getStationIdFromBsId(stationName)
        if (!fallback.isNullOrBlank()) {
            Log.d(TAG, "resolveStationIdIfNeeded: fallback getStationIdFromBsId($stationName) → $fallback")
            return fallback
        }
        Log.w(TAG, "resolveStationIdIfNeeded: stationId 보정 실패 (routeId=$routeId, stationName=$stationName, wincId=$wincId)")
        return ""
    }

    private fun normalize(name: String) = name.replace("\\s".toRegex(), "").replace("[^\\p{L}\\p{N}]".toRegex(), "")

    // 정류장 이름으로 stationId 매핑
    private fun getStationIdFromName(stationName: String): String {
        val stationMapping = mapOf(
            "새동네아파트앞" to "7021024000",
            "새동네아파트건너" to "7021023900",
            "칠성고가도로하단" to "7021051300",
            "대구삼성창조캠퍼스3" to "7021011000",
            "대구삼성창조캠퍼스" to "7021011200",
            "동대구역" to "7021052100",
            "동대구역건너" to "7021052000",
            "경명여고건너" to "7021024200",
            "경명여고" to "7021024100"
        )

        // 정확한 매칭 시도
        stationMapping[stationName]?.let { return it }

        // 부분 매칭 시도
        for ((key, value) in stationMapping) {
            if (stationName.contains(key) || key.contains(stationName)) {
                return value
            }
        }

        return ""
    }

    // showOngoingBusTracking에서 wincId 파라미터 추가
    fun showOngoingBusTracking(
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String?,
        isUpdate: Boolean, // 이 플래그는 이제 알림을 새로 생성할지, 기존 알림을 업데이트할지를 결정합니다.
        notificationId: Int, // ONGOING_NOTIFICATION_ID 또는 개별 알림 ID
        allBusesSummary: String?,
        routeId: String?,
        stationId: String? = null,
        wincId: String? = null,
        isIndividualAlarm: Boolean = false // 이 알림이 개별 도착 알람인지 여부
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

        Log.d(TAG, "🔄 showOngoingBusTracking: $busNo, $stationName, $remainingMinutes, currentStation='$currentStation', isIndividualAlarm=$isIndividualAlarm, notificationId=$notificationId")

        // stationId 보정
        var effectiveStationId = stationId ?: trackingInfo.stationId
        if (effectiveStationId.isBlank() || effectiveStationId.length < 10 || !effectiveStationId.startsWith("7")) {
            serviceScope.launch {
                val fixedStationId = resolveStationIdIfNeeded(effectiveRouteId, stationName, effectiveStationId, wincId)
                if (fixedStationId.isNotBlank()) {
                    showOngoingBusTracking(
                        busNo, stationName, remainingMinutes, currentStation, isUpdate, notificationId, allBusesSummary, routeId, fixedStationId, wincId, isIndividualAlarm
                    )
                } else {
                    Log.e(TAG, "❌ stationId 보정 실패: $routeId, $busNo, $stationName")
                }
            }
            return
        }

        // BusInfo 생성 (remainingMinutes는 BusInfo에서 파생)
        // 운행종료 판단 로직 개선 - 기점출발예정, 차고지행 등은 운행종료가 아님
        val isOutOfService = (currentStation?.contains("운행종료") == true) ||
                            (trackingInfo.lastBusInfo?.estimatedTime?.contains("운행종료") == true) ||
                            (currentStation?.contains("차고지") == true && remainingMinutes < 0)

        Log.d(TAG, "🔍 [BusAlertService] 운행종료 판단: remainingMinutes=$remainingMinutes, currentStation='$currentStation', isOutOfService=$isOutOfService")

        val busInfo = BusInfo(
            currentStation = currentStation ?: "정보 없음",
            estimatedTime = if (isOutOfService) "운행종료" else when {
                remainingMinutes < 0 -> currentStation ?: "정보 없음" // 기점출발예정 등의 정보 표시
                remainingMinutes == 0 -> "곧 도착"
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
        val formattedTime = when (val busMinutes = busInfo.getRemainingMinutes()) { // 변수명 변경
            in Int.MIN_VALUE..0 -> if (busInfo.estimatedTime.isNotEmpty()) busInfo.estimatedTime else "정보 없음"
            1 -> "1분"
            else -> "${busMinutes}분"
        }
        val currentStationFinal = busInfo.currentStation

        Log.d(TAG, "✅ lastBusInfo 갱신: $busNo, $formattedTime, '$currentStationFinal'")

        // TTS 알림은 startTrackingInternal에서 직접 처리하므로 이 블록은 제거합니다.

        // 알림 갱신 (통합 알림으로 통일)
        try {
            notificationUpdater.updateOngoing(
                ONGOING_NOTIFICATION_ID,
                activeTrackings,
                isInForeground
            ) { newValue ->
                isInForeground = newValue
            }

            Log.d(TAG, "✅ 알림 통합 업데이트: $busNo, $formattedTime, $currentStationFinal, ID=$ONGOING_NOTIFICATION_ID")

            // 백업 업데이트 (항상 실행)
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    val backup = notificationUpdater.buildOngoing(activeTrackings)
                    val notificationManager =
                        getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.notify(ONGOING_NOTIFICATION_ID, backup)
                } catch (_: Exception) {}
            }, 1000)

            // 자동알람 모드일 때 자동알람 알림도 실시간 업데이트
            if (isAutoAlarmMode) {
                val busInfo = activeTrackings.values.firstOrNull()?.lastBusInfo
                autoAlarmNotifier.updateWithData(
                    busNo = busNo,
                    stationName = stationName,
                    remainingMinutes = busInfo?.getRemainingMinutes() ?: remainingMinutes,
                    remainingStops = busInfo?.remainingStops ?: "0",
                    currentStation = currentStationFinal,
                    routeTCd = activeTrackings.values.firstOrNull()?.routeTCd
                )
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ 알림 ${if(isIndividualAlarm) "생성" else "업데이트"} 오류: ${e.message}", e)
            if (!isIndividualAlarm) { // 개별 알람이 아닐 때만 포그라운드 알림 업데이트 시도
                updateForegroundNotification()
            }
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

        // 운행종료 판단 로직 개선 - 기점출발예정, 차고지행 등은 운행종료가 아님
        val isOutOfService = (currentStation.contains("운행종료")) ||
                            (currentStation.contains("차고지") && remainingMinutes < 0)

        Log.d(TAG, "🔍 [updateAutoAlarmBusInfo] 운행종료 판단: remainingMinutes=$remainingMinutes, currentStation='$currentStation', isOutOfService=$isOutOfService")

        val busInfo = BusInfo(
            currentStation = currentStation,
            estimatedTime = if (isOutOfService) "운행종료" else when {
                remainingMinutes < 0 -> currentStation // 기점출발예정 등의 정보 표시
                remainingMinutes == 0 -> "곧 도착"
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

    // [추가] 다음 버스로 전환되었는지 확인하고 TTS 안내
    private fun checkNextBusAndNotify(trackingInfo: TrackingInfo, newBusInfo: BusInfo) {
        val prevBusInfo = trackingInfo.lastBusInfo ?: return
        
        // 이전 정보가 '곧 도착'이거나 3분 이내였는데, 
        // 새로운 정보가 7분 이상으로 늘어났다면 다음 버스로 간주
        val prevMinutes = prevBusInfo.getRemainingMinutes()
        val newMinutes = newBusInfo.getRemainingMinutes()
        
        // 유효한 시간 범위인지 확인
        if (prevMinutes < 0 || newMinutes < 0) return

        // 다음 버스 전환 조건:
        // 1. 이전 버스가 3분 이내 또는 '곧 도착'
        // 2. 새로운 버스가 7분 이상 남음
        // 3. 두 시간 차이가 5분 이상 (일시적인 데이터 튀는 현상 방지)
        if (prevMinutes <= 3 && newMinutes >= 7 && (newMinutes - prevMinutes) >= 5) {
            Log.i(TAG, "🚌 [다음 버스 감지] 이전: ${prevMinutes}분, 현재: ${newMinutes}분 - TTS 안내 시도")
            
            // 중복 안내 방지 (이미 안내했으면 스킵)
            if (trackingInfo.lastTtsAnnouncedMinutes == newMinutes) {
                return
            }

            if (useTextToSpeech) {
                val ttsMessage = "다음 버스, 약 ${newMinutes}분 후 도착"
                ttsController.speakTts(ttsMessage)
                Log.d(TAG, "[TTS] 다음 버스 안내: $ttsMessage")

                // 안내 상태 업데이트
                trackingInfo.lastTtsAnnouncedMinutes = newMinutes
                trackingInfo.lastTtsAnnouncedStation = newBusInfo.currentStation
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
        ttsController.setUseTts(useTextToSpeech)
    }

    fun setAudioOutputMode(mode: Int) {
        Log.d(TAG, "setAudioOutputMode called: $mode")
        if (mode in OUTPUT_MODE_HEADSET..OUTPUT_MODE_AUTO) {
            audioOutputMode = mode
            ttsController.setAudioOutputMode(audioOutputMode)
        }
    }

    fun getAudioOutputMode(): Int = audioOutputMode

    fun isHeadsetConnected(): Boolean = ttsController.isHeadsetConnected()

    fun speakTts(text: String, earphoneOnly: Boolean = false, forceSpeaker: Boolean = false) {
        ttsController.speakTts(text, earphoneOnly, forceSpeaker)
    }

    fun setTtsVolume(volume: Double) {
        serviceScope.launch {
            try {
                ttsVolume = volume.toFloat().coerceIn(0f, 1f)
                ttsController.setTtsVolume(ttsVolume)
                Log.d(TAG, "TTS Volume set to: ${ttsVolume * 100}%")
            } catch (e: Exception) {
                Log.e(TAG, "Error setting TTS volume: ${e.message}", e)
            }
        }
    }

    fun cancelOngoingTracking() {
        Log.d(TAG, "cancelOngoingTracking called (ID: $ONGOING_NOTIFICATION_ID)")
        try {
            // 1. 포그라운드 서비스 먼저 중지 (노티피케이션 제거를 위해)
            if (isInForeground) {
                Log.d(TAG, "Service is in foreground, calling stopForeground(STOP_FOREGROUND_REMOVE).")
                stopForeground(STOP_FOREGROUND_REMOVE)
                isInForeground = false
            }

            // 2. 모든 알림 직접 취소
            try {
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancelAll()
                notificationManager.cancel(ONGOING_NOTIFICATION_ID)
                notificationManager.cancel(AUTO_ALARM_NOTIFICATION_ID) // 자동알람 전용 알림 취소 추가
                Log.d(TAG, "모든 알림 직접 취소 완료 (cancelOngoingTracking)")
            } catch (e: Exception) {
                Log.e(TAG, "알림 취소 오류 (cancelOngoingTracking): ${e.message}")
            }

            // 4. 모든 추적 작업 중지
            monitoringJobs.values.forEach { it.cancel() }
            monitoringJobs.clear()
            activeTrackings.clear()
            monitoredRoutes.clear()

            // 5. Flutter 측에 알림 취소 이벤트 전송 시도
            try {
                val allCancelIntent = Intent("com.devground.daegubus.ALL_TRACKING_CANCELLED")
                sendBroadcast(allCancelIntent)
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

    

    // 알림 취소 (MainActivity 호출 호환)
    fun cancelNotification(id: Int) {
        Log.d(TAG, "알림 취소 요청: ID=$id")
        try {
            NotificationManagerCompat.from(this).cancel(id)
            if (id == ONGOING_NOTIFICATION_ID && activeTrackings.isEmpty()) {
                if (isInForeground) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    isInForeground = false
                }
                checkAndStopServiceIfNeeded()
            }
            Log.d(TAG, "✅ 알림 취소 완료: ID=$id")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 알림 취소 오류: ID=$id, ${e.message}")
        }
    }

    // 모든 알림 취소
    fun cancelAllNotifications() {
        Log.i(TAG, "모든 알림 취소 요청")
        try {
            // 모든 알림 취소 및 추적 중지 로직을 stopAllBusTracking()으로 위임
            stopAllBusTracking()
            Log.d(TAG, "✅ 모든 알림 취소 및 추적 중지 완료 (cancelAllNotifications)")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 모든 알림 취소 오류 (cancelAllNotifications): ${e.message}")
        }
    }

    private fun stopTrackingIfIdle() {
        serviceScope.launch {
            checkAndStopServiceIfNeeded()
        }
    }

    // 중복 이벤트 방지를 위한 캐시
    private val sentCancellationEvents = mutableSetOf<String>()
    private val eventTimeouts = mutableMapOf<String, Long>()
    
    private fun sendCancellationBroadcast(busNo: String, routeId: String, stationName: String) {
        try {
            // 중복 이벤트 방지 키 생성
            val eventKey = "${busNo}_${routeId}_${stationName}_cancellation"
            val currentTime = System.currentTimeMillis()
            
            // 5초 이내 중복 이벤트 체크
            val lastEventTime = eventTimeouts[eventKey] ?: 0
            if (currentTime - lastEventTime < 5000) {
                Log.d(TAG, "⚠️ 중복 취소 이벤트 방지: $eventKey (${currentTime - lastEventTime}ms 전에 전송됨)")
                return
            }
            
            // 이벤트 시간 기록
            eventTimeouts[eventKey] = currentTime
            sentCancellationEvents.add(eventKey)
            
            // 오래된 이벤트 정리 (30초 이전)
            val expiredKeys = eventTimeouts.filter { currentTime - it.value > 30000 }.keys
            for (key in expiredKeys) {
                eventTimeouts.remove(key)
                sentCancellationEvents.remove(key)
            }

            val cancellationIntent = Intent("com.devground.daegubus.NOTIFICATION_CANCELLED").apply {
                putExtra("busNo", busNo)
                putExtra("routeId", routeId)
                putExtra("stationName", stationName)
                putExtra("source", "native_service")
                putExtra("timestamp", currentTime) // 이벤트 시간 추가
                flags = Intent.FLAG_INCLUDE_STOPPED_PACKAGES
            }
            sendBroadcast(cancellationIntent)
            Log.d(TAG, "✅ 알림 취소 이벤트 브로드캐스트 전송: $busNo, $routeId, $stationName")

            // Flutter 메서드 채널을 통해 직접 이벤트 전송 시도 (개선된 방법)
            try {
                MainActivity.sendFlutterEvent("onAlarmCanceledFromNotification", mapOf(
                    "busNo" to busNo,
                    "routeId" to routeId,
                    "stationName" to stationName,
                    "timestamp" to currentTime
                ))
                Log.d(TAG, "✅ Flutter 메서드 채널로 알람 취소 이벤트 전송 완료")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Flutter 메서드 채널 전송 오류: ${e.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ 알림 취소 이벤트 전송 오류: ${e.message}")
        }
    }

    private fun sendAllCancellationBroadcast() {
        try {
            val allCancelBroadcast = Intent("com.devground.daegubus.ALL_TRACKING_CANCELLED").apply {
                flags = Intent.FLAG_INCLUDE_STOPPED_PACKAGES
            }
            sendBroadcast(allCancelBroadcast)
            Log.d(TAG, "모든 추적 취소 이벤트 브로드캐스트 전송")

            // Flutter 메서드 채널을 통해 직접 이벤트 전송 시도
            try {
                if (applicationContext is MainActivity) {
                    (applicationContext as MainActivity)._methodChannel?.invokeMethod("onAllAlarmsCanceled", null)
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

        val isWithinThreshold = when {
            !trackingInfo.isAutoAlarm ->
                remainingMinutes >= 0 && remainingMinutes <= ARRIVAL_THRESHOLD_MINUTES
            alertOnArrivalOnly -> {
                val stops = busInfo.remainingStops.toIntOrNull() ?: 99
                remainingMinutes >= 0 && (stops < 3 || remainingMinutes <= 3)
            }
            else ->
                // 토글 OFF: 설정된 알람 시각 이후부터 버스 정보가 있으면 발화 (TrackingInfo별 독립 시각)
                remainingMinutes >= 0 && System.currentTimeMillis() >= trackingInfo.exactAlarmTriggerTime
        }

        if (isWithinThreshold) {
            // 시간 변경 또는 버스 위치(정류장) 변경 시 TTS 발화
            val minutesChanged = trackingInfo.lastNotifiedMinutes != remainingMinutes
            val stationChanged = busInfo.currentStation.isNotBlank() &&
                trackingInfo.lastTtsAnnouncedStation != busInfo.currentStation
            val shouldNotifyTts = minutesChanged || stationChanged
            if (shouldNotifyTts) {
                val forceSpeaker = trackingInfo.isCommuteAlarm
                
                // 퇴근 알람 (이어폰 시 TTS, 미연결 시 진동) 처리를 위한 로직 추가
                val isReturnAlarm = trackingInfo.isAutoAlarm && !trackingInfo.isCommuteAlarm
                
                if (isReturnAlarm && !ttsController.isHeadsetConnected()) {
                    Log.d(TAG, "📳 퇴근 알람: 이어폰 미연결 상태이므로 TTS 건너뛰고 진동 발생")
                    try {
                        val vibrator = getSystemService(Context.VIBRATOR_SERVICE) as android.os.Vibrator
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            vibrator.vibrate(android.os.VibrationEffect.createOneShot(500, android.os.VibrationEffect.DEFAULT_AMPLITUDE))
                        } else {
                            @Suppress("DEPRECATION")
                            vibrator.vibrate(500)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "진동 발생 오류: ${e.message}")
                    }
                    
                    trackingInfo.lastNotifiedMinutes = remainingMinutes
                    trackingInfo.lastTtsAnnouncedStation = busInfo.currentStation
                } else {
                    try {
                        // 자동알람은 이어폰 체크 우회 (단, 퇴근알람이면서 이어폰 연결 유무에 따른 분기는 위에서 처리됨)
                        ttsController.startTtsServiceSpeak(
                            busNo = trackingInfo.busNo,
                            stationName = trackingInfo.stationName,
                            routeId = trackingInfo.routeId,
                            stationId = trackingInfo.stationId,
                            remainingMinutes = remainingMinutes,
                            forceSpeaker = forceSpeaker,
                            currentStation = busInfo.currentStation,
                            isAutoAlarm = trackingInfo.isAutoAlarm
                        )

                        trackingInfo.lastNotifiedMinutes = remainingMinutes
                        trackingInfo.lastTtsAnnouncedStation = busInfo.currentStation

                        Log.d(
                            TAG,
                            "📢 TTS 발화: ${trackingInfo.busNo}번 버스, ${remainingMinutes}분 후 도착, 현재 위치: ${busInfo.currentStation} (시간변경=$minutesChanged, 위치변경=$stationChanged, forceSpeaker=$forceSpeaker)"
                        )
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ TTS 발화 오류: ${e.message}", e)

                        val message =
                            "${trackingInfo.busNo}번 버스가 ${trackingInfo.stationName} 정류장에 곧 도착합니다."
                        ttsController.speakTts(message, forceSpeaker = forceSpeaker)

                        trackingInfo.lastNotifiedMinutes = remainingMinutes
                        trackingInfo.lastTtsAnnouncedStation = busInfo.currentStation
                    }
                }
            }

            // 자동알람인 경우 항상 도착 알림 (다음 버스 추적을 위해)
            val shouldNotifyArrival = if (trackingInfo.isAutoAlarm) {
                // 자동알람: 이전 알림 시간과 다르면 항상 알림
                trackingInfo.lastNotifiedMinutes != remainingMinutes
            } else {
                // 일반 알람: 한 번만 알림
                !hasNotifiedArrival.contains(trackingInfo.routeId)
            }

            if (shouldNotifyArrival) {
                // [수정] 중복 노티피케이션 제거 요청으로 인해 sendAlertNotification 호출 제거
                // notificationHandler.sendAlertNotification(...)

                // 자동알람이 아닌 경우에만 hasNotifiedArrival에 추가 (중복 방지)
                if (!trackingInfo.isAutoAlarm) {
                    hasNotifiedArrival.add(trackingInfo.routeId)
                }

                Log.d(TAG, "📳 도착 임박 상태 감지: ${trackingInfo.busNo}번, ${trackingInfo.stationName} (자동알람: ${trackingInfo.isAutoAlarm}) - 별도 알림은 생성하지 않음")
            }
        } else if (trackingInfo.isAutoAlarm) {
            // 자동알람인 경우 버스가 임계값 밖이면 알림 상태 초기화 (다음 버스를 위해)
            trackingInfo.lastNotifiedMinutes = Int.MAX_VALUE
            Log.d(TAG, "🔄 자동알람 상태 초기화: ${trackingInfo.busNo}번 버스가 임계값 밖 (${remainingMinutes}분)")
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
            // 🛑 사용자 수동 중지 플래그 확인 (재시작 방지)
            if (isManuallyStoppedByUser) {
                val timeSinceStop = System.currentTimeMillis() - lastManualStopTime
                if (timeSinceStop < RESTART_PREVENTION_DURATION) {
                    Log.w(TAG, "🛑 User manually stopped ${timeSinceStop / 1000}sec ago - rejecting updateTrackingInfoFromFlutter: $busNo")
                    return
                } else {
                    // 30초가 지났으면 플래그 해제
                    isManuallyStoppedByUser = false
                    lastManualStopTime = 0L
                    Log.i(TAG, "✅ Native restart prevention period expired - allowing updateTrackingInfoFromFlutter: $busNo")
                }
            }

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

            // 경량화: 불필요한 중복 업데이트 제거
            // 백업 타이머가 주기적으로 업데이트하므로 즉시 업데이트는 최소화

            Log.d(TAG, "✅ 버스 추적 알림 업데이트 완료: $busNo, ${remainingMinutes}분, 현재 위치: $currentStation")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 버스 추적 알림 업데이트 오류: ${e.message}", e)
            // 오류 발생 시에도 알림 업데이트 시도
            updateForegroundNotification()
        }
    }

// 모든 추적 중지
    private fun stopAllTracking() {
        Log.i(TAG, "📱 --- stopAllTracking 시작 ---")

        try {
            // 🛑 서비스 활성화 플래그를 가장 먼저 비활성화 (새로운 요청 차단)
            isServiceActive = false
            Log.d(TAG, "✅ 서비스 비활성화 플래그 설정")

            // 🛑 사용자 수동 중지 플래그 강화 (이미 설정되어 있지만 재확인)
            if (!isManuallyStoppedByUser) {
                isManuallyStoppedByUser = true
                lastManualStopTime = System.currentTimeMillis()
            }
            Log.w(TAG, "🛑 사용자 수동 중지 플래그 재확인: $isManuallyStoppedByUser")

            // 1. 코루틴 스코프 취소로 모든 비동기 작업 강제 중지
            try {
                serviceScope.cancel()
                Log.d(TAG, "✅ 서비스 코루틴 스코프 취소")
            } catch (e: Exception) {
                Log.e(TAG, "❌ 서비스 코루틴 스코프 취소 오류: ${e.message}")
            }

            // 2. 모니터링 타이머 중지
            stopMonitoringTimer()
            Log.d(TAG, "✅ 모니터링 타이머 중지")

            // 3. TTS 추적 완전 중지
            stopTtsTracking(forceStop = true)
            Log.d(TAG, "✅ TTS 추적 중지")

            // 4. 자동 알람 WorkManager 작업 강력 취소
            try {
                val workManager = androidx.work.WorkManager.getInstance(this)
                
                // 모든 대기 중인 작업 취소 (가장 강력한 방법)
                workManager.cancelAllWork()
                
                // 특정 태그별 취소
                workManager.cancelAllWorkByTag("autoAlarmTask")
                workManager.cancelAllWorkByTag("nextAutoAlarm")
                
                // 개별 버스별 자동알람 작업 취소
                activeTrackings.values.forEach { tracking ->
                    if (tracking.isAutoAlarm) {
                        workManager.cancelAllWorkByTag("autoAlarm_${tracking.busNo}")
                        workManager.cancelAllWorkByTag("autoAlarm_${tracking.routeId}")
                        workManager.cancelAllWorkByTag("nextAutoAlarm_${tracking.routeId}")
                    }
                }
                
                // 자동알람 모드 완전 비활성화
                isAutoAlarmMode = false
                autoAlarmStartTime = 0L
                
                Log.d(TAG, "✅ WorkManager 작업 강력 취소 완료")
            } catch (e: Exception) {
                Log.e(TAG, "❌ WorkManager 작업 취소 오류: ${e.message}")
            }

            // 5. 개별 취소 이벤트 전송
            Log.d(TAG, "📨 개별 취소 이벤트 전송 시작")
            val routesToCancel = monitoredRoutes.toMap()
            routesToCancel.forEach { (routeId, route) ->
                try {
                    val stationName = route.second
                    val busNoFromTracking = activeTrackings[routeId]?.busNo ?: "unknown"
                    sendCancellationBroadcast(busNoFromTracking, routeId, stationName)
                    Log.d(TAG, "✅ 개별 취소 이벤트 전송: $routeId")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 개별 취소 이벤트 전송 오류: $routeId, ${e.message}")
                }
            }

            // 6. 모든 취소 이벤트 전송
            sendAllCancellationBroadcast()
            Log.d(TAG, "✅ 모든 취소 이벤트 전송")

            // 7. 데이터 강력 정리
            Log.d(TAG, "🧭 데이터 강력 정리 시작")
            monitoringJobs.values.forEach { 
                try {
                    it.cancel()
                } catch (e: Exception) {
                    Log.w(TAG, "모니터링 작업 취소 오류: ${e.message}")
                }
            }
            monitoringJobs.clear()
            activeTrackings.clear()
            monitoredRoutes.clear()
            cachedBusInfo.clear()
            arrivingSoonNotified.clear()
            try {
                hasNotifiedTts.clear()
                hasNotifiedArrival.clear()
            } catch (e: Exception) {
                Log.w(TAG, "TTS/Arrival 캐시 정리 오류: ${e.message}")
            }
            Log.d(TAG, "✅ 모든 데이터 정리 완료")

            // 8. 포그라운드 서비스 강제 중지
            Log.d(TAG, "🚀 포그라운드 서비스 강제 중지 시작")
            try {
                if (isInForeground) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    isInForeground = false
                    Log.d(TAG, "✅ 포그라운드 서비스 중지 완료")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ 포그라운드 서비스 중지 오류: ${e.message}")
            }

            // 9. 모든 알림 강력 취소 (다단계 시도)
            Log.d(TAG, "🔔 알림 강력 취소 시작")
            try {
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                
                // 9.1. 즉시 취소
                notificationManager.cancelAll()
                notificationManager.cancel(ONGOING_NOTIFICATION_ID)
                notificationManager.cancel(AUTO_ALARM_NOTIFICATION_ID)
                
                // 9.2. NotificationManagerCompat으로도 취소
                val notificationManagerCompat = NotificationManagerCompat.from(this)
                notificationManagerCompat.cancelAll()
                notificationManagerCompat.cancel(ONGOING_NOTIFICATION_ID)
                notificationManagerCompat.cancel(AUTO_ALARM_NOTIFICATION_ID)
                
                Log.d(TAG, "✅ 즉시 알림 취소 완료")

                // 9.3. 지연된 추가 취소 (3회 시도)
                val handler = Handler(Looper.getMainLooper())
                for (i in 1..3) {
                    handler.postDelayed({
                        try {
                            notificationManager.cancelAll()
                            notificationManager.cancel(ONGOING_NOTIFICATION_ID)
                            notificationManager.cancel(AUTO_ALARM_NOTIFICATION_ID)
                            Log.d(TAG, "✅ 지연된 알림 취소 완료 ($i/3)")
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ 지연된 알림 취소 오류 ($i/3): ${e.message}")
                        }
                    }, (i * 500).toLong())
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ 알림 취소 오류: ${e.message}")
            }

            // 10. 인스턴스 및 서비스 완전 정리
            try {
                instance = null
                stopSelf()
                Log.d(TAG, "✅ 서비스 인스턴스 정리 및 중지 요청 완료")
            } catch (e: Exception) {
                Log.e(TAG, "❌ 서비스 중지 오류: ${e.message}")
            }

            Log.i(TAG, "✅✅✅ stopAllTracking 완료 - 강력한 정리 작업 완료! ✅✅✅")
            Log.i(TAG, "✅ 사용자 수동 중지 상태: $isManuallyStoppedByUser")
            Log.i(TAG, "✅ 서비스 활성 상태: $isServiceActive")
            Log.i(TAG, "✅ 남은 추적: ${activeTrackings.size}개, 모니터링 작업: ${monitoringJobs.size}개")

        } catch (e: Exception) {
            Log.e(TAG, "❌ stopAllTracking 중 오류 발생: ${e.message}", e)
            try {
                Log.w(TAG, "⚠️ 긴급 복구 시작: 최소한의 정리 작업 수행")
                
                // 긴급 정리
                isServiceActive = false
                isManuallyStoppedByUser = true
                lastManualStopTime = System.currentTimeMillis()
                
                monitoringJobs.clear()
                activeTrackings.clear()
                monitoredRoutes.clear()
                
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancelAll()
                
                if (isInForeground) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    isInForeground = false
                }
                
                instance = null
                stopSelf()
                
                Log.w(TAG, "⚠️ 긴급 복구 완료")
            } catch (cleanupError: Exception) {
                Log.e(TAG, "❌ 긴급 복구 실패: ${cleanupError.message}")
            }
        }
    }

    // [ADD] Stop tracking for a specific route (optionally cancel notification)
    fun stopTrackingForRoute(routeId: String, stationId: String? = null, busNo: String? = null, cancelNotification: Boolean = false, notificationId: Int? = null) {
        serviceScope.launch {
            Log.i(TAG, "--- stopTrackingForRoute called: routeId=$routeId, stationId=$stationId, busNo=$busNo, cancelNotification=$cancelNotification, notificationId=$notificationId ---")
            try {
                // 1. 추적 작업 취소 및 데이터 정리
                monitoringJobs[routeId]?.cancel()
                monitoringJobs.remove(routeId)
                activeTrackings.remove(routeId)
                monitoredRoutes.remove(routeId)
                arrivingSoonNotified.remove(routeId)
                hasNotifiedTts.remove(routeId)
                hasNotifiedArrival.remove(routeId)

                Log.d(TAG, "✅ 추적 데이터 정리 완료: $routeId, 남은 추적: ${activeTrackings.size}개")

                // 2. 알림 취소 처리
                if (cancelNotification) {
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                    // 개별 알림 ID 계산 및 취소
                    val specificNotificationId = notificationId ?: generateNotificationId(routeId)
                    try {
                        notificationManager.cancel(specificNotificationId)
                        Log.d(TAG, "✅ 개별 알림 취소: routeId=$routeId, notificationId=$specificNotificationId")
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ 개별 알림 취소 실패: ${e.message}")
                    }
                }

                // 3. 포그라운드 알림 업데이트 또는 서비스 종료
                if (activeTrackings.isEmpty()) {
                    // 모든 추적이 끝났을 때만 포그라운드 서비스 종료
                    try {
                        stopForeground(STOP_FOREGROUND_REMOVE)
                        isInForeground = false
                        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        notificationManager.cancel(ONGOING_NOTIFICATION_ID)
                        Log.d(TAG, "✅ 모든 추적 종료 - 포그라운드 서비스 중지")
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ 포그라운드 서비스 중지 오류: ${e.message}", e)
                    }
                    stopSelf()
                } else {
                    // 다른 추적이 남아있으면 포그라운드 알림만 업데이트
                    Log.d(TAG, "🔄 다른 추적 존재 (${activeTrackings.size}개), 포그라운드 알림 업데이트")
                    updateForegroundNotification()
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ stopTrackingForRoute 오류: ${e.message}", e)
            }
        }
    }

    // 포그라운드 알림 갱신
    private fun updateForegroundNotification() {
        try {
            if (activeTrackings.isEmpty()) {
                Log.d(TAG, "활성 추적 없음, 포그라운드 알림 취소")
                NotificationManagerCompat.from(this).cancel(ONGOING_NOTIFICATION_ID)
                if (isInForeground) {
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    isInForeground = false
                }
                checkAndStopServiceIfNeeded()
                return
            }

            notificationUpdater.updateOngoing(
                ONGOING_NOTIFICATION_ID,
                activeTrackings,
                isInForeground
            ) { newValue ->
                isInForeground = newValue
            }

            Log.d(TAG, "✅ 포그라운드 알림 갱신 완료")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 포그라운드 알림 갱신 오류: ${e.message}", e)
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
            val builder = NotificationCompat.Builder(this, CHANNEL_ID_ALERT)
                .setSmallIcon(R.drawable.ic_bus_notification)
                .setContentTitle("$busNo 버스 곧 도착")
                .setContentText("$busNo bus is arriving at $stationName.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
            
            if (currentStation != null) {
                builder.setStyle(NotificationCompat.BigTextStyle().bigText("Current location: $currentStation"))
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(9998, builder.build())
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
        currentStation: String?,
        routeId: String? = null
    ) {
        // 이제 이 메서드는 showOngoingBusTracking을 호출하여 개별 알림을 표시합니다.
        showOngoingBusTracking(
            busNo = busNo,
            stationName = stationName,
            remainingMinutes = remainingMinutes,
            currentStation = currentStation,
            isUpdate = false, // 새 알림이므로 isUpdate는 false
            notificationId = id, // 전달받은 id 사용
            allBusesSummary = null, // 개별 알람에는 전체 요약 불필요
            routeId = routeId,
            isIndividualAlarm = true // 이 알림이 개별 알람임을 명시
        )
    }

    // 현재 실행 중인 자동 알람 정보
    private var currentAutoAlarmBusNo: String = ""
    private var currentAutoAlarmStationName: String = ""
    private var currentAutoAlarmRouteId: String = ""

    /**
     * 배터리 절약을 위한 자동알람 경량화 모드
     * - Foreground Service 사용 안함 (하지만 추적을 위해 필요하다면 사용)
     * - 간단한 알림만 표시
     * - 5분 후 자동 종료
     */
    private fun handleAutoAlarmLightweight(busNo: String, stationName: String, remainingMinutes: Int, currentStation: String, routeId: String, stationId: String, useTTS: Boolean = true, isCommuteAlarm: Boolean = false, alarmHour: Int = -1, alarmMinute: Int = -1) {
        try {
            Log.d(TAG, "🔔 자동알람 경량화 모드 처리: $busNo 번, $stationName, routeId=$routeId, stationId=$stationId, TTS=$useTTS")

            // 자동알람 모드 활성화
            isAutoAlarmMode = true
            autoAlarmStartTime = System.currentTimeMillis()

            // 정확한 알람 발화 시각 계산 (toggle OFF 모드용) - TrackingInfo에 저장 (다중 알람 독립 관리)
            val computedTriggerTime = if (alarmHour >= 0 && alarmMinute >= 0) {
                val cal = java.util.Calendar.getInstance().apply {
                    set(java.util.Calendar.HOUR_OF_DAY, alarmHour)
                    set(java.util.Calendar.MINUTE, alarmMinute)
                    set(java.util.Calendar.SECOND, 0)
                    set(java.util.Calendar.MILLISECOND, 0)
                }
                // 이미 지났으면 현재 시각 사용
                if (cal.timeInMillis < autoAlarmStartTime) autoAlarmStartTime else cal.timeInMillis
            } else {
                autoAlarmStartTime // Flutter 트리거: 즉시 발화
            }
            Log.d(TAG, "⏰ 알람 발화 시각: ${java.util.Date(computedTriggerTime)}, alarmHour=$alarmHour, alarmMinute=$alarmMinute")

            // 정보 저장
            currentAutoAlarmBusNo = busNo
            currentAutoAlarmStationName = stationName
            currentAutoAlarmRouteId = routeId

            // 칩 cycling 상태 초기화
            autoAlarmNotifier.resetChipState()

            // 경량화된 알림 표시
            autoAlarmNotifier.showInitialNotification(busNo, stationName, remainingMinutes, currentStation)

            // 🔊 TTS 미사용 시 알람 사운드만 재생 (TTS는 실제 데이터 도착 후 발화)
            if (!useTTS) {
                alarmSoundPlayer.play()
            }

            // 📌 핵심: 실시간 추적 시작 → 첫 API 응답 시 실제 도착 정보로 TTS 발화
            // (기존: 의미 없는 "알람이 시작되었습니다" 멘트 제거 → 실제 "N분 후 도착" 발화)
            if (routeId.isNotBlank() && stationId.isNotBlank()) {
                Log.d(TAG, "🔔 자동알람: 실시간 추적 시작 ($routeId, $stationId)")
                addMonitoredRoute(routeId, stationId, stationName)
                startTracking(routeId, stationId, stationName, busNo, isAutoAlarm = true, isCommuteAlarm = isCommuteAlarm)
                // TrackingInfo에 발화 시각 저장 (다중 알람 독립 관리)
                activeTrackings[routeId]?.exactAlarmTriggerTime = computedTriggerTime
            } else {
                Log.e(TAG, "❌ 자동알람: routeId 또는 stationId 누락으로 추적 불가")
            }

            // Flutter에 시작 알림 전송 (중복 실행 방지용)
            MainActivity.sendFlutterEvent("onAutoAlarmStarted", mapOf(
                "busNo" to busNo,
                "stationName" to stationName,
                "routeId" to routeId,
                "timestamp" to System.currentTimeMillis()
            ))

            // 설정 기반 자동 종료 스케줄링
            Handler(Looper.getMainLooper()).postDelayed({
                if (isAutoAlarmMode && (System.currentTimeMillis() - autoAlarmStartTime) >= autoAlarmTimeoutMs) {
                    Log.d(TAG, "🔔 자동알람 경량화 모드 타임아웃으로 종료")
                    stopAutoAlarmLightweight()
                }
            }, autoAlarmTimeoutMs)

            Log.d(TAG, "✅ 자동알람 경량화 모드 시작 완료")

        } catch (e: Exception) {
            Log.e(TAG, "❌ 자동알람 경량화 모드 처리 오류: ${e.message}", e)
        }
    }

    /**
     * 자동알람 경량화 모드 종료
     */
    private fun stopAutoAlarmLightweight() {
        try {
            Log.d("BusAlertService", "🔔 자동알람 경량화 모드 종료")

            // 🔇 알람 사운드 정지
            alarmSoundPlayer.stop()

            // TTS 추적 중지
            try {
                ttsController.stopTtsServiceTracking()
                Log.d("BusAlertService", "✅ TTS 추적 중지 완료")
            } catch (e: Exception) {
                Log.w("BusAlertService", "⚠️ TTS 추적 중지 오류 (무시): ${e.message}")
            }

            // 자동알람 추적에 해당하는 모니터링 작업 취소
            val autoAlarmRouteId = currentAutoAlarmRouteId
            if (autoAlarmRouteId.isNotBlank()) {
                try {
                    monitoringJobs[autoAlarmRouteId]?.cancel()
                    monitoringJobs.remove(autoAlarmRouteId)
                    activeTrackings.remove(autoAlarmRouteId)
                    monitoredRoutes.remove(autoAlarmRouteId)
                    cachedBusInfo.remove(autoAlarmRouteId)
                    Log.d("BusAlertService", "✅ 자동알람 모니터링 작업 취소 완료: $autoAlarmRouteId")
                } catch (e: Exception) {
                    Log.w("BusAlertService", "⚠️ 자동알람 모니터링 취소 오류 (무시): ${e.message}")
                }
            }

            isAutoAlarmMode = false
            autoAlarmStartTime = 0L

            // 자동알람 알림 제거
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(9999)
            notificationManager.cancel(AUTO_ALARM_NOTIFICATION_ID)

            // Flutter에 종료 알림 전송 (재실행 방지용)
            MainActivity.sendFlutterEvent("onAutoAlarmStopped", mapOf(
                "timestamp" to System.currentTimeMillis(),
                "busNo" to currentAutoAlarmBusNo,
                "stationName" to currentAutoAlarmStationName,
                "routeId" to currentAutoAlarmRouteId
            ))

            Log.d("BusAlertService", "✅ 자동알람 경량화 모드 종료 완료")

        } catch (e: Exception) {
            Log.e("BusAlertService", "❌ 자동알람 경량화 모드 종료 오류: ${e.message}", e)
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

internal fun isSamsungOneUi(): Boolean {
    return Build.MANUFACTURER.equals("samsung", ignoreCase = true)
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
