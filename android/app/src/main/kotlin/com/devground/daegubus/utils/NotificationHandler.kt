package com.devground.daegubus.utils

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
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
import com.devground.daegubus.services.BusAlertService
import com.devground.daegubus.MainActivity
import com.devground.daegubus.R
import android.content.BroadcastReceiver
import android.content.IntentFilter
import android.net.Uri
import android.provider.Settings

class NotificationHandler(private val context: Context) {

    companion object {
        private const val TAG = "NotificationHandler"

        // Notification Channel IDs
        private const val CHANNEL_ID_ONGOING_LEGACY = "bus_tracking_ongoing"
        // v3: IMPORTANCE_HIGH + setShowBadge(false) 로 Live Update 조건 충족
        private const val CHANNEL_ID_ONGOING_LIVE_UPDATE = "bus_live_update_v3"
        private const val CHANNEL_ID_ONGOING_OLD_LIVE_UPDATE = "bus_live_update"
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
        const val ACTION_STOP_TRACKING = "com.devground.daegubus.action.STOP_TRACKING"
        const val ACTION_STOP_SPECIFIC_ROUTE_TRACKING = "com.devground.daegubus.action.STOP_SPECIFIC_ROUTE_TRACKING"
        const val ACTION_CANCEL_NOTIFICATION = "com.devground.daegubus.action.CANCEL_NOTIFICATION"

        private val lastRemainingMinutesByRoute = mutableMapOf<String, Int>()

        fun getOngoingChannelId(): String {
            return if (Build.VERSION.SDK_INT >= 36) {
                CHANNEL_ID_ONGOING_LIVE_UPDATE
            } else {
                CHANNEL_ID_ONGOING_LEGACY
            }
        }
    }

     // --- Notification Channel Creation ---

    fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                val ongoingChannelId = getOngoingChannelId()

                if (Build.VERSION.SDK_INT >= 36) {
                    cleanupLegacyOngoingChannels(notificationManager, ongoingChannelId)
                }

