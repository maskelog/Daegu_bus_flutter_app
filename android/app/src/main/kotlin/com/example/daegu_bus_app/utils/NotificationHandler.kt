package com.example.daegu_bus_app.utils

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.util.Log
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import com.example.daegu_bus_app.services.BusAlertService
import com.example.daegu_bus_app.MainActivity
import com.example.daegu_bus_app.R
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.net.Uri
import android.provider.Settings

class NotificationHandler(private val context: Context) {

    companion object {
        private const val TAG = "NotificationHandler"

        // Notification Channel IDs
        private const val CHANNEL_ID_ONGOING = "bus_tracking_ongoing"
        private const val CHANNEL_NAME_ONGOING = "실시간 버스 추적"
        private const val CHANNEL_ID_ALERT = "bus_tracking_alert"
        private const val CHANNEL_NAME_ALERT = "버스 도착 임박 알림"
        private const val CHANNEL_ID_ERROR = "bus_tracking_error"
        private const val CHANNEL_NAME_ERROR = "추적 오류 알림"

        // Notification IDs
        const val ONGOING_NOTIFICATION_ID = 1 // Referenced by BusAlertService
        private const val ALERT_NOTIFICATION_ID_BASE = 1000 // Base for dynamic alert IDs
        const val ARRIVING_SOON_NOTIFICATION_ID = 2 // For arriving soon notifications

        // Intent Actions (referenced by notifications) - BusAlertService와 통일
        const val ACTION_STOP_TRACKING = "com.example.daegu_bus_app.action.STOP_TRACKING"
        const val ACTION_STOP_SPECIFIC_ROUTE_TRACKING = "com.example.daegu_bus_app.action.STOP_SPECIFIC_ROUTE_TRACKING"
        const val ACTION_CANCEL_NOTIFICATION = "com.example.daegu_bus_app.action.CANCEL_NOTIFICATION"

        private val lastRemainingMinutesByRoute = mutableMapOf<String, Int>()
    }

     // --- Notification Channel Creation ---

    fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                // Android 16+ (SDK 36): 기존 채널 삭제 후 재생성하여 Live Update "실시간 정보" 설정이 OS에 등록되도록 함
                // 채널이 이전 SDK 타겟에서 생성된 경우 OS가 promoted notification 기능을 인식하지 못함
                if (Build.VERSION.SDK_INT >= 36) {
                    val prefs = context.getSharedPreferences("notification_channel_prefs", Context.MODE_PRIVATE)
                    val migrationKey = "channel_migrated_sdk36_v3_importance_default"
                    if (!prefs.getBoolean(migrationKey, false)) {
                        try {
                            notificationManager.deleteNotificationChannel(CHANNEL_ID_ONGOING)
                            Log.d(TAG, "🔄 Android 16 채널 마이그레이션: 기존 ongoing 채널 삭제")
                        } catch (e: Exception) {
                            Log.w(TAG, "⚠️ 기존 채널 삭제 실패 (이미 없을 수 있음): ${e.message}")
                        }
                        prefs.edit().putBoolean(migrationKey, true).apply()
                        Log.d(TAG, "✅ Android 16 채널 마이그레이션 완료 (v3 - IMPORTANCE_DEFAULT)")
                    }
                }

                // Ongoing Channel (Live Update / 실시간 정보 지원)
                // Google 샘플과 동일하게 IMPORTANCE_DEFAULT 사용 - Live Update 토글이 설정에 표시되기 위한 요건
                val ongoingChannel = NotificationChannel(
                    CHANNEL_ID_ONGOING,
                    CHANNEL_NAME_ONGOING,
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "실시간 버스 추적 상태 알림"
                    enableVibration(false)
                    enableLights(false)
                    setShowBadge(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    setBypassDnd(false)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        setAllowBubbles(false)
                    }
                }

