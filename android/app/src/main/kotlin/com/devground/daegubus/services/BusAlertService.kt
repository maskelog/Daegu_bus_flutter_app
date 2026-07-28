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
import com.devground.daegubus.BusActions
import com.devground.daegubus.BusDisplayMode
import com.devground.daegubus.BusNotificationIds
import com.devground.daegubus.BusOutputMode
import com.devground.daegubus.models.BusInfo
import com.devground.daegubus.utils.NotificationHandler
import com.devground.daegubus.MainActivity
import com.devground.daegubus.services.BusAlertTtsController
import com.devground.daegubus.services.BusAlertNotificationUpdater
import com.devground.daegubus.services.BusAlertTrackingManager

class BusAlertService : Service() {
    companion object {
        private const val TAG = "BusAlertService"

        // --- 알림 채널 (서비스 구현 세부사항) ---
        private const val CHANNEL_ID_ONGOING = "bus_tracking_ongoing"
        private const val CHANNEL_NAME_ONGOING = "실시간 버스 추적"
        internal const val CHANNEL_ID_ALERT = "bus_tracking_alert"
        private const val CHANNEL_NAME_ALERT = "버스 도착 임박 알림"
        private const val CHANNEL_ID_ERROR = "bus_tracking_error"
        private const val CHANNEL_NAME_ERROR = "추적 오류 알림"
        private const val CHANNEL_BUS_ALERTS = "bus_alerts"
        internal const val CHANNEL_ID_AUTO_ALARM_LEGACY = "auto_alarm_silent_v1"
        internal const val CHANNEL_ID_AUTO_ALARM_LEGACY_OLD = "auto_alarm_lightweight"
        internal const val CHANNEL_ID_AUTO_ALARM_LIVE_UPDATE = "auto_alarm_live_update_v3"
        internal const val CHANNEL_NAME_AUTO_ALARM = "자동 알람 (경량)"

        // --- 서비스 상태 ---
        private var instance: BusAlertService? = null
        fun getInstance(): BusAlertService? = instance
        private var isServiceActive = false
        fun isActive(): Boolean = isServiceActive

        internal fun getAutoAlarmChannelId(): String =
            if (Build.VERSION.SDK_INT >= 36) CHANNEL_ID_AUTO_ALARM_LIVE_UPDATE
            else CHANNEL_ID_AUTO_ALARM_LEGACY

        // --- 하위 호환 aliases (신규 코드는 BusActions / BusNotificationIds / BusOutputMode 사용) ---
        const val ONGOING_NOTIFICATION_ID = BusNotificationIds.ONGOING
        const val AUTO_ALARM_NOTIFICATION_ID = BusNotificationIds.AUTO_ALARM

        const val ACTION_START_TRACKING = BusActions.ACTION_START_TRACKING
        const val ACTION_STOP_TRACKING = BusActions.ACTION_STOP_TRACKING
        const val ACTION_STOP_SPECIFIC_ROUTE_TRACKING = BusActions.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
        const val ACTION_CANCEL_NOTIFICATION = BusActions.ACTION_CANCEL_NOTIFICATION
        const val ACTION_START_TTS_TRACKING = BusActions.ACTION_START_TTS_TRACKING
        const val ACTION_STOP_TTS_TRACKING = BusActions.ACTION_STOP_TTS_TRACKING
        const val ACTION_START_TRACKING_FOREGROUND = BusActions.ACTION_START_TRACKING_FOREGROUND
        const val ACTION_UPDATE_TRACKING = BusActions.ACTION_UPDATE_TRACKING
        const val ACTION_STOP_BUS_ALERT_TRACKING = BusActions.ACTION_STOP_BUS_ALERT_TRACKING
        const val ACTION_START_AUTO_ALARM_LIGHTWEIGHT = BusActions.ACTION_START_AUTO_ALARM_LIGHTWEIGHT
        const val ACTION_STOP_AUTO_ALARM = BusActions.ACTION_STOP_AUTO_ALARM
        const val ACTION_SET_ALARM_SOUND = BusActions.ACTION_SET_ALARM_SOUND
        const val ACTION_SHOW_NOTIFICATION = BusActions.ACTION_SHOW_NOTIFICATION

        const val OUTPUT_MODE_HEADSET = BusOutputMode.HEADSET
        const val OUTPUT_MODE_SPEAKER = BusOutputMode.SPEAKER
        const val OUTPUT_MODE_AUTO = BusOutputMode.AUTO
        const val DISPLAY_MODE_ALARMED_ONLY = BusDisplayMode.ALARMED_ONLY

        // --- 서비스 내부 상수 ---
        const val DEFAULT_ALARM_SOUND = ""
        // MAX_CONSECUTIVE_ERRORS는 BusAlertTrackingManager.updateBusInfo로 이관
        // (2026-07-28, 1b-3) — 그 함수가 유일한 사용처였다.
        private const val ARRIVAL_THRESHOLD_MINUTES = 60
    }