                // Ongoing Channel — Live Update 요건: IMPORTANCE_HIGH, setShowBadge(false), VISIBILITY_PUBLIC
                val ongoingChannel = NotificationChannel(
                    ongoingChannelId,
                    CHANNEL_NAME_ONGOING,
                    // 문서 체크리스트: "채널 중요도 HIGH" — Live Update 상태칩 표시를 위해 HIGH 필요
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = if (Build.VERSION.SDK_INT >= 36) {
                        "실시간 버스 도착 정보 Live Update"
                    } else {
                        "실시간 버스 추적 상태 알림"
                    }
                    // 업데이트마다 소리/진동 방지 (HIGH이지만 silent)
                    setSound(null, null)
                    enableVibration(false)
                    enableLights(false)
                    // Live Update 조건: 뱃지 비활성, 잠금화면 공개
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    setBypassDnd(false)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        setAllowBubbles(false)
                    }
                }

                // Alert Channel
                val alertChannel = NotificationChannel(
                    CHANNEL_ID_ALERT,
                    CHANNEL_NAME_ALERT,
                    NotificationManager.IMPORTANCE_MAX
                ).apply {
                    description = "버스 도착 임박 시 알림"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 500, 200, 500, 200, 500)
                    enableLights(true)
                    setShowBadge(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                    setBypassDnd(true)
                }

                // Error Channel
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
                Log.d(TAG, "Notification channels created. ongoingChannelId=$ongoingChannelId")
            } catch (e: Exception) {
                Log.e(TAG, "Error creating notification channels: ${e.message}", e)
            }
        }
    }

    private fun cleanupLegacyOngoingChannels(
        notificationManager: NotificationManager,
        keepChannelId: String
    ) {
        listOf(CHANNEL_ID_ONGOING_LEGACY, CHANNEL_ID_ONGOING_OLD_LIVE_UPDATE, "bus_live_update_v2")
            .filter { it != keepChannelId }
            .forEach { channelId ->
                try {
                    val legacyChannel = notificationManager.getNotificationChannel(channelId) ?: return@forEach
                    notificationManager.deleteNotificationChannel(channelId)
                    Log.d(TAG, "🧹 Deleted legacy channel: $channelId")
                } catch (e: Exception) { /* ignore */ }
            }
    }

    init {
        try {
            val filter = IntentFilter(BusAlertService.ACTION_STOP_TRACKING)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(NotificationCancelReceiver(), filter, Context.RECEIVER_NOT_EXPORTED)
            } else {
                context.registerReceiver(NotificationCancelReceiver(), filter)
            }
        } catch (e: Exception) {
            Log.e(TAG, "NotificationCancelReceiver registration error: ${e.message}")
        }
    }

    class NotificationCancelReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val routeId = intent.getStringExtra("routeId") ?: return
            val busNo = intent.getStringExtra("busNo") ?: return
            val stationName = intent.getStringExtra("stationName") ?: return
            val stopIntent = Intent(context, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_STOP_TRACKING
                putExtra("routeId", routeId)
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
            }
            context.startService(stopIntent)
        }
    }

    private fun createCancelBroadcastPendingIntent(
        routeId: String?,
        busNo: String?,
        stationName: String?,
        notificationId: Int,
        isAutoAlarm: Boolean = false
    ): PendingIntent {
        val cancelIntent = Intent(context, BusAlertService::class.java).apply {
            action = if (isAutoAlarm) BusAlertService.ACTION_STOP_AUTO_ALARM else BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
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

    fun buildOngoingNotification(activeTrackings: Map<String, com.devground.daegubus.services.TrackingInfo>): Notification {
        val startTime = System.currentTimeMillis()
        var shouldVibrateOnChange = false
        val ongoingChannelId = getOngoingChannelId()
        
        activeTrackings.forEach { (routeId, info) ->
            val busInfo = info.lastBusInfo
            if (busInfo != null) {
                val currentMinutes = busInfo.getRemainingMinutes()
                val prevMinutes = lastRemainingMinutesByRoute[routeId]
                if (prevMinutes != null && currentMinutes >= 0 && prevMinutes >= 0 && currentMinutes != prevMinutes) {
                    shouldVibrateOnChange = true
                }
                lastRemainingMinutesByRoute[routeId] = currentMinutes
            }
        }

        val currentTime = SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date())
        var title = "버스 알람 추적 중 ($currentTime)"
        var contentText = "추적 중인 버스: ${activeTrackings.size}개"

        val inboxStyle = NotificationCompat.InboxStyle().setBigContentTitle(title)

        if (activeTrackings.isNotEmpty()) {
            activeTrackings.values.take(5).forEach { trackingInfo ->
                val busInfo = trackingInfo.lastBusInfo
                val busNo = trackingInfo.busNo
                val stationNameShort = trackingInfo.stationName.take(10) + if (trackingInfo.stationName.length > 10) "..." else ""
                val timeStr = busInfo?.getFormattedTime() ?: "정보 없음"
                val locationInfo = if (!busInfo?.currentStation.isNullOrEmpty()) " [현재: ${busInfo?.currentStation}]" else ""
                val infoLine = "$busNo (${stationNameShort}): $timeStr$locationInfo"
                inboxStyle.addLine(infoLine)
            }
            if (activeTrackings.size > 5) inboxStyle.setSummaryText("+${activeTrackings.size - 5}개 더 추적 중")

            val firstTracking = activeTrackings.values.firstOrNull()
            if (firstTracking != null) {
                val busInfo = firstTracking.lastBusInfo
                val busNo = firstTracking.busNo
                val timeStr = busInfo?.getFormattedTime() ?: "정보 없음"
                val locationInfo = if (!busInfo?.currentStation.isNullOrEmpty()) " [${busInfo?.currentStation}]" else ""
                title = buildTrackingHeadline(busNo, timeStr)
                contentText = buildTrackingContentText(firstTracking.stationName, timeStr, locationInfo, activeTrackings.size - 1)
                inboxStyle.setBigContentTitle(title)
            }
        }

        val firstTracking = activeTrackings.values.firstOrNull()
        val defaultContentIntent = createPendingIntent()

        // Android 16+ (API 36) Live Updates 지원: 실기기에서 검증된 텍스트 상태칩 경로 사용
        if (Build.VERSION.SDK_INT >= 36) {
            val busTypeColor = when (firstTracking?.routeTCd) {
                "1" -> 0xFFDC2626.toInt()
                "2" -> 0xFFF59E0B.toInt()
                "3" -> 0xFF2563EB.toInt()
                "4" -> 0xFF10B981.toInt()
                else -> ContextCompat.getColor(context, R.color.tracking_color)
            }

            // 네이티브 빌더 생성 (API 26+)
            val nativeBuilder = Notification.Builder(context, ongoingChannelId)
                .setContentTitle(title)
                .setContentText(contentText)
                .setSmallIcon(R.drawable.ic_bus_notification)
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_PROGRESS)
                .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setColor(busTypeColor)
                // Live Update 자격 조건: colorized=true 는 승격/상태칩 표시를 방해할 수 있으므로 사용하지 않음
                .setOnlyAlertOnce(true)

            defaultContentIntent?.let { nativeBuilder.setContentIntent(it) }
            requestPromotedOngoing(nativeBuilder)

            if (firstTracking != null) {
                val busInfo        = firstTracking.lastBusInfo
                val remainingMin   = busInfo?.getRemainingMinutes() ?: 0
                val stopsInt       = busInfo?.remainingStops?.filter { it.isDigit() }?.toIntOrNull() ?: 0
                val currentStation = busInfo?.currentStation?.takeIf { it.isNotBlank() && it != "정보 없음" }
                val extraCount     = activeTrackings.size - 1

                // ── 레퍼런스 구조: 제목 / 본문 / 상태칩 ────────────────────────────
                val liveTitle = buildLiveTitle(firstTracking.busNo, stopsInt, remainingMin, busInfo?.estimatedTime)
                val liveBody  = buildLiveBody(firstTracking.stationName, currentStation, stopsInt, remainingMin, extraCount)
                val chipText  = buildChipText(stopsInt, remainingMin, busInfo?.estimatedTime)

                nativeBuilder.setContentTitle(liveTitle)
                nativeBuilder.setContentText(liveBody)
                // subText: 하차 예정 정류장명
                nativeBuilder.setSubText(firstTracking.stationName.take(14))

                // 상태칩 — "7개소전" 형식 (max 7자)
                @Suppress("NewApi")
                nativeBuilder.setShortCriticalText(chipText)
                Log.d(TAG, "🎯 상태칩: '$chipText'  제목: '$liveTitle'")

                // ── 버스 아이콘 ───────────────────────────────────────────────────
                createColoredBusIcon(context, busTypeColor, firstTracking.busNo)?.let {
                    nativeBuilder.setLargeIcon(android.graphics.drawable.Icon.createWithBitmap(it))
                }

                // ── ProgressStyle (레퍼런스 buildPlatformProgressStyle 구조 적용) ─
                // progress = 정거장 수 기반 동적 계산 (없으면 분 기반 fallback)
                val progress      = calcProgress(stopsInt, remainingMin)
                val remaining     = (100 - progress).coerceIn(0, 100)

                @Suppress("NewApi")
                try {
                    val progressStyle = Notification.ProgressStyle()
                        .setProgress(progress)
                        .setProgressTrackerIcon(
                            android.graphics.drawable.Icon.createWithResource(context, R.drawable.ic_bus_tracker)
                        )
                    try { progressStyle.setStyledByProgress(true) } catch (_: Exception) { }

                    // 세그먼트: 이동완료(버스색) + 잔여구간(회색)
                    val segments = mutableListOf<Notification.ProgressStyle.Segment>()
                    if (progress > 0)   segments.add(Notification.ProgressStyle.Segment(progress).setColor(busTypeColor))
                    if (remaining > 0)  segments.add(Notification.ProgressStyle.Segment(remaining).setColor(0xFFE0E0E0.toInt()))
                    if (segments.isNotEmpty()) progressStyle.setProgressSegments(segments)

                    // 포인트: 출발(초록 ●) / 도착(빨강 ●)
                    // 유효 범위 1~99 (0/100은 "Dropped the point" 경고 후 무시됨)
                    progressStyle.setProgressPoints(listOf(
                        Notification.ProgressStyle.Point(1).setColor(0xFF4CAF50.toInt()),
                        Notification.ProgressStyle.Point(99).setColor(0xFFFF5722.toInt())
                    ))
                    nativeBuilder.setStyle(progressStyle)
                    // 레퍼런스: ProgressStyle 설정 후 setProgress() 추가 호출 필수
                    nativeBuilder.setProgress(100, progress, false)
                } catch (e: Exception) {
                    Log.e(TAG, "ProgressStyle 설정 실패: ${e.message}")
                    nativeBuilder.setProgress(100, calcProgress(stopsInt, remainingMin), false)
                }
            }

            // 액션 추가
            nativeBuilder.addAction(Notification.Action.Builder(
                android.graphics.drawable.Icon.createWithResource(context, R.drawable.ic_stop_tracking),
                "추적 중지", createStopPendingIntent()).build())
            
            if (activeTrackings.values.any { it.isAutoAlarm }) {
                nativeBuilder.addAction(Notification.Action.Builder(
                    android.graphics.drawable.Icon.createWithResource(context, R.drawable.ic_cancel),
                    "중지", createStopAutoAlarmPendingIntent()).build())
            }

            val builtNotification = nativeBuilder.build()
            // FLAG_PROMOTED_ONGOING 수동 설정 필수 —
            // setRequestPromotedOngoing() 리플렉션이 삼성 One UI에서 실패하고
            // setExtras extras 경로만으로는 hasPromotableCharacteristics()가 false를 반환하기 때문
            @Suppress("NewApi")
            builtNotification.flags = builtNotification.flags or
                Notification.FLAG_ONGOING_EVENT or
                Notification.FLAG_NO_CLEAR or
                Notification.FLAG_FOREGROUND_SERVICE or
                Notification.FLAG_PROMOTED_ONGOING

            try {
                val hasPromotableMethod = builtNotification.javaClass.getMethod("hasPromotableCharacteristics")
                Log.d(TAG, "📋 hasPromotableCharacteristics: ${hasPromotableMethod.invoke(builtNotification)}")
            } catch (_: Exception) {}

            if (shouldVibrateOnChange && isVibrationEnabled()) vibrateOnce()
            return builtNotification
        }

        // Android 15 이하: NotificationCompat 활용
        val notificationBuilder = NotificationCompat.Builder(context, ongoingChannelId)
            .setContentTitle(title)
            .setContentText(contentText)
            .setSmallIcon(R.drawable.ic_bus_notification)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_PROGRESS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setStyle(inboxStyle)
            .setRequestPromotedOngoing(true)

        defaultContentIntent?.let { notificationBuilder.setContentIntent(it) }

        notificationBuilder.addAction(R.drawable.ic_stop_tracking, "추적 중지", createStopPendingIntent())
        if (activeTrackings.values.any { it.isAutoAlarm }) {
            notificationBuilder.addAction(R.drawable.ic_cancel, "중지", createStopAutoAlarmPendingIntent())
        }

        firstTracking?.lastBusInfo?.let { busInfo ->
            val stopsForChip = busInfo.remainingStops?.filter { it.isDigit() }?.toIntOrNull() ?: 0
            val statusText = buildChipText(stopsForChip, busInfo.getRemainingMinutes(), busInfo.estimatedTime)
            try { notificationBuilder.setShortCriticalText(statusText) } catch (_: Exception) { }
        }

        val builtNotification = notificationBuilder.build()
        builtNotification.flags = builtNotification.flags or Notification.FLAG_ONGOING_EVENT or Notification.FLAG_NO_CLEAR or Notification.FLAG_FOREGROUND_SERVICE
        
        if (Build.VERSION.SDK_INT >= 36) {
            try {
                Log.d(TAG, "📋 hasPromotable: ${builtNotification.hasPromotableCharacteristics()}")
                Log.d(TAG, "📋 canPostPromoted: ${(context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager).canPostPromotedNotifications()}")
            } catch (e: Exception) { /* ignore */ }
        }

        if (shouldVibrateOnChange && isVibrationEnabled()) vibrateOnce()
        return builtNotification
    }

    private fun requestPromotedOngoing(builder: Notification.Builder) {
        builder.setExtras(
            Bundle().apply {
                putBoolean("android.requestPromotedOngoing", true)
            },
        )

        try {
            builder.javaClass
                .getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType)
                .invoke(builder, true)
        } catch (_: ReflectiveOperationException) {
            // SDK 표면에 직접 노출되지 않은 환경에서도 extras 경로로 승격 요청을 유지한다.
        }
    }

    // ── Live Update 텍스트 빌더 (레퍼런스: live-update/DeliveryStatus.kt 참고) ──

    /**
     * 상태칩 텍스트 (max 7자)
     * "7개소전" / "곧도착" / "도착" / "2분후" 형식
     */
    private fun buildChipText(stopsInt: Int, remainingMinutes: Int, estimatedTime: String?): String {
        val normalized = estimatedTime?.trim().orEmpty().replace(" ", "")
        return when {
            normalized.contains("지나") || normalized.contains("종료") -> "지나감"
            stopsInt == 1                                               -> "곧도착"
            stopsInt > 1                                               -> "${stopsInt}개소전"
            remainingMinutes <= 0                                      -> "곧도착"
            remainingMinutes > 0                                       -> "${remainingMinutes}분후"
            else                                                       -> "???"
        }.take(7)
    }

    /**
     * Live Update 알림 제목
     * "623번 · 7개소전" / "623번 · 곧 도착" 형식
     */
    private fun buildLiveTitle(busNo: String, stopsInt: Int, remainingMinutes: Int, estimatedTime: String?): String {
        val normalized = estimatedTime?.trim().orEmpty().replace(" ", "")
        return when {
            normalized.contains("지나") || normalized.contains("종료") -> "${busNo}번 버스 지나감"
            stopsInt == 1                                               -> "${busNo}번 버스 · 곧 도착"
            stopsInt > 1                                               -> "${busNo}번 버스 · ${stopsInt}개소 전"
            remainingMinutes <= 0                                      -> "${busNo}번 버스 · 곧 도착"
            remainingMinutes > 0                                       -> "${busNo}번 버스 · ${remainingMinutes}분 후 도착"
            else                                                       -> "${busNo}번 도착 정보 없음"
        }
    }

    /**
     * Live Update 알림 본문
     * "현재: 명덕역 → 대구역 방향" 형식
     */
    private fun buildLiveBody(
        stationName: String,
        currentStation: String?,
        stopsInt: Int,
        remainingMinutes: Int,
        extraCount: Int
    ): String {
        val dest = if (stationName.length > 10) "${stationName.take(10)}.." else stationName
        val locationPart = if (!currentStation.isNullOrBlank() && currentStation != "정보 없음") {
            "현재: $currentStation"
        } else { "" }
        val stopsPart = when {
            stopsInt > 0          -> "$dest 방향 · ${stopsInt}정거장 남음"
            remainingMinutes > 0  -> "$dest 방향 · ${remainingMinutes}분"
            else                  -> dest
        }
        val extraLabel = if (extraCount > 0) " (+${extraCount})" else ""
        return if (locationPart.isNotEmpty()) "$locationPart → $stopsPart$extraLabel"
               else "$stopsPart$extraLabel"
    }

    /** 정거장 수 기반 progress 계산 (없으면 분 기반 fallback) */
    private fun calcProgress(stopsInt: Int, remainingMinutes: Int): Int {
        val MAX_STOPS = 30
        val MAX_MINUTES = 30
        return when {
            stopsInt > 0          -> ((MAX_STOPS - stopsInt.coerceIn(0, MAX_STOPS)) * 100 / MAX_STOPS)
            remainingMinutes > 0  -> ((MAX_MINUTES - remainingMinutes.coerceIn(0, MAX_MINUTES)) * 100 / MAX_MINUTES)
            else                  -> 100
        }.coerceIn(0, 100)
    }

    // ── 레거시 포맷 (API 15 이하 fallback용) ─────────────────────────────────

    private fun buildLiveUpdateStatusChipText(estimatedTime: String?, remainingMinutes: Int, remainingStops: Int): String {
        return buildChipText(remainingStops, remainingMinutes, estimatedTime)
    }

    private fun buildTrackingHeadline(busNo: String, timeText: String): String {
        return when (timeText) {
            "정보 없음" -> "${busNo}번 도착 정보 없음"
            "오류"     -> "${busNo}번 정보 확인 중"
            "운행종료"  -> "${busNo}번 운행종료"
            else        -> "${busNo}번 $timeText"
        }
    }

    private fun buildTrackingContentText(stationName: String, timeText: String, locationInfo: String, extraTrackingCount: Int): String {
        val stationLabel = if (stationName.length > 12) "${stationName.take(12)}.." else stationName
        val extraLabel = if (extraTrackingCount > 0) " +$extraTrackingCount" else ""
        return "$stationLabel · $timeText$locationInfo$extraLabel"
    }

    private fun createColoredBusIcon(context: Context, color: Int, busNo: String): android.graphics.Bitmap? {
        try {
            val density = context.resources.displayMetrics.density
            val iconSizePx = (48 * density).toInt()
            val drawable = ContextCompat.getDrawable(context, R.drawable.ic_bus_large) ?: ContextCompat.getDrawable(context, R.drawable.ic_bus_notification) ?: return null
            val bitmap = android.graphics.Bitmap.createBitmap(iconSizePx, iconSizePx, android.graphics.Bitmap.Config.ARGB_8888)
            val canvas = android.graphics.Canvas(bitmap)
            val paint = android.graphics.Paint().apply { this.color = color; isAntiAlias = true; style = android.graphics.Paint.Style.FILL }
            canvas.drawCircle(iconSizePx / 2f, iconSizePx / 2f, iconSizePx / 2f - 2 * density, paint)
            val iconPadding = (8 * density).toInt()
            drawable.setBounds(iconPadding, iconPadding, iconSizePx - iconPadding, iconSizePx - iconPadding)
            drawable.setTint(android.graphics.Color.WHITE)
            drawable.draw(canvas)
            return bitmap
        } catch (e: Exception) { return null }
    }

    private fun buildTrackingSmallRemoteViews(title: String, contentText: String): RemoteViews {
        return RemoteViews(context.packageName, R.layout.notification_tracking_small).apply {
            setTextViewText(R.id.notification_title, title)
            setTextViewText(R.id.notification_content, contentText)
        }
    }

    private fun buildTrackingRemoteViews(title: String, contentText: String, trackingInfo: com.devground.daegubus.services.TrackingInfo?): RemoteViews {
        return RemoteViews(context.packageName, R.layout.notification_tracking).apply {
            setTextViewText(R.id.notification_title, title)
            setTextViewText(R.id.notification_content, contentText)
            val remainingMinutes = trackingInfo?.lastBusInfo?.getRemainingMinutes() ?: -1
            val progressPercent = if (remainingMinutes <= 0) 100 else ((30 - remainingMinutes.coerceIn(0, 30)) * 100 / 30)
            setProgressBar(R.id.notification_progress, 100, progressPercent, false)
            val trackWidthPx = (context.resources.displayMetrics.widthPixels - (context.resources.getDimensionPixelSize(R.dimen.notification_padding_horizontal) * 2)).coerceAtLeast(0)
            val maxOffset = (trackWidthPx - context.resources.getDimensionPixelSize(R.dimen.notification_bus_icon_size)).coerceAtLeast(0)
            setFloat(R.id.notification_bus_icon, "setTranslationX", (maxOffset * progressPercent / 100.0).toFloat().coerceIn(0f, maxOffset.toFloat()))
        }
    }

    private fun isVibrationEnabled(): Boolean {
        return try { context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).getBoolean("flutter.vibrate", true) } catch (e: Exception) { true }
    }

    private fun vibrateOnce() {
        try {
            val vibrator = context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) vibrator.vibrate(VibrationEffect.createOneShot(200, VibrationEffect.DEFAULT_AMPLITUDE))
            else vibrator.vibrate(200)
        } catch (e: Exception) { /* ignore */ }
    }

    private fun createPendingIntent(): PendingIntent? {
        val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply { flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK }
        return if (openAppIntent != null) PendingIntent.getActivity(context, 0, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE) else null
    }

    private fun createStopPendingIntent(): PendingIntent {
        val stopAllIntent = Intent(context, BusAlertService::class.java).apply { action = ACTION_STOP_TRACKING; flags = Intent.FLAG_ACTIVITY_NEW_TASK }
        return PendingIntent.getService(context, 99999, stopAllIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun createStopAutoAlarmPendingIntent(): PendingIntent {
        val stopAutoAlarmIntent = Intent(context, BusAlertService::class.java).apply { action = BusAlertService.ACTION_STOP_AUTO_ALARM; flags = Intent.FLAG_ACTIVITY_NEW_TASK }
        return PendingIntent.getService(context, 9998, stopAutoAlarmIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

     fun sendAlertNotification(routeId: String, busNo: String, stationName: String, isAutoAlarm: Boolean = false) {
        val notificationId = ALERT_NOTIFICATION_ID_BASE + routeId.hashCode()
        val builder = NotificationCompat.Builder(context, CHANNEL_ID_ALERT)
            .setContentTitle("버스 도착 임박!")
            .setContentText("$busNo 번 버스가 $stationName 정류장에 곧 도착합니다.")
            .setSmallIcon(R.drawable.ic_bus_notification)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(ContextCompat.getColor(context, R.color.alert_color))
            .setContentIntent(createPendingIntent())
            .setAutoCancel(true)
            .addAction(R.drawable.ic_cancel, "종료", createCancelBroadcastPendingIntent(routeId, busNo, stationName, notificationId, isAutoAlarm))
            .setDefaults(NotificationCompat.DEFAULT_ALL)
        NotificationManagerCompat.from(context).notify(notificationId, builder.build())
    }

     fun sendErrorNotification(routeId: String?, busNo: String?, stationName: String?, message: String) {
        val notificationId = ALERT_NOTIFICATION_ID_BASE + (routeId ?: "error").hashCode() + 1
        val builder = NotificationCompat.Builder(context, CHANNEL_ID_ERROR)
            .setContentTitle("버스 추적 오류")
            .setContentText(if (!busNo.isNullOrEmpty() && !stationName.isNullOrEmpty()) "$busNo ($stationName): $message" else message)
            .setSmallIcon(R.drawable.ic_bus_notification)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setContentIntent(createPendingIntent())
            .setAutoCancel(true)
        NotificationManagerCompat.from(context).notify(notificationId, builder.build())
    }

     fun cancelNotification(id: Int) {
         try {
             val systemNotificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
             systemNotificationManager.cancel(id)
             NotificationManagerCompat.from(context).cancel(id)
             if (id == ONGOING_NOTIFICATION_ID) {
                 systemNotificationManager.cancelAll()
                 val stopIntent = Intent(context, BusAlertService::class.java).apply { action = BusAlertService.ACTION_STOP_TRACKING }
                 if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(stopIntent) else context.startService(stopIntent)
                 MainActivity.sendFlutterEvent("onAllAlarmsCanceled", null)
             }
         } catch (e: Exception) { Log.e(TAG, "Error cancelling notification ID $id: ${e.message}") }
     }

     fun cancelOngoingTrackingNotification() { cancelNotification(ONGOING_NOTIFICATION_ID) }
     fun cancelBusTrackingNotification(routeId: String, busNo: String, stationName: String, isAutoAlarm: Boolean) { cancelNotification(ONGOING_NOTIFICATION_ID) }
     fun cancelAllNotifications() {
         try {
             val systemNotificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
             systemNotificationManager.cancelAll()
             NotificationManagerCompat.from(context).cancelAll()
             val stopIntent = Intent(context, BusAlertService::class.java).apply { action = BusAlertService.ACTION_STOP_TRACKING }
             if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) context.startForegroundService(stopIntent) else context.startService(stopIntent)
             MainActivity.sendFlutterEvent("onAllAlarmsCanceled", null)
         } catch (e: Exception) { Log.e(TAG, "Error cancelling all notifications: ${e.message}") }
     }

     fun buildNotification(id: Int, busNo: String, stationName: String, remainingMinutes: Int, currentStation: String?, routeId: String?, isAutoAlarm: Boolean = false): Notification {
         val title = if (remainingMinutes <= 0) "${busNo}번 버스 도착" else "${busNo}번 버스 알람"
         val contentText = if (remainingMinutes <= 0) "${busNo}번 버스가 ${stationName}에 곧 도착합니다." else "${busNo}번 버스가 약 ${remainingMinutes}분 후 도착 예정입니다."
         val builder = NotificationCompat.Builder(context, CHANNEL_ID_ALERT)
             .setContentTitle(title)
             .setContentText(contentText)
             .setSmallIcon(R.mipmap.ic_launcher)
             .setPriority(NotificationCompat.PRIORITY_HIGH)
             .setCategory(NotificationCompat.CATEGORY_ALARM)
             .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
             .setColor(ContextCompat.getColor(context, R.color.alert_color))
             .setAutoCancel(true)
             .setDefaults(NotificationCompat.DEFAULT_ALL)
             .addAction(R.drawable.ic_cancel, "종료", createCancelBroadcastPendingIntent(routeId, busNo, stationName, id, isAutoAlarm))
         if (!currentStation.isNullOrEmpty()) builder.setSubText("현재 위치: $currentStation")
         createPendingIntent()?.let { builder.setContentIntent(it) }
         return builder.build()
     }

     fun buildArrivingSoonNotification(busNo: String, stationName: String, currentStation: String?): Notification {
         return NotificationCompat.Builder(context, CHANNEL_ID_ALERT)
             .setContentTitle("Bus Arriving Soon!")
             .setContentText("Bus $busNo is arriving soon at $stationName station.")
             .setSubText(currentStation ?: "")
             .setSmallIcon(R.drawable.ic_bus_notification)
             .setPriority(NotificationCompat.PRIORITY_HIGH)
             .setCategory(NotificationCompat.CATEGORY_ALARM)
             .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
             .setColor(ContextCompat.getColor(context, R.color.alert_color))
             .setContentIntent(createPendingIntent())
             .setAutoCancel(true)
             .addAction(R.drawable.ic_cancel, "종료", createCancelBroadcastPendingIntent(null, busNo, stationName, ARRIVING_SOON_NOTIFICATION_ID, false))
             .setDefaults(NotificationCompat.DEFAULT_ALL)
             .build()
     }
}