                // Alert Channel (Maximum importance for critical alerts)
                val alertChannel = NotificationChannel(
                    CHANNEL_ID_ALERT,
                    CHANNEL_NAME_ALERT,
                    NotificationManager.IMPORTANCE_MAX // 최고 우선순위로 변경
                ).apply {
                    description = "버스 도착 임박 시 알림"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500) // 더 강력한 진동 패턴
                    lightColor = ContextCompat.getColor(context, R.color.tracking_color) // Use context
                    enableLights(true)
                    setShowBadge(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    setBypassDnd(true) // 방해금지 모드에서도 표시
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        setAllowBubbles(true) // 버블 알림 허용
                    }
                }

                // Error Channel (Default importance)
                 val errorChannel = NotificationChannel(
                    CHANNEL_ID_ERROR,
                    CHANNEL_NAME_ERROR,
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "버스 추적 중 오류 발생 알림"
                    enableVibration(true)
                    setShowBadge(true)
                }

                notificationManager.createNotificationChannel(ongoingChannel)
                notificationManager.createNotificationChannel(alertChannel)
                notificationManager.createNotificationChannel(errorChannel)
                Log.d(TAG, "Notification channels created.")
            } catch (e: Exception) {
                Log.e(TAG, "Error creating notification channels: ${e.message}", e)
            }
        }
    }

    private fun isSamsungOneUi(): Boolean {
        return Build.MANUFACTURER.equals("samsung", ignoreCase = true)
    }

    // 알림 종료 브로드캐스트 리시버 등록 (앱 시작 시 1회만 등록 필요)
    init {
        try {
            val filter = IntentFilter(BusAlertService.ACTION_STOP_TRACKING)
            // Android 14 이상에서는 RECEIVER_NOT_EXPORTED 플래그 필수
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(NotificationCancelReceiver(), filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(NotificationCancelReceiver(), filter)
            }
            Log.d(TAG, "NotificationCancelReceiver 등록 성공")
        } catch (e: Exception) {
            Log.e(TAG, "NotificationCancelReceiver 등록 오류: ${e.message}", e)
        }
    }

    // 알림 종료 브로드캐스트 리시버
    class NotificationCancelReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val routeId = intent.getStringExtra("routeId") ?: return
            val busNo = intent.getStringExtra("busNo") ?: return
            val stationName = intent.getStringExtra("stationName") ?: return
            Log.i(TAG, "[BR] 알림 종료 브로드캐스트 수신: $busNo, $routeId, $stationName")
            // BusAlertService에 종료 인텐트 전달
            val stopIntent = Intent(context, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_STOP_TRACKING
                putExtra("routeId", routeId)
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
            }
            context.startService(stopIntent)
            Log.i(TAG, "[BR] BusAlertService에 종료 인텐트 전달 완료")
        }
    }

    // 종료 브로드캐스트 PendingIntent 생성 헬퍼
    private fun createCancelBroadcastPendingIntent(
        routeId: String?,
        busNo: String?,
        stationName: String?,
        notificationId: Int,
        isAutoAlarm: Boolean = false
    ): PendingIntent {
        val cancelIntent = Intent(context, BusAlertService::class.java).apply {
            action = if (isAutoAlarm) {
                // 자동알람은 전체 자동알람 모드 종료 액션 제공
                BusAlertService.ACTION_STOP_AUTO_ALARM
            } else {
                // 일반 알람도 개별 중지 액션 사용 (전체 추적 중지가 아닌 특정 알람만 중지)
                BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
            }
            putExtra("routeId", routeId)
            putExtra("busNo", busNo)
            putExtra("stationName", stationName)
            putExtra("notificationId", notificationId)
            putExtra("isAutoAlarm", isAutoAlarm)
            putExtra("shouldRemoveFromList", true)
        }
        return PendingIntent.getService(
            context, notificationId + if (isAutoAlarm) 5000 else 0, cancelIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    // --- Ongoing Notification ---

    fun buildOngoingNotification(activeTrackings: Map<String, com.example.daegu_bus_app.services.TrackingInfo>): Notification {
        val startTime = System.currentTimeMillis()
        val currentTimeStr = SimpleDateFormat("HH:mm:ss.SSS", Locale.getDefault()).format(Date())
        var shouldVibrateOnChange = false
        Log.d(TAG, "🔔 알림 생성 시작 - $currentTimeStr")

        // 각 활성 추적의 버스 정보를 로그로 출력
        activeTrackings.forEach { (routeId, info) ->
            val busInfo = info.lastBusInfo
            Log.d(TAG, "🔍 추적 상태: ${info.busNo}번 버스, 시간=${busInfo?.estimatedTime ?: "정보 없음"}, 위치=${busInfo?.currentStation ?: "위치 정보 없음"}")
            if (busInfo != null) {
                val currentMinutes = busInfo.getRemainingMinutes()
                val prevMinutes = lastRemainingMinutesByRoute[routeId]
                if (prevMinutes != null &&
                    currentMinutes >= 0 &&
                    prevMinutes >= 0 &&
                    currentMinutes != prevMinutes
                ) {
                    shouldVibrateOnChange = true
                }
                lastRemainingMinutesByRoute[routeId] = currentMinutes
            }
        }

        val currentTime = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date()) // 현재 시간을 초 단위까지 표시
        var title = "버스 알람 추적 중 ($currentTime)"
        var contentText = "추적 중인 버스: ${activeTrackings.size}개"

        val inboxStyle = NotificationCompat.InboxStyle()
            .setBigContentTitle(title)

        if (activeTrackings.isEmpty()) {
            contentText = "추적 중인 버스가 없습니다."
            inboxStyle.addLine(contentText)
            Log.d(TAG, "🚫 추적 중인 버스 없음")
        } else {
            Log.d(TAG, "📊 추적 중인 버스 수: ${activeTrackings.size}")
            activeTrackings.values.take(5).forEach { trackingInfo ->
                val busInfo = trackingInfo.lastBusInfo
                val busNo = trackingInfo.busNo
                val stationNameShort = trackingInfo.stationName.take(10) + if (trackingInfo.stationName.length > 10) "..." else ""

                // 시간 정보 처리 개선
                val timeStr = when {
                    busInfo == null -> "정보 없음"
                    busInfo.estimatedTime == "운행종료" -> "운행종료"
                    busInfo.estimatedTime == "곧 도착" -> "곧 도착"
                    busInfo.estimatedTime.contains("분") -> {
                        val minutes = busInfo.estimatedTime.replace("[^0-9]".toRegex(), "").toIntOrNull()
                        if (minutes != null) {
                            if (minutes <= 0) "곧 도착" else "${minutes}분"
                        } else busInfo.estimatedTime
                    }
                    busInfo.getRemainingMinutes() <= 0 -> "곧 도착"
                    trackingInfo.consecutiveErrors > 0 -> "오류"
                    else -> busInfo.estimatedTime
                }

                // 현재 위치 정보 추가
                val locationInfo = if (busInfo?.currentStation != null && busInfo.currentStation.isNotEmpty()) {
                    " [현재: ${busInfo.currentStation}]"
                } else {
                    ""
                }

                val lowFloorStr = if (busInfo?.isLowFloor == true) "(저)" else ""
                val infoLine = "$busNo$lowFloorStr (${stationNameShort}): $timeStr$locationInfo"
                inboxStyle.addLine(infoLine)
                Log.d(TAG, "➕ 알림 라인 추가: $infoLine")
                Log.d(TAG, "🚍 버스 정보 디버깅: 버스=$busNo, 위치=${busInfo?.currentStation ?: "위치 없음"}, 시간=$timeStr")
            }

            if (activeTrackings.size > 5) {
                inboxStyle.setSummaryText("+${activeTrackings.size - 5}개 더 추적 중")
            }

            // 첫 번째 버스 정보를 contentText에 표시
            val firstTracking = activeTrackings.values.firstOrNull()
            if (firstTracking != null) {
                val busInfo = firstTracking.lastBusInfo
                val busNo = firstTracking.busNo
                val timeStr = when {
                    busInfo == null -> "정보 없음"
                    busInfo.estimatedTime == "운행종료" -> "운행종료"
                    busInfo.estimatedTime == "곧 도착" -> "곧 도착"
                    busInfo.estimatedTime.contains("분") -> {
                        val minutes = busInfo.estimatedTime.replace("[^0-9]".toRegex(), "").toIntOrNull()
                        if (minutes != null) {
                            if (minutes <= 0) "곧 도착" else "${minutes}분"
                        } else busInfo.estimatedTime
                    }
                    busInfo.getRemainingMinutes() <= 0 -> "곧 도착"
                    firstTracking.consecutiveErrors > 0 -> "오류"
                    else -> busInfo.estimatedTime
                }

                // 현재 위치 정보 추가 (전체 표시)
                val locationInfo = if (busInfo?.currentStation != null && busInfo.currentStation.isNotEmpty()) {
                    " [${busInfo.currentStation}]"
                } else {
                    ""
                }

                val headerText = buildTrackingHeadline(busNo, timeStr)
                title = headerText
                contentText = buildTrackingContentText(
                    stationName = firstTracking.stationName,
                    timeText = timeStr,
                    locationInfo = locationInfo,
                    extraTrackingCount = activeTrackings.size - 1
                )
                inboxStyle.setBigContentTitle(headerText)
                Log.d(TAG, "📝 알림 텍스트 업데이트: $contentText")
            }
        }

        // NotificationCompat.Builder에 setWhen 추가 및 FLAG_ONGOING_EVENT 플래그 추가
        val notificationBuilder = NotificationCompat.Builder(context, CHANNEL_ID_ONGOING)
            .setContentTitle(title)
            .setContentText(contentText)
            .setSmallIcon(R.drawable.ic_bus_notification)
            .setPriority(NotificationCompat.PRIORITY_HIGH) // 높은 우선순위 유지
                        .setContentIntent(createPendingIntent())
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
            .setColor(ContextCompat.getColor(context, R.color.tracking_color))
            .setColorized(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC) // 잠금화면에서 전체 내용 표시
            .setTimeoutAfter(0) // 자동 삭제 방지
            .setLocalOnly(false) // 웨어러블 기기에도 표시

        val firstTracking = activeTrackings.values.firstOrNull()
        val smallViews = buildTrackingSmallRemoteViews(title, contentText)
        val bigViews = buildTrackingRemoteViews(title, contentText, firstTracking)
        notificationBuilder
            .setStyle(NotificationCompat.DecoratedCustomViewStyle())
            .setCustomContentView(smallViews)
            .setCustomBigContentView(bigViews)


        // 추적 중지 버튼 추가
        Log.d(TAG, "🔔🔔🔔 '추적 중지' 버튼 추가 시작 🔔🔔🔔")
        val stopPendingIntent = createStopPendingIntent()
        Log.d(TAG, "🔔 Stop PendingIntent 생성됨: $stopPendingIntent")
        notificationBuilder.addAction(
            R.drawable.ic_stop_tracking,
            "추적 중지",
            stopPendingIntent
        )
        Log.d(TAG, "🔔 '추적 중지' 액션 추가 완료")

        // 자동알람 중지 액션 추가: 활성 추적 중 자동알람이 하나라도 있으면 버튼 표시
        val hasAutoAlarm = activeTrackings.values.any { it.isAutoAlarm }
        if (hasAutoAlarm) {
            Log.d(TAG, "🔔 자동알람 감지됨 - '중지' 버튼 추가")
            notificationBuilder.addAction(
                R.drawable.ic_cancel,
                "중지",
                createStopAutoAlarmPendingIntent()
            )
        }

        // Android 버전 및 Live Updates 지원 여부 로깅
        Log.d(TAG, "📱 ===== Android 버전 정보 =====")
        Log.d(TAG, "📱 SDK Version: ${Build.VERSION.SDK_INT}")
        Log.d(TAG, "📱 Release: ${Build.VERSION.RELEASE}")
        Log.d(TAG, "📱 Manufacturer: ${Build.MANUFACTURER}")
        Log.d(TAG, "📱 Model: ${Build.MODEL}")
        Log.d(TAG, "📱 Live Updates API 지원: ${if (Build.VERSION.SDK_INT >= 36) "✅ YES (Android 16+)" else "❌ NO (Android ${Build.VERSION.RELEASE})"}")
        Log.d(TAG, "📱 ================================")

        // Android 16+ (API 36): NotificationCompat.Builder 사용 + FLAG_PROMOTED_ONGOING 수동 보완
        // 문제: NotificationCompat.Builder.setRequestPromotedOngoing()가 extras에는 기록하지만
        // notification.flags의 FLAG_PROMOTED_ONGOING 비트를 직접 설정하지 않을 수 있음.
        // 이로 인해 hasPromotableCharacteristics()가 false → "실시간 정보" 토글 미표시.
        // 해결: 빌드 후 리플렉션으로 FLAG_PROMOTED_ONGOING 값을 읽어 flags에 수동 설정.
        val notification = if (Build.VERSION.SDK_INT >= 36) {
            try {
                // 가장 가까운 버스 정보 가져오기
                val firstTracking = activeTrackings.values.firstOrNull()

                // 버스 타입별 색상 결정 (첫 번째 버스 기준)
                val busTypeColor = when (firstTracking?.routeTCd) {
                    "1" -> 0xFFDC2626.toInt() // 급행: 빨간색
                    "2" -> 0xFFF59E0B.toInt() // 좌석: 주황색
                    "3" -> 0xFF2563EB.toInt() // 일반: 파란색
                    "4" -> 0xFF10B981.toInt() // 지선/마을: 초록색
                    else -> ContextCompat.getColor(context, R.color.tracking_color) // 기본값
                }

                val largeBusIconBitmap = if (firstTracking != null) {
                    createColoredBusIcon(context, busTypeColor, firstTracking.busNo)
                } else {
                    null
                }

                val liveBuilder = NotificationCompat.Builder(context, CHANNEL_ID_ONGOING)
                    .setSmallIcon(R.drawable.ic_bus_notification)
                    .setContentTitle(title)
                    .setContentText(contentText)
                    .setContentIntent(createPendingIntent())
                    .setOngoing(true)
                    .setOnlyAlertOnce(true)
                    .setRequestPromotedOngoing(true)
                    .setCategory(Notification.CATEGORY_PROGRESS)
                    .setColor(busTypeColor)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                    .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
                    .addAction(R.drawable.ic_stop_tracking, "추적 중지", stopPendingIntent)

                if (largeBusIconBitmap != null) {
                    liveBuilder.setLargeIcon(largeBusIconBitmap)
                }

                // --- Live Update Promotable Characteristics Checks ---
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                @Suppress("NewApi")
                val canPostPromoted = try {
                    notificationManager.canPostPromotedNotifications()
                } catch (e: Exception) {
                    Log.e(TAG, "❌ canPostPromotedNotifications 호출 실패: ${e.message}")
                    false
                }
                Log.d(TAG, "📋 NotificationManager.canPostPromotedNotifications(): $canPostPromoted")

                // Live Update 핵심: ProgressStyle + setShortCriticalText
                if (firstTracking != null) {
                    val busInfo = firstTracking.lastBusInfo

                    // 1. 상태 칩 텍스트 계산
                    val remainingStopsInt = busInfo?.remainingStops
                        ?.filter { it.isDigit() }?.toIntOrNull() ?: 0
                    val timeMinutes = when {
                        busInfo == null -> -1
                        busInfo.estimatedTime.contains("분") ->
                            busInfo.estimatedTime.replace("[^0-9]".toRegex(), "").toIntOrNull() ?: busInfo.getRemainingMinutes()
                        else -> busInfo.getRemainingMinutes()
                    }
                    val computedChipText = buildLiveUpdateStatusChipText(
                        busInfo?.estimatedTime,
                        timeMinutes,
                        remainingStopsInt
                    )

                    val remainingMinutes = busInfo?.getRemainingMinutes() ?: 0
                    val arrivalTimeMillis = if (remainingMinutes > 0) {
                        System.currentTimeMillis() + (remainingMinutes * 60 * 1000L)
                    } else {
                        System.currentTimeMillis() + 60000L
                    }
                    liveBuilder.setShortCriticalText(
                        computedChipText.trim().take(10).ifBlank { "정보 없음" }
                    )
                    liveBuilder.setWhen(arrivalTimeMillis)
                    liveBuilder.setUsesChronometer(true)
                    liveBuilder.setChronometerCountDown(true)
                    liveBuilder.setShowWhen(true)
                    Log.d(TAG, "✅ setShortCriticalText 적용 완료 ('$computedChipText')")
                    Log.d(TAG, "⏰ setWhen 설정: ${remainingMinutes}분 후 ($arrivalTimeMillis)")

                    // 4. ProgressStyle 설정 (NotificationCompat.ProgressStyle)
                    val maxMinutes = 30
                    val clampedRemainingMinutes = remainingMinutes.coerceIn(0, maxMinutes)
                    val progressPercent = if (clampedRemainingMinutes <= 0) 100
                                          else ((maxMinutes - clampedRemainingMinutes) * 100 / maxMinutes)
                    val progress = progressPercent.coerceIn(0, 100)
                    val remainingPercent = (100 - progress).coerceIn(0, 100)

                    Log.d(TAG, "🎯 Progress 계산: remaining=${remainingMinutes}분, progress=${progress}%")

                    try {
                        val progressStyle = NotificationCompat.ProgressStyle()
                            .setProgress(progress)
                            .setProgressTrackerIcon(
                                androidx.core.graphics.drawable.IconCompat.createWithResource(
                                    context,
                                    R.drawable.ic_bus_tracker
                                )
                            )

                        // Segments: 진행 구간 (버스 색상) + 남은 구간 (회색)
                        val segments = mutableListOf<NotificationCompat.ProgressStyle.Segment>()
                        if (progress > 0) {
                            segments.add(NotificationCompat.ProgressStyle.Segment(progress).setColor(busTypeColor))
                        }
                        if (remainingPercent > 0) {
                            segments.add(
                                NotificationCompat.ProgressStyle.Segment(remainingPercent)
                                    .setColor(0xFFE0E0E0.toInt())
                            )
                        }
                        if (segments.isNotEmpty()) {
                            progressStyle.setProgressSegments(segments)
                        }

                        // Points: 출발 (초록) + 도착 (주황)
                        progressStyle.setProgressPoints(listOf(
                            NotificationCompat.ProgressStyle.Point(1).setColor(0xFF4CAF50.toInt()),
                            NotificationCompat.ProgressStyle.Point(100).setColor(0xFFFF5722.toInt())
                        ))

                        liveBuilder.setStyle(progressStyle)
                        Log.d(TAG, "✅ NotificationCompat.ProgressStyle 설정 완료")
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ ProgressStyle 설정 실패: ${e.message}", e)
                    }

                    Log.d(TAG, "🎯 Live Update 설정 완료:")
                    Log.d(TAG, "   - Builder: NotificationCompat.Builder")
                    Log.d(TAG, "   - ProgressStyle: NotificationCompat.ProgressStyle")
                    Log.d(TAG, "   - setShortCriticalText: '$computedChipText'")
                    Log.d(TAG, "   - setRequestPromotedOngoing: true")
                    Log.d(TAG, "   - setProgress: $progress/100")
                    Log.d(TAG, "   - SDK Version: ${Build.VERSION.SDK_INT}")
                }

                // 자동알람 중지 액션
                if (hasAutoAlarm) {
                    liveBuilder.addAction(R.drawable.ic_cancel, "중지", createStopAutoAlarmPendingIntent())
                }

                // 승격 불가 시 설정 바로가기
                if (!canPostPromoted) {
                    try {
                        val manageSettingsIntent = Intent(Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS).apply {
                            putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                        }
                        val manageSettingsPendingIntent = PendingIntent.getActivity(
                            context, 9997, manageSettingsIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        liveBuilder.addAction(R.drawable.ic_cancel, "알림 설정", manageSettingsPendingIntent)
                        Log.d(TAG, "⚙️ '알림 설정' 액션 추가됨 (Promoted Notifications 비활성화됨)")
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ '알림 설정' 액션 추가 실패: ${e.message}")
                    }
                }

                // 최종 빌드
                val builtNotification = liveBuilder.build()

                // FLAG_PROMOTED_ONGOING 수동 보완:
                // NotificationCompat.Builder.setRequestPromotedOngoing()가 notification.flags에
                // FLAG_PROMOTED_ONGOING 비트를 설정하지 않는 경우를 대비해 리플렉션으로 직접 설정.
                // hasPromotableCharacteristics()가 true이면 이미 설정된 것이므로 생략.
                @Suppress("NewApi")
                val hasPromotableCharacteristics = try {
                    builtNotification.hasPromotableCharacteristics()
                } catch (e: Exception) {
                    Log.e(TAG, "❌ hasPromotableCharacteristics 호출 실패: ${e.message}")
                    false
                }
                if (!hasPromotableCharacteristics) {
                    try {
                        val flagField = Notification::class.java.getField("FLAG_PROMOTED_ONGOING")
                        val flagValue = flagField.getInt(null)
                        builtNotification.flags = builtNotification.flags or flagValue
                        Log.d(TAG, "✅ FLAG_PROMOTED_ONGOING ($flagValue=0x${Integer.toHexString(flagValue)}) 리플렉션으로 수동 설정됨")
                    } catch (e: NoSuchFieldException) {
                        // FLAG_PROMOTED_ONGOING이 아직 공개 API가 아닌 경우 — setRequestPromotedOngoing 리플렉션 시도
                        try {
                            val method = builtNotification.javaClass.getMethod(
                                "setRequestPromotedOngoing", Boolean::class.javaPrimitiveType
                            )
                            method.invoke(builtNotification, true)
                            Log.d(TAG, "✅ setRequestPromotedOngoing(true) 리플렉션 폴백 적용됨")
                        } catch (e2: Exception) {
                            Log.w(TAG, "⚠️ FLAG_PROMOTED_ONGOING 수동 설정 불가: ${e2.message}")
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ FLAG_PROMOTED_ONGOING 리플렉션 오류: ${e.message}")
                    }
                }

                @Suppress("NewApi")
                val hasPromotableAfterFix = try {
                    builtNotification.hasPromotableCharacteristics()
                } catch (e: Exception) { false }
                Log.d(TAG, "📋 hasPromotableCharacteristics (수동 보완 후): $hasPromotableAfterFix")
                Log.d(TAG, "📋 canPostPromotedNotifications: $canPostPromoted")
                Log.d(TAG, "📋 notification.flags: ${Integer.toHexString(builtNotification.flags)}")

                builtNotification
            } catch (e: Exception) {
                Log.e(TAG, "❌ Android 16 NotificationCompat.Builder 오류: ${e.message}", e)
                e.printStackTrace()
                val compatNotification = notificationBuilder.build()
                val fallbackFlags = Notification.FLAG_ONGOING_EVENT or
                    Notification.FLAG_NO_CLEAR or Notification.FLAG_FOREGROUND_SERVICE
                compatNotification.flags = compatNotification.flags or fallbackFlags
                compatNotification
            }
        } else {
            // Android 15 이하는 기존 NotificationCompat 사용
            val compatNotification = notificationBuilder.build()
            val compatFlags = Notification.FLAG_ONGOING_EVENT or
                Notification.FLAG_NO_CLEAR or Notification.FLAG_FOREGROUND_SERVICE
            compatNotification.flags = compatNotification.flags or compatFlags
            compatNotification
        }

        val endTime = System.currentTimeMillis()
        Log.d(TAG, "✅ 알림 생성 완료 - 소요시간: ${endTime - startTime}ms, 현재 시간: $currentTime")

        if (shouldVibrateOnChange && isVibrationEnabled()) {
            vibrateOnce()
        }

        return notification
    }

    // Android 16 Live Update 상태칩 적용 헬퍼
    private fun buildLiveUpdateStatusChipText(
        estimatedTime: String?,
        remainingMinutes: Int,
        remainingStops: Int
    ): String {
        val normalized = estimatedTime?.trim().orEmpty().replace(" ", "")
        val normalizedNormalized = when {
            normalized.contains("곧") && normalized.contains("도착") -> "도착"
            normalized == "운행종료" || normalized == "지나감" -> "지나감"
            normalized.contains("도착") -> "도착"
            else -> normalized
        }

        if (remainingMinutes < 0) {
            return "지나감"
        }

        if (normalizedNormalized == "지나감") {
            return "지나감"
        }

        val minutePart = if (normalizedNormalized.contains("분")) {
            normalizedNormalized.replace("[^0-9]".toRegex(), "").toIntOrNull()
        } else {
            null
        } ?: remainingMinutes

        if (normalizedNormalized == "도착" || minutePart <= 0 || remainingMinutes <= 0) {
            return "도착"
        }

        if (minutePart > 0) {
            return "${minutePart}분"
        }

        return if (remainingStops > 0) "${remainingStops}개전" else "정보 없음"
    }

    private fun buildTrackingHeadline(busNo: String, timeText: String): String {
        return when (timeText) {
            "정보 없음" -> "${busNo}번 도착 정보 없음"
            "오류" -> "${busNo}번 정보 확인 중"
            "운행종료" -> "${busNo}번 운행종료"
            else -> "${busNo}번 $timeText"
        }
    }

    private fun buildTrackingContentText(
        stationName: String,
        timeText: String,
        locationInfo: String,
        extraTrackingCount: Int
    ): String {
        val stationLabel = if (stationName.length > 12) {
            "${stationName.take(12)}.."
        } else {
            stationName
        }
        val extraLabel = if (extraTrackingCount > 0) " +$extraTrackingCount" else ""
        return "$stationLabel · $timeText$locationInfo$extraLabel"
    }


    // 버스 아이콘 비트맵 생성 함수 (Live Update 영역에 표시되도록 최적화)
    private fun createColoredBusIcon(context: Context, color: Int, busNo: String): android.graphics.Bitmap? {
        try {
            // Live Update 아이콘 권장 크기: 48x48dp (mdpi 기준)
            val density = context.resources.displayMetrics.density
            val iconSizePx = (48 * density).toInt()

            val drawable = ContextCompat.getDrawable(context, R.drawable.ic_bus_large)
                ?: ContextCompat.getDrawable(context, R.drawable.ic_bus_notification)
                ?: return null

            val bitmap = android.graphics.Bitmap.createBitmap(
                iconSizePx,
                iconSizePx,
                android.graphics.Bitmap.Config.ARGB_8888
            )
            val canvas = android.graphics.Canvas(bitmap)

            // 배경에 원형 그리기 (더 눈에 띄게)
            val paint = android.graphics.Paint().apply {
                this.color = color
                isAntiAlias = true
                style = android.graphics.Paint.Style.FILL
            }
            val centerX = iconSizePx / 2f
            val centerY = iconSizePx / 2f
            val radius = iconSizePx / 2f - 2 * density
            canvas.drawCircle(centerX, centerY, radius, paint)

            // 아이콘 그리기 (흰색으로)
            val iconPadding = (8 * density).toInt()
            drawable.setBounds(iconPadding, iconPadding, iconSizePx - iconPadding, iconSizePx - iconPadding)
            drawable.setTint(android.graphics.Color.WHITE)
            drawable.draw(canvas)

            Log.d(TAG, "🎨 Live Update 아이콘 생성 완료: ${iconSizePx}x${iconSizePx}px, 색상: ${Integer.toHexString(color)}")
            return bitmap
        } catch (e: Exception) {
            Log.e(TAG, "버스 아이콘 생성 실패: ${e.message}")
            return null
        }
    }



    
    private fun buildTrackingSmallRemoteViews(
        title: String,
        contentText: String
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.notification_tracking_small)
        views.setTextViewText(R.id.notification_title, title)
        views.setTextViewText(R.id.notification_content, contentText)
        return views
    }

    private fun buildTrackingRemoteViews(
        title: String,
        contentText: String,
        trackingInfo: com.example.daegu_bus_app.services.TrackingInfo?
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.notification_tracking)
        views.setTextViewText(R.id.notification_title, title)
        views.setTextViewText(R.id.notification_content, contentText)

        val remainingMinutes = trackingInfo?.lastBusInfo?.getRemainingMinutes() ?: -1
        val maxMinutes = 30
        val progressPercent = if (remainingMinutes <= 0) {
            100
        } else {
            val clamped = remainingMinutes.coerceIn(0, maxMinutes)
            ((maxMinutes - clamped) * 100 / maxMinutes)
        }

        views.setProgressBar(R.id.notification_progress, 100, progressPercent, false)

        val screenWidthPx = context.resources.displayMetrics.widthPixels
        val horizontalPaddingPx = context.resources.getDimensionPixelSize(R.dimen.notification_padding_horizontal)
        val trackWidthPx = (screenWidthPx - (horizontalPaddingPx * 2)).coerceAtLeast(0)
        val iconSizePx = context.resources.getDimensionPixelSize(R.dimen.notification_bus_icon_size)
        val maxOffset = (trackWidthPx - iconSizePx).coerceAtLeast(0)
        val offset = (maxOffset * progressPercent / 100.0).toInt().coerceIn(0, maxOffset)
        views.setFloat(R.id.notification_bus_icon, "setTranslationX", offset.toFloat())

        return views
    }

private fun isVibrationEnabled(): Boolean {
        return try {
            val prefs = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            prefs.getBoolean("flutter.vibrate", true)
        } catch (e: Exception) {
            Log.e(TAG, "Error reading vibration setting: ${e.message}")
            true
        }
    }

    private fun vibrateOnce() {
        try {
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                vibrator.vibrate(VibrationEffect.createOneShot(200, VibrationEffect.DEFAULT_AMPLITUDE))
            } else {
                @Suppress("DEPRECATION")
                vibrator.vibrate(200)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error triggering vibration: ${e.message}")
        }
    }

    private fun createPendingIntent(): PendingIntent? {
        val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        return if (openAppIntent != null) {
            PendingIntent.getActivity(
                context, 0, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
        } else null
    }

    private fun createStopPendingIntent(): PendingIntent {
        Log.d(TAG, "🔔 createStopPendingIntent 호출됨")
        val stopAllIntent = Intent(context, BusAlertService::class.java).apply {
            action = ACTION_STOP_TRACKING // 통일된 ACTION 사용
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        Log.d(TAG, "🔔 Stop Intent 생성: action=${stopAllIntent.action}, flags=${stopAllIntent.flags}")
        
        val pendingIntent = PendingIntent.getService(
            context, 
            99999, // 더 고유한 requestCode 사용
            stopAllIntent, 
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        Log.d(TAG, "🔔 Stop PendingIntent 생성 완료: requestCode=99999")
        return pendingIntent
    }

    private fun createStopAutoAlarmPendingIntent(): PendingIntent {
        val stopAutoAlarmIntent = Intent(context, BusAlertService::class.java).apply {
            action = BusAlertService.ACTION_STOP_AUTO_ALARM
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        return PendingIntent.getService(
            context, 9998, stopAutoAlarmIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

     // --- Alert Notification ---

     fun sendAlertNotification(routeId: String, busNo: String, stationName: String, isAutoAlarm: Boolean = false) {
        val notificationId = ALERT_NOTIFICATION_ID_BASE + routeId.hashCode()
        val contentText = "$busNo 번 버스가 $stationName 정류장에 곧 도착합니다."
        Log.d(TAG, "Sending ALERT notification: $contentText (ID: $notificationId)")

        val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = if (openAppIntent != null) PendingIntent.getActivity(
            context, notificationId, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        ) else null

        val cancelPendingIntent = createCancelBroadcastPendingIntent(routeId, busNo, stationName, notificationId, isAutoAlarm)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID_ALERT)
            .setContentTitle("버스 도착 임박!")
            .setContentText(contentText)
            .setSmallIcon(R.drawable.ic_bus_notification)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
             .setColor(ContextCompat.getColor(context, R.color.alert_color)) // Use context
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .addAction(R.drawable.ic_cancel, "종료", cancelPendingIntent)
            .setDefaults(NotificationCompat.DEFAULT_ALL)

        val notificationManager = NotificationManagerCompat.from(context)
        notificationManager.notify(notificationId, builder.build())
    }

     // --- Error Notification ---

     fun sendErrorNotification(routeId: String?, busNo: String?, stationName: String?, message: String) {
        val notificationId = ALERT_NOTIFICATION_ID_BASE + (routeId ?: "error").hashCode() + 1
        val title = "버스 추적 오류"
        var contentText = message
        if (!busNo.isNullOrEmpty() && !stationName.isNullOrEmpty()) {
             contentText = "$busNo ($stationName): $message"
        }
         Log.w(TAG, "Sending ERROR notification: $contentText (ID: $notificationId)")

         val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
         val pendingIntent = if (openAppIntent != null) PendingIntent.getActivity(
             context, notificationId, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
         ) else null

         val builder = NotificationCompat.Builder(context, CHANNEL_ID_ERROR)
             .setContentTitle(title)
             .setContentText(contentText)
             .setSmallIcon(R.drawable.ic_bus_notification) // Consider an error icon
             .setPriority(NotificationCompat.PRIORITY_DEFAULT)
             .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
             .setContentIntent(pendingIntent)
             .setAutoCancel(true)

         val notificationManager = NotificationManagerCompat.from(context)
         notificationManager.notify(notificationId, builder.build())
     }

     // --- Notification Cancellation ---

     fun cancelNotification(id: Int) {
         Log.d(TAG, "Request to cancel notification ID: $id")
         try {
             // 1. 강화된 즉시 취소 (이중 보장)
             try {
                 val systemNotificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                 val notificationManagerCompat = NotificationManagerCompat.from(context)
                 
                 // 개별 ID 강제 취소 (여러 번 시도)
                 for (attempt in 1..3) {
                     systemNotificationManager.cancel(id)
                     notificationManagerCompat.cancel(id)
                     if (attempt < 3) {
                         Thread.sleep(50) // 짧은 지연 후 재시도
                     }
                 }
                 
                 // 로그에서 보인 문제 ID들도 함께 취소
                 val problematicIds = listOf(916311223, 954225315, 1, 10000, id)
                 for (problematicId in problematicIds) {
                     systemNotificationManager.cancel(problematicId)
                     notificationManagerCompat.cancel(problematicId)
                 }
                 
                 Log.d(TAG, "✅ 강화된 알림 취소 완료: ID=$id (+ ${problematicIds.size}개 추가 ID)")
             } catch (e: Exception) {
                 Log.e(TAG, "❌ 강화된 알림 취소 오류: ${e.message}")
             }

             // 진행 중인 추적 알림인 경우 BusAlertService에도 알림
             if (id == ONGOING_NOTIFICATION_ID) {
                 // 2. 모든 알림 강제 취소 (ONGOING_NOTIFICATION_ID인 경우)
                 try {
                     val systemNotificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                     systemNotificationManager.cancelAll()
                     Log.d(TAG, "✅ 모든 알림 강제 취소 완료 (ONGOING)")
                 } catch (e: Exception) {
                     Log.e(TAG, "❌ 모든 알림 강제 취소 오류: ${e.message}")
                 }

                 // 2. 서비스에 중지 요청 전송
                 val stopIntent = Intent(context, BusAlertService::class.java).apply {
                     action = BusAlertService.ACTION_STOP_TRACKING
                     flags = Intent.FLAG_ACTIVITY_NEW_TASK
                 }
                 if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                     context.startForegroundService(stopIntent)
                 } else {
                     context.startService(stopIntent)
                 }
                 Log.d(TAG, "Sent stop tracking request to BusAlertService")

                 // 3. 전체 취소 이벤트 브로드캐스트
                 val allCancelIntent = Intent("com.example.daegu_bus_app.ALL_TRACKING_CANCELLED")
                 context.sendBroadcast(allCancelIntent)
                 Log.d(TAG, "Sent ALL_TRACKING_CANCELLED broadcast")

                 // 4. Flutter 메서드 채널을 통해 직접 이벤트 전송 시도 (개선된 방법)
                 try {
                     MainActivity.sendFlutterEvent("onAllAlarmsCanceled", null)
                     Log.d(TAG, "✅ Flutter 메서드 채널로 모든 알람 취소 이벤트 전송 완료 (NotificationHandler)")
                 } catch (e: Exception) {
                     Log.e(TAG, "❌ Flutter 메서드 채널 전송 오류 (NotificationHandler): ${e.message}")
                 }

                 // 5. 지연된 추가 노티피케이션 취소 (백업)
                 Handler(Looper.getMainLooper()).postDelayed({
                     try {
                         val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                         notificationManager.cancel(ONGOING_NOTIFICATION_ID)
                         notificationManager.cancelAll()
                         Log.d(TAG, "지연된 노티피케이션 취소 완료")
                     } catch (e: Exception) {
                         Log.e(TAG, "지연된 노티피케이션 취소 오류: ${e.message}")
                     }
                 }, 500)
             }
         } catch (e: Exception) {
             Log.e(TAG, "Error cancelling notification ID $id: ${e.message}", e)
         }
     }

     fun cancelOngoingTrackingNotification() {
         Log.d(TAG, "Canceling ongoing tracking notification ID: $ONGOING_NOTIFICATION_ID")
         try {
             // 1. 즉시 노티피케이션 취소 (최우선)
             try {
                 val systemNotificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                 systemNotificationManager.cancel(ONGOING_NOTIFICATION_ID)
                 systemNotificationManager.cancelAll()
                 Log.d(TAG, "즉시 노티피케이션 취소 완료 (cancelOngoingTrackingNotification)")
             } catch (e: Exception) {
                 Log.e(TAG, "즉시 노티피케이션 취소 오류: ${e.message}")
             }

             // 2. NotificationManagerCompat으로도 취소
             try {
                 val notificationManager = NotificationManagerCompat.from(context)
                 notificationManager.cancel(ONGOING_NOTIFICATION_ID)
                 notificationManager.cancelAll()
                 Log.d(TAG, "NotificationManagerCompat으로 노티피케이션 취소 완료")
             } catch (e: Exception) {
                 Log.e(TAG, "NotificationManagerCompat 취소 오류: ${e.message}")
             }

             // 3. BusAlertService에 중지 요청
             val stopIntent = Intent(context, BusAlertService::class.java).apply {
                 action = BusAlertService.ACTION_STOP_TRACKING
                 flags = Intent.FLAG_ACTIVITY_NEW_TASK
             }
             if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                 context.startForegroundService(stopIntent)
             } else {
                 context.startService(stopIntent)
             }
             Log.d(TAG, "Sent stop tracking request to BusAlertService")

             // 4. 전체 취소 이벤트 브로드캐스트 (즉시)
             val allCancelIntent = Intent("com.example.daegu_bus_app.ALL_TRACKING_CANCELLED")
             context.sendBroadcast(allCancelIntent)
             Log.d(TAG, "Sent ALL_TRACKING_CANCELLED broadcast")

             // 5. Flutter 메서드 채널을 통해 직접 이벤트 전송 시도 (개선된 방법)
             try {
                 MainActivity.sendFlutterEvent("onAllAlarmsCanceled", null)
                 Log.d(TAG, "✅ Flutter 메서드 채널로 모든 알람 취소 이벤트 전송 완료 (cancelOngoingTrackingNotification)")
             } catch (e: Exception) {
                 Log.e(TAG, "❌ Flutter 메서드 채널 전송 오류 (cancelOngoingTrackingNotification): ${e.message}")
             }

             // 6. 지연된 추가 노티피케이션 취소 (백업)
             Handler(Looper.getMainLooper()).postDelayed({
                 try {
                     val systemNotificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                     systemNotificationManager.cancel(ONGOING_NOTIFICATION_ID)
                     systemNotificationManager.cancelAll()
                     Log.d(TAG, "지연된 노티피케이션 취소 완료 (cancelOngoingTrackingNotification)")
                 } catch (e: Exception) {
                     Log.e(TAG, "지연된 노티피케이션 취소 오류: ${e.message}")
                 }

                 // 지연된 브로드캐스트도 전송
                 context.sendBroadcast(allCancelIntent)
                 Log.d(TAG, "Sent delayed ALL_TRACKING_CANCELLED broadcast")
             }, 500)
         } catch (e: Exception) {
             Log.e(TAG, "Error cancelling ongoing tracking notification: ${e.message}", e)
         }
     }

     fun cancelBusTrackingNotification(routeId: String, busNo: String, stationName: String, isAutoAlarm: Boolean) {
         Log.d(TAG, "Request to cancel bus tracking notification: Route=$routeId, Bus=$busNo, Station=$stationName")
         try {
             // 특정 노선 추적 알림 취소
             val systemNotificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
             
             // ONGOING_NOTIFICATION_ID 취소
             systemNotificationManager.cancel(ONGOING_NOTIFICATION_ID)
             
             // NotificationManagerCompat으로도 취소
             val notificationManager = NotificationManagerCompat.from(context)
             notificationManager.cancel(ONGOING_NOTIFICATION_ID)
             
             Log.d(TAG, "Bus tracking notification cancelled: Route=$routeId, Bus=$busNo")
         } catch (e: Exception) {
             Log.e(TAG, "Error cancelling bus tracking notification: ${e.message}")
         }
     }

     fun cancelAllNotifications() {
         Log.d(TAG, "Request to cancel ALL notifications")
         try {
             // 1. 즉시 모든 노티피케이션 취소 (최우선) - 개별 ID까지 강제 취소
             try {
                 val systemNotificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                 
                 // 개별 알림 ID들 강제 취소 (여러 번 시도)
                 for (attempt in 1..3) {
                     systemNotificationManager.cancel(ONGOING_NOTIFICATION_ID)
                     systemNotificationManager.cancel(ARRIVING_SOON_NOTIFICATION_ID)
                     
                     // 동적으로 생성된 알림 ID들도 취소 (범위 기반)
                     for (i in ALERT_NOTIFICATION_ID_BASE..(ALERT_NOTIFICATION_ID_BASE + 1000)) {
                         systemNotificationManager.cancel(i)
                     }
                     
                     // 전체 취소
                     systemNotificationManager.cancelAll()
                     
                     if (attempt < 3) {
                         Thread.sleep(100) // 짧은 지연 후 재시도
                     }
                 }
                 
                 Log.d(TAG, "즉시 모든 노티피케이션 취소 완료 (cancelAllNotifications)")
             } catch (e: Exception) {
                 Log.e(TAG, "즉시 모든 노티피케이션 취소 오류: ${e.message}")
             }

             // 2. NotificationManagerCompat으로도 취소 (이중 보장)
             try {
                 val notificationManager = NotificationManagerCompat.from(context)
                 
                 // 개별 ID 취소 후 전체 취소
                 notificationManager.cancel(ONGOING_NOTIFICATION_ID)
                 notificationManager.cancel(ARRIVING_SOON_NOTIFICATION_ID)
                 
                 // 동적 ID 범위 취소
                 for (i in ALERT_NOTIFICATION_ID_BASE..(ALERT_NOTIFICATION_ID_BASE + 1000)) {
                     notificationManager.cancel(i)
                 }
                 
                 notificationManager.cancelAll()
                 Log.d(TAG, "NotificationManagerCompat으로 모든 노티피케이션 취소 완료")
             } catch (e: Exception) {
                 Log.e(TAG, "NotificationManagerCompat 모든 취소 오류: ${e.message}")
             }

             // 3. BusAlertService에 중지 요청
             val stopIntent = Intent(context, BusAlertService::class.java).apply {
                 action = BusAlertService.ACTION_STOP_TRACKING
             }
             if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                 context.startForegroundService(stopIntent)
             } else {
                 context.startService(stopIntent)
             }
             Log.d(TAG, "Sent stop tracking request to BusAlertService")

             // 4. 전체 취소 이벤트 브로드캐스트
             val allCancelIntent = Intent("com.example.daegu_bus_app.ALL_TRACKING_CANCELLED")
             context.sendBroadcast(allCancelIntent)
             Log.d(TAG, "Sent ALL_TRACKING_CANCELLED broadcast")

             // 5. Flutter 메서드 채널을 통해 직접 이벤트 전송 시도 (개선된 방법)
             try {
                 MainActivity.sendFlutterEvent("onAllAlarmsCanceled", null)
                 Log.d(TAG, "✅ Flutter 메서드 채널로 모든 알람 취소 이벤트 전송 완료 (cancelAllNotifications)")
             } catch (e: Exception) {
                 Log.e(TAG, "❌ Flutter 메서드 채널 전송 오류 (cancelAllNotifications): ${e.message}")
             }

             // 6. 지연된 추가 노티피케이션 취소 (백업) - 더 강력하게
             Handler(Looper.getMainLooper()).postDelayed({
                 try {
                     val systemNotificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                     
                     // 개별 ID들 다시 한번 강제 취소
                     systemNotificationManager.cancel(ONGOING_NOTIFICATION_ID)
                     systemNotificationManager.cancel(ARRIVING_SOON_NOTIFICATION_ID)
                     
                     // 범위 기반 재취소
                     for (i in ALERT_NOTIFICATION_ID_BASE..(ALERT_NOTIFICATION_ID_BASE + 1000)) {
                         systemNotificationManager.cancel(i)
                     }
                     
                     systemNotificationManager.cancelAll()
                     Log.d(TAG, "지연된 모든 노티피케이션 취소 완료 (cancelAllNotifications)")
                 } catch (e: Exception) {
                     Log.e(TAG, "지연된 모든 노티피케이션 취소 오류: ${e.message}")
                 }
                 
                 // NotificationManagerCompat로도 다시 한번 취소
                 try {
                     val notificationManager = NotificationManagerCompat.from(context)
                     notificationManager.cancelAll()
                     Log.d(TAG, "지연된 NotificationManagerCompat 취소 완료")
                 } catch (e: Exception) {
                     Log.e(TAG, "지연된 NotificationManagerCompat 취소 오류: ${e.message}")
                 }
             }, 500)

             // 7. 추가 지연 취소 (2초 후 최종 정리)
             Handler(Looper.getMainLooper()).postDelayed({
                 try {
                     val systemNotificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                     systemNotificationManager.cancelAll()
                     Log.d(TAG, "최종 지연된 모든 노티피케이션 취소 완료")
                 } catch (e: Exception) {
                     Log.e(TAG, "최종 지연된 노티피케이션 취소 오류: ${e.message}")
                 }
             }, 2000)

         } catch (e: Exception) {
             Log.e(TAG, "Error cancelling all notifications: ${e.message}", e)
         }
     }

     // --- Regular Notification ---

     fun buildNotification(
         id: Int,
         busNo: String,
         stationName: String,
         remainingMinutes: Int,
         currentStation: String?,
         routeId: String?,
         isAutoAlarm: Boolean = false // 자동알람 여부 추가
     ): Notification {
         val title = if (remainingMinutes <= 0) {
             "${busNo}번 버스 도착" // 더 간결하게
         } else {
             "${busNo}번 버스 알람"
         }
         val contentText = if (remainingMinutes <= 0) {
             "${busNo}번 버스가 ${stationName}에 곧 도착합니다."
         } else {
             "${busNo}번 버스가 약 ${remainingMinutes}분 후 도착 예정입니다."
         }
         val subText = if (currentStation != null && currentStation.isNotEmpty()) "현재 위치: $currentStation" else null

         // 앱 실행 Intent
         val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
             flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
         }
         val pendingIntent = if (openAppIntent != null) PendingIntent.getActivity(
             context, id, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
         ) else null

         val cancelPendingIntent = createCancelBroadcastPendingIntent(routeId, busNo, stationName, id, isAutoAlarm)

         val builder = NotificationCompat.Builder(context, CHANNEL_ID_ALERT) // 도착 알림 채널 사용
             .setContentTitle(title)
             .setContentText(contentText)
             .setSmallIcon(R.mipmap.ic_launcher) // 앱 아이콘 사용
             .setPriority(NotificationCompat.PRIORITY_HIGH)
             .setCategory(NotificationCompat.CATEGORY_ALARM)
             .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
             .setColor(ContextCompat.getColor(context, R.color.alert_color))
             .setAutoCancel(true)
             .setDefaults(NotificationCompat.DEFAULT_ALL) // 소리, 진동 등 기본 설정
             .addAction(R.drawable.ic_cancel, "종료", cancelPendingIntent)

         if (subText != null) {
             builder.setSubText(subText)
         }
         if (pendingIntent != null) {
             builder.setContentIntent(pendingIntent)
         }

         Log.d(TAG, "✅ 개별 알림 생성: ID=$id, Bus=$busNo, Station=$stationName, Route=$routeId")
         return builder.build()
     }

     // --- Arriving Soon Notification ---

     fun buildArrivingSoonNotification(
         busNo: String,
         stationName: String,
         currentStation: String?
     ): Notification {
         val title = "Bus Arriving Soon!"
         val contentText = "Bus $busNo is arriving soon at $stationName station."
         val subText = currentStation?.let { "Current location: $it" } ?: ""

         Log.d(TAG, "Building arriving soon notification: $contentText (ID: $ARRIVING_SOON_NOTIFICATION_ID)")

         val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
             flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
         }
         val pendingIntent = if (openAppIntent != null) PendingIntent.getActivity(
             context, ARRIVING_SOON_NOTIFICATION_ID, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
         ) else null

         val cancelPendingIntent = createCancelBroadcastPendingIntent(null, busNo, stationName, ARRIVING_SOON_NOTIFICATION_ID, false)

         val builder = NotificationCompat.Builder(context, CHANNEL_ID_ALERT)
             .setContentTitle(title)
             .setContentText(contentText)
             .setSubText(subText)
             .setSmallIcon(R.drawable.ic_bus_notification)
             .setPriority(NotificationCompat.PRIORITY_HIGH)
             .setCategory(NotificationCompat.CATEGORY_ALARM)
             .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
             .setColor(ContextCompat.getColor(context, R.color.alert_color))
             .setContentIntent(pendingIntent)
             .setAutoCancel(true)
             .addAction(R.drawable.ic_cancel, "종료", cancelPendingIntent)
             .setDefaults(NotificationCompat.DEFAULT_ALL)

         return builder.build()
     }
}