    private val binder = LocalBinder()
    private val exceptionHandler = CoroutineExceptionHandler { _, e ->
        Log.e(TAG, "Unhandled coroutine exception", e)
    }
    internal val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob() + exceptionHandler)
    internal val mainHandler = Handler(Looper.getMainLooper())
    private lateinit var busApiService: BusApiService
    internal lateinit var notificationHandler: NotificationHandler
    private lateinit var notificationUpdater: BusAlertNotificationUpdater
    private lateinit var trackingManager: BusAlertTrackingManager
    internal lateinit var ttsController: BusAlertTtsController
    private var useTextToSpeech: Boolean = true
    private var useVibration: Boolean = true
    private var audioOutputMode: Int = OUTPUT_MODE_AUTO
    private var ttsVolume: Float = 1.0f
    internal var isInForeground: Boolean = false

    // Tracking State
    internal val monitoringJobs = HashMap<String, Job>()
    internal val activeTrackings = HashMap<String, TrackingInfo>()
    internal val pendingAutoAlarms = HashSet<String>() // 동기 중복 방지용 (coroutine 진입 전)
    internal val monitoredRoutes = HashMap<String, Triple<String, String, Job?>>()
    internal val cachedBusInfo = HashMap<String, BusInfo>()
    private val arrivingSoonNotified = HashSet<String>()
    private var isTtsTrackingActive = false

    // TTS/Audio variables
    private val ttsInitializationLock = Object()
    private var currentAlarmSound: String = DEFAULT_ALARM_SOUND
    private var notificationDisplayMode: Int = DISPLAY_MODE_ALARMED_ONLY
    private var backupUpdateJob: Job? = null
    internal var autoAlarmTimeoutRunnable: Runnable? = null

    // 배터리 최적화를 위한 자동알람 모드
    internal var isAutoAlarmMode = false
    internal var autoAlarmStartTime = 0L
    internal var autoAlarmTimeoutMs = 1800000L // 기본 30분, 설정으로 변경 가능
    private var alertOnArrivalOnly = false // 도착 임박 시에만 알림 (3정거장/3분)

    internal val alarmSoundPlayer = BusAlertAlarmSoundPlayer(this)
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
            { b, s, r, c, routeId, summary ->
                notificationUpdater.showOngoingBusTracking(
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
            ttsController,
            { useTextToSpeech },
            ARRIVAL_THRESHOLD_MINUTES,
            this,
            monitoredRoutes,
            arrivingSoonNotified,
            hasNotifiedTts,
            hasNotifiedArrival,
            ::generateNotificationId,
            { isInForeground = it },
            ONGOING_NOTIFICATION_ID,
            cachedBusInfo,
            { isServiceActive },
            { isServiceActive = it },
            { isManuallyStoppedByUser },
            { isManuallyStoppedByUser = it },
            { lastManualStopTime = it },
            { lastManualStopTime },
            { isAutoAlarmMode = it },
            { autoAlarmStartTime = it },
            { instance = null },
            { isInForeground },
            ::stopMonitoringTimer,
            ::stopTtsTracking,
            ::checkAndStopServiceIfNeeded,
            AUTO_ALARM_NOTIFICATION_ID,
            notificationHandler,
            RESTART_PREVENTION_DURATION,
            { alertOnArrivalOnly },
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
            useVibration = flutterPrefs.getBoolean("flutter.vibrate", true)

            audioOutputMode = getFlutterLongPref(flutterPrefs, "speaker_mode", OUTPUT_MODE_HEADSET.toLong()).toInt()
            ttsController.setAudioOutputMode(audioOutputMode)
            applicationContext.getSharedPreferences("AppSettings", Context.MODE_PRIVATE)
                .edit().putInt("speaker_mode", audioOutputMode).apply()

            notificationDisplayMode = getFlutterLongPref(flutterPrefs, "notificationDisplayMode", DISPLAY_MODE_ALARMED_ONLY.toLong()).toInt()
            ttsVolume = 1.0f
            ttsController.setTtsVolume(ttsVolume)
            autoAlarmTimeoutMs = getFlutterLongPref(flutterPrefs, "auto_alarm_timeout_ms", 1800000L).coerceIn(300000L, 7200000L)
            // alertOnArrivalOnly는 intent extras로 전달됨 (setAlertOnArrivalOnly()로도 실시간 변경 가능)
            Log.d(TAG, "⚙️ Settings loaded - TTS: $useTextToSpeech, Sound: $currentAlarmSound, NotifMode: $notificationDisplayMode, Output: $audioOutputMode, Volume: ${ttsVolume * 100}%, FlutterUseTts: $flutterUseTts, FlutterAlarmSound: $flutterAlarmSound")
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

override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    Log.i(TAG, "onStartCommand Received: Action = ${intent?.action}, StartId=$startId")

    val command = parseCommand(intent)
    if (!isServiceActive && (command is ServiceCommand.StartAutoAlarmLightweight || command is ServiceCommand.StartForegroundTracking)) {
        // Zombie state: service is alive but marked inactive. Re-activate for alarm/tracking start.
        // Returning without startForeground() here causes ForegroundServiceDidNotStartInTimeException.
        Log.i(TAG, "♻️ Zombie state — re-activating for ${command::class.simpleName}")
        isServiceActive = true
    }
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
    val targetAlarmTime = intent?.getLongExtra("targetAlarmTime", 0L) ?: 0L
    val intentAlertOnArrivalOnly = intent?.getBooleanExtra("alertOnArrivalOnly", alertOnArrivalOnly) ?: alertOnArrivalOnly

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
                
                notificationManager.cancel(ONGOING_NOTIFICATION_ID)
                notificationManager.cancel(AUTO_ALARM_NOTIFICATION_ID)
                notificationManager.cancelAll()
                
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
            trackingManager.sendAllCancellationBroadcast()

            // 5단계: 모든 추적 작업과 서비스 중지
            Log.i(TAG, "🛑 5단계: 모든 추적 작업 중지 시작")
            trackingManager.stopAllTracking()
            
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
                trackingManager.stopSpecificTracking(command.routeId, command.busNo, command.stationName, command.shouldRemoveFromList)
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

            // startForegroundService()를 호출한 경우 5초 이내에 startForeground()를 반드시 호출해야 함
            // stationId 해결이나 추적 시작이 비동기여서 늦어지면 ForegroundServiceDidNotStartInTimeException 발생
            if (!isInForeground) {
                try {
                    val placeholder = notificationHandler.buildOngoingNotification(mapOf())
                    if (Build.VERSION.SDK_INT >= 36) {
                        startForeground(ONGOING_NOTIFICATION_ID, placeholder, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        startForeground(ONGOING_NOTIFICATION_ID, placeholder, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
                    } else {
                        startForeground(ONGOING_NOTIFICATION_ID, placeholder)
                    }
                    isInForeground = true
                    Log.d(TAG, "🔔 일반 알람: 포그라운드 서비스 즉시 시작")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 일반 알람 포그라운드 서비스 시작 오류: ${e.message}", e)
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
                trackingManager.stopTrackingIfIdle()
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
                        trackingManager.stopTrackingIfIdle()
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

                    notificationUpdater.showOngoingBusTracking(
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
                notificationUpdater.showOngoingBusTracking(
                    busNo = busNo,
                    stationName = stationName,
                    remainingMinutes = remainingMinutes,
                    currentStation = currentStation,
                    isUpdate = isUpdate,
                    notificationId = ONGOING_NOTIFICATION_ID,
                    allBusesSummary = allBusesSummary,
                    routeId = routeId,
                    stationId = resolvedStationId  // stationId 전달하여 즉시 유효성 검사 통과
                )
            }
            // [AUTO ALARM 실시간 정보 즉시 갱신] autoAlarmTask 등 자동알람 진입점에서 실시간 정보 즉시 fetch
            if (!routeId.isBlank() && !resolvedStationId.isNullOrBlank() && stationName.isNotBlank()) {
                trackingManager.updateBusInfo(routeId, resolvedStationId, stationName)
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
            // 단, 10초 이상 지난 경우는 새 알람으로 간주하여 기존 종료 후 재시작
            if (isAutoAlarmMode && currentAutoAlarmRouteId == routeIdText && routeIdText.isNotBlank()) {
                val timeSinceStart = System.currentTimeMillis() - autoAlarmStartTime
                if (timeSinceStart < 60000L) {
                    Log.w(TAG, "⚠️ 자동알람 이미 추적 중 (${timeSinceStart}ms 전 시작) - 중복 무시")
                    return START_NOT_STICKY
                }
                Log.i(TAG, "ℹ️ 새 자동알람 요청 (이전 시작 ${timeSinceStart/1000}초 전) - 기존 종료 후 재시작")
                autoAlarmNotifier.stopAutoAlarmLightweight()
            }

            // intent extras로 전달된 alertOnArrivalOnly를 인스턴스 필드에 반영
            alertOnArrivalOnly = intentAlertOnArrivalOnly
            val excludeHolidays = intent?.getBooleanExtra("excludeHolidays", false) ?: false
            Log.d(TAG, "🔔 자동알람 경량화 모드 시작: $autoAlarmBusNo 번, $autoAlarmStationName, TTS=$useTTS, ArrivalOnly=$alertOnArrivalOnly")
            autoAlarmNotifier.handleAutoAlarmLightweight(autoAlarmBusNo, autoAlarmStationName, remainingMinutes, currentStationText, routeIdText, stationIdText, useTTS, isCommuteAlarm, alarmHour, alarmMinute, targetAlarmTime, excludeHolidays)
        }
        ServiceCommand.StopAutoAlarm -> {
            Log.i(TAG, "🛑 ACTION_STOP_AUTO_ALARM received")

            // 사용자 수동 중지 플래그 설정 (자동 알람 재시작 방지)
            isManuallyStoppedByUser = true
            lastManualStopTime = System.currentTimeMillis()
            Log.w(TAG, "🛑 사용자 수동 중지 플래그 설정 (자동알람 중지)")

            // 자동알람 전체 종료: 경량화 알림 + 모든 추적 중지
            try {
                autoAlarmNotifier.stopAutoAlarmLightweight()
            } catch (_: Exception) { }

            // Flutter에 취소 이벤트 전달
            try {
                trackingManager.sendAllCancellationBroadcast()
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
        trackingManager.stopSpecificTracking(routeId, busNo, stationName, shouldRemoveFromList = true)
    }

    // 모든 추적 중지 (MainActivity 호출용)
    fun stopAllBusTracking() {
        trackingManager.stopAllTracking()
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

        alarmSoundPlayer.stop()
        trackingManager.stopAllTracking()
        ttsController.cleanupTts()
        serviceScope.cancel()

        super.onDestroy()
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    inner class LocalBinder : Binder() {
        fun getService(): BusAlertService = this@BusAlertService
    }

    internal fun startTracking(routeId: String, stationId: String, stationName: String, busNo: String, isAutoAlarm: Boolean = false, alarmId: Int? = null, isCommuteAlarm: Boolean = false, exactAlarmTriggerTime: Long? = null) {
        serviceScope.launch {
            try {
                Log.d(TAG, "🚀 startTracking 코루틴 시작: $busNo ($routeId), stationId=$stationId, isAutoAlarm=$isAutoAlarm")
                var realStationId = stationId
                if (stationId.length < 10 || !stationId.startsWith("7")) {
                    realStationId = busApiService.getStationIdFromBsId(stationId) ?: stationId
                    Log.d(TAG, "stationId 변환: $stationId → $realStationId")
                }
                startTrackingInternal(routeId, realStationId, stationName, busNo, isAutoAlarm, alarmId, isCommuteAlarm)
                exactAlarmTriggerTime?.let { activeTrackings[routeId]?.exactAlarmTriggerTime = it }
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

    private fun startBackupUpdateTimer() {
        stopMonitoringTimer()

        backupUpdateJob = serviceScope.launch {
            delay(30_000)
            while (isActive) {
                if (activeTrackings.isEmpty()) {
                    Log.d(TAG, "백업 타이머: 활성 추적 없음, 타이머 종료")
                    break
                }
                Log.d(TAG, "🔄 백업 타이머: 알림 갱신 (${activeTrackings.size}개)")
                try {
                    updateForegroundNotification()
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 백업 타이머 알림 업데이트 실패: ${e.message}")
                }
                delay(60_000)
            }
        }

        Log.d(TAG, "✅ 경량화된 백업 타이머 시작됨")
    }
    // updateBusInfo/checkNextBusAndNotify/checkArrivalAndNotify/updateTrackingInfoFromFlutter는
    // BusAlertTrackingManager로 이관 (2026-07-28, 1b-3).

    // Flutter에서 버스 정보 업데이트 수신 (공개 함수) — BusAlertTrackingManager로 이관
    // (2026-07-28, 1b-3). Public 시그니처는 BusApiChannelHandler가 호출하므로 유지.
    fun updateBusInfoFromFlutter(
        routeId: String,
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String?,
        estimatedTime: String?,
        isLowFloor: Boolean
    ) {
        trackingManager.updateBusInfoFromFlutter(routeId, busNo, stationName, remainingMinutes, currentStation, estimatedTime, isLowFloor)
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
            { b, s, r, c, routeId, summary ->
                notificationUpdater.showOngoingBusTracking(
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
            ttsController,
            { useTextToSpeech },
            ARRIVAL_THRESHOLD_MINUTES,
            this,
            monitoredRoutes,
            arrivingSoonNotified,
            hasNotifiedTts,
            hasNotifiedArrival,
            ::generateNotificationId,
            { isInForeground = it },
            ONGOING_NOTIFICATION_ID,
            cachedBusInfo,
            { isServiceActive },
            { isServiceActive = it },
            { isManuallyStoppedByUser },
            { isManuallyStoppedByUser = it },
            { lastManualStopTime = it },
            { lastManualStopTime },
            { isAutoAlarmMode = it },
            { autoAlarmStartTime = it },
            { instance = null },
            { isInForeground },
            ::stopMonitoringTimer,
            ::stopTtsTracking,
            ::checkAndStopServiceIfNeeded,
            AUTO_ALARM_NOTIFICATION_ID,
            notificationHandler,
            RESTART_PREVENTION_DURATION,
            { alertOnArrivalOnly },
        )
        loadSettings()
        notificationHandler.createNotificationChannels()
    }

    fun addMonitoredRoute(routeId: String, stationId: String, stationName: String) {
        monitoredRoutes[routeId] = Triple(stationId, stationName, monitoringJobs[routeId])
        Log.d(TAG, "Added route to monitored list: $routeId at $stationName ($stationId)")
    }

    // stationId 보정 함수 (정류장 이름 매핑 우선)
    internal suspend fun resolveStationIdIfNeeded(routeId: String, stationName: String, stationId: String, wincId: String?): String {
        if (stationId.length == 10 && stationId.startsWith("7")) return stationId

        // 1. wincId가 있으면 사용
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

    // BusAlertNotificationUpdater.showOngoingBusTracking으로 이관 (2026-07-25). Public
    // 시그니처는 BusTrackingChannelHandler가 호출하므로 유지.
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
        wincId: String? = null,
        isIndividualAlarm: Boolean = false
    ) {
        notificationUpdater.showOngoingBusTracking(
            busNo, stationName, remainingMinutes, currentStation, isUpdate, notificationId,
            allBusesSummary, routeId, stationId, wincId, isIndividualAlarm
        )
    }

    // BusAlertAutoAlarmNotifier.updateAutoAlarmBusInfo로 이관 (2026-07-25). 저장소 전체
    // grep 결과 외부 호출부가 없었지만 public API라 위임 스텁은 남겨둔다.
    fun updateAutoAlarmBusInfo(
        busNo: String,
        stationName: String,
        routeId: String,
        stationId: String,
        remainingMinutes: Int,
        currentStation: String
    ) {
        autoAlarmNotifier.updateAutoAlarmBusInfo(busNo, stationName, routeId, stationId, remainingMinutes, currentStation)
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

    fun setAlertOnArrivalOnly(value: Boolean) {
        Log.d(TAG, "setAlertOnArrivalOnly: $value")
        alertOnArrivalOnly = value
    }

    fun setAudioOutputMode(mode: Int) {
        Log.d(TAG, "setAudioOutputMode called: $mode")
        if (mode in OUTPUT_MODE_HEADSET..OUTPUT_MODE_AUTO) {
            audioOutputMode = mode
            ttsController.setAudioOutputMode(audioOutputMode)
            applicationContext.getSharedPreferences("AppSettings", Context.MODE_PRIVATE)
                .edit().putInt("speaker_mode", mode).apply()
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

    fun cancelOngoingTracking() = trackingManager.cancelOngoingTracking()

    // 알림 취소 (MainActivity 호출 호환)
    fun cancelNotification(id: Int) = trackingManager.cancelNotification(id)

    // 모든 알림 취소
    fun cancelAllNotifications() = trackingManager.cancelAllNotifications()

    // cancelOngoingTracking/cancelNotification/cancelAllNotifications/stopTrackingIfIdle/
    // sendAllCancellationBroadcast는 BusAlertTrackingManager로 이관 (2026-07-28, 1b-2).
    // checkAndStopService()는 저장소 전체 참조 0건(private, dead code)이라 이관 대신 삭제.

    private val hasNotifiedTts = HashSet<String>()
    private val hasNotifiedArrival = HashSet<String>()

    // checkArrivalAndNotify는 BusAlertTrackingManager로 이관 (2026-07-28, 1b-3).

    // BusAlertTrackingManager로 이관 (2026-07-28, 1b-3). Public 시그니처는
    // BusTrackingChannelHandler가 호출하므로 유지.
    fun updateTrackingInfoFromFlutter(
        routeId: String,
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String
    ) {
        trackingManager.updateTrackingInfoFromFlutter(routeId, busNo, stationName, remainingMinutes, currentStation)
    }

    /**
     * 버스 추적 알림을 업데이트하는 메서드 (MainActivity에서 직접 호출)
     */
    // BusAlertNotificationUpdater.updateTrackingNotification으로 이관 (2026-07-25). Public
    // 시그니처는 BusTrackingChannelHandler가 호출하므로 유지.
    fun updateTrackingNotification(
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        currentStation: String,
        routeId: String,
        stationId: String? = null,
        wincId: String? = null
    ) {
        notificationUpdater.updateTrackingNotification(busNo, stationName, remainingMinutes, currentStation, routeId, stationId, wincId)
    }

// 모든 추적 중지

    // BusAlertTrackingManager.stopTrackingForRoute로 이관 (2026-07-25). Public 시그니처는
    // 채널 핸들러(BusApiChannelHandler/BusTrackingChannelHandler)가 호출하므로 유지.
    fun stopTrackingForRoute(routeId: String, stationId: String? = null, busNo: String? = null, cancelNotification: Boolean = false, notificationId: Int? = null) {
        trackingManager.stopTrackingForRoute(routeId, stationId, busNo, cancelNotification, notificationId)
    }

    // 포그라운드 알림 갱신
    internal fun updateForegroundNotification() {
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

    private fun stopMonitoringTimer() {
        backupUpdateJob?.cancel()
        backupUpdateJob = null
        Log.d(TAG, "Monitoring timer stopped (stopMonitoringTimer)")
    }

    // [ADD] Stop TTS tracking (set isTtsTrackingActive to false and clean up)
    fun stopTtsTracking(forceStop: Boolean = false) {
        isTtsTrackingActive = false
        // If there are any TTS-related jobs/handlers, stop them here (expand as needed)
        Log.d(TAG, "TTS tracking stopped (stopTtsTracking), forceStop=$forceStop")
    }

    // BusAlertNotificationUpdater.showBusArrivingSoon으로 이관 (2026-07-25). 저장소 전체
    // grep 결과 외부 호출부가 없었지만 public API라 위임 스텁은 남겨둔다.
    fun showBusArrivingSoon(busNo: String, stationName: String, currentStation: String?) {
        notificationUpdater.showBusArrivingSoon(busNo, stationName, currentStation)
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
        notificationUpdater.showOngoingBusTracking(
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
    internal var currentAutoAlarmBusNo: String = ""
    internal var currentAutoAlarmStationName: String = ""
    internal var currentAutoAlarmRouteId: String = ""

    // handleAutoAlarmLightweight/stopAutoAlarmLightweight는 BusAlertAutoAlarmNotifier로
    // 이관 (2026-07-25).
}

// NotificationDismissReceiver / isSamsungOneUi / getNotificationChannels / toMap 확장 함수는
// BusAlertModels.kt로 이관 (2026-07-28, 1b-1).
