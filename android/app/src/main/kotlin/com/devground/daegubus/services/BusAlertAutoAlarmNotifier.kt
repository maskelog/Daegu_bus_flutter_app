package com.devground.daegubus.services

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.devground.daegubus.MainActivity
import com.devground.daegubus.R
import com.devground.daegubus.models.BusInfo
import com.devground.daegubus.utils.NotificationHandler
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

class BusAlertAutoAlarmNotifier(private val service: BusAlertService) {
    private val context: Context get() = service
    private val TAG = "BusAlertAutoAlarmNotifier"

    private var chipLastStation: String = ""
    private var chipDetailUntilMs: Long = 0L
    private var chipRevertJob: Job? = null
    private var chipLastBusNo: String = ""
    private var chipLastStationName: String = ""
    private var chipLastRemainingMinutes: Int = 0
    private var chipLastRemainingStops: String = "0"
    private var chipLastRouteTCd: String? = null

    fun resetChipState() {
        chipLastStation = ""
        chipDetailUntilMs = 0L
        chipRevertJob?.cancel()
        chipRevertJob = null
    }

    fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val autoAlarmChannelId = BusAlertService.getAutoAlarmChannelId()

            if (Build.VERSION.SDK_INT >= 36) {
                cleanupLegacyAutoAlarmChannels(notificationManager, autoAlarmChannelId)
            } else {
                // 진동 있는 구 채널 삭제 (알림 업데이트 시 재진동 방지)
                try {
                    notificationManager.deleteNotificationChannel(BusAlertService.CHANNEL_ID_AUTO_ALARM_LEGACY_OLD)
                } catch (_: Exception) {}
            }

            if (notificationManager.getNotificationChannel(autoAlarmChannelId) == null) {
                val channel = NotificationChannel(
                    autoAlarmChannelId,
                    BusAlertService.CHANNEL_NAME_AUTO_ALARM,
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = if (Build.VERSION.SDK_INT >= 36) {
                        "자동 알람 Live Update"
                    } else {
                        "자동 알람 알림 (업데이트 시 무음)"
                    }
                    if (Build.VERSION.SDK_INT >= 36) {
                        setSound(null, null)
                        enableVibration(false)
                        enableLights(false)
                        setBypassDnd(false)
                        setShowBadge(false)
                    } else {
                        setSound(null, null)
                        enableVibration(false)
                        enableLights(true)
                        lightColor = 0xFF2196F3.toInt()
                        setBypassDnd(true)
                        setShowBadge(true)
                    }
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }
                notificationManager.createNotificationChannel(channel)
                val createdChannel = notificationManager.getNotificationChannel(autoAlarmChannelId)
                Log.d(
                    TAG,
                    "자동알람 채널 생성 완료: id=$autoAlarmChannelId, importance=${createdChannel?.importance}, sound=${createdChannel?.sound}, vibration=${createdChannel?.shouldVibrate()}"
                )
            }
        }
    }

    fun cleanupLegacyAutoAlarmChannels(
        notificationManager: NotificationManager,
        keepChannelId: String
    ) {
        listOf(BusAlertService.CHANNEL_ID_AUTO_ALARM_LEGACY, BusAlertService.CHANNEL_ID_AUTO_ALARM_LEGACY_OLD, "auto_alarm_live_update_v2")
            .filter { it != keepChannelId }
            .forEach { channelId ->
                val legacyChannel = notificationManager.getNotificationChannel(channelId) ?: return@forEach
                Log.w(
                    TAG,
                    "🧹 Removing legacy auto-alarm channel: id=$channelId, importance=${legacyChannel.importance}, sound=${legacyChannel.sound}, vibration=${legacyChannel.shouldVibrate()}"
                )
                try {
                    notificationManager.deleteNotificationChannel(channelId)
                } catch (e: Exception) {
                    Log.e(TAG, "❌ Failed to delete legacy auto-alarm channel $channelId: ${e.message}", e)
                }
            }
    }

    fun showInitialNotification(busNo: String, stationName: String, remainingMinutes: Int, currentStation: String) {
        try {
            ensureChannel()

            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

            val smallView = RemoteViews(context.packageName, R.layout.notification_auto_alarm_small).apply {
                setTextViewText(R.id.tv_bus_no, busNo)
                setTextViewText(R.id.tv_arrival_info, "도착 정보 확인 중...")
                setTextViewText(R.id.tv_station_name, stationName)
            }

            val bigView = RemoteViews(context.packageName, R.layout.notification_auto_alarm_big).apply {
                setTextViewText(R.id.tv_bus_no, busNo)
                setTextViewText(R.id.tv_arrival_time, "확인 중")
                setTextViewText(R.id.tv_remaining_stops, "")
                setTextViewText(R.id.tv_station_name, stationName)
                setProgressBar(R.id.progress_bar, 100, 0, true)
                setViewVisibility(R.id.tv_current_location, android.view.View.GONE)
            }

            val appIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            val contentPendingIntent = appIntent?.let {
                PendingIntent.getActivity(context, BusAlertService.AUTO_ALARM_NOTIFICATION_ID, it,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            }

            val stopIntent = Intent(context, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_STOP_AUTO_ALARM
            }
            val stopPendingIntent = PendingIntent.getService(
                context, BusAlertService.AUTO_ALARM_NOTIFICATION_ID + 1, stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val ongoingChannelId = NotificationHandler.getOngoingChannelId()
            val notification = NotificationCompat.Builder(context, ongoingChannelId)
                .setSmallIcon(R.drawable.ic_bus_notification)
                .setStyle(NotificationCompat.DecoratedCustomViewStyle())
                .setCustomContentView(smallView)
                .setCustomBigContentView(bigView)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setAutoCancel(false)
                .setOngoing(true)
                .setRequestPromotedOngoing(true)
                .setContentIntent(contentPendingIntent)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .addAction(R.drawable.ic_cancel, "알람 끄기", stopPendingIntent)
                .setColor(ContextCompat.getColor(context, R.color.tracking_color))
                .setSilent(true)
                .build()

            if (!service.isInForeground) {
                try {
                    if (Build.VERSION.SDK_INT >= 36) {
                        service.startForeground(
                            BusAlertService.ONGOING_NOTIFICATION_ID,
                            notification,
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                        )
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        service.startForeground(
                            BusAlertService.ONGOING_NOTIFICATION_ID,
                            notification,
                            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                        )
                    } else {
                        service.startForeground(BusAlertService.ONGOING_NOTIFICATION_ID, notification)
                    }
                    service.isInForeground = true
                    Log.d(TAG, "✅ 자동알람: 포그라운드 서비스 시작")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 포그라운드 서비스 시작 실패, notify 사용: ${e.message}")
                    notificationManager.notify(BusAlertService.ONGOING_NOTIFICATION_ID, notification)
                }
            } else {
                // 이미 포그라운드 상태 → 같은 ONGOING ID로 업데이트 (별도 알림 생성 방지)
                notificationManager.notify(BusAlertService.ONGOING_NOTIFICATION_ID, notification)
            }
            Log.d(TAG, "✅ 자동알람 초기 알림 표시: $busNo ($stationName)")

        } catch (e: Exception) {
            Log.e(TAG, "❌ 자동알람 초기 알림 실패: ${e.message}", e)
        }
    }

    fun updateWithData(
        busNo: String,
        stationName: String,
        remainingMinutes: Int,
        remainingStops: String,
        currentStation: String,
        routeTCd: String? = null
    ) {
        try {
            ensureChannel()
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            val autoAlarmChannelId = BusAlertService.getAutoAlarmChannelId()
            Log.d(TAG, "자동알람 업데이트 채널 선택: $autoAlarmChannelId")

            val appIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            val contentPendingIntent = appIntent?.let {
                PendingIntent.getActivity(context, BusAlertService.AUTO_ALARM_NOTIFICATION_ID, it,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            }

            val stopIntent = Intent(context, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_STOP_AUTO_ALARM
            }
            val stopPendingIntent = PendingIntent.getService(
                context, BusAlertService.AUTO_ALARM_NOTIFICATION_ID + 1, stopIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            chipLastBusNo = busNo
            chipLastStationName = stationName
            chipLastRemainingMinutes = remainingMinutes
            chipLastRemainingStops = remainingStops
            chipLastRouteTCd = routeTCd

            val stationChanged = currentStation.isNotBlank() && currentStation != chipLastStation
            if (stationChanged) {
                chipLastStation = currentStation
                chipDetailUntilMs = System.currentTimeMillis() + 4000L
                chipRevertJob?.cancel()
                chipRevertJob = service.serviceScope.launch {
                    delay(4000)
                    updateWithData(
                        chipLastBusNo, chipLastStationName,
                        chipLastRemainingMinutes, chipLastRemainingStops,
                        chipLastStation, chipLastRouteTCd
                    )
                }
            }

            val stopsInt = remainingStops.filter { it.isDigit() }.toIntOrNull() ?: 0

            val busTypeColor = when (routeTCd) {
                "1" -> 0xFFDC2626.toInt()
                "2" -> 0xFFF59E0B.toInt()
                "3" -> 0xFF2563EB.toInt()
                "4" -> 0xFF10B981.toInt()
                else -> ContextCompat.getColor(context, R.color.tracking_color)
            }

            if (Build.VERSION.SDK_INT >= 36) {
                try {
                    val liveTitle = when {
                        stopsInt == 1  -> "$busNo 번 버스 · 곧 도착"
                        stopsInt > 1   -> "$busNo 번 버스 · ${stopsInt}개소 전"
                        remainingMinutes <= 0 -> "$busNo 번 버스 · 곧 도착"
                        else           -> "$busNo 번 버스 · ${remainingMinutes}분 후 도착"
                    }
                    val destShort = if (stationName.length > 10) "${stationName.take(10)}.." else stationName
                    val locationPart = if (currentStation.isNotBlank() && currentStation != "정보 없음") "현재: $currentStation" else ""
                    val liveBody = when {
                        stopsInt > 0 && locationPart.isNotEmpty() -> "$locationPart → $destShort 방향 · ${stopsInt}정거장 남음"
                        stopsInt > 0                               -> "$destShort 방향 · ${stopsInt}정거장 남음"
                        locationPart.isNotEmpty()                  -> "$locationPart → $destShort"
                        else                                       -> "$destShort · ${remainingMinutes}분 후 도착"
                    }
                    val chipText = when {
                        stopsInt == 1        -> "곧도착"
                        stopsInt > 1         -> "${stopsInt}개소전"
                        remainingMinutes <= 0 -> "곧도착"
                        else                 -> "${remainingMinutes}분후"
                    }.take(7)

                    @Suppress("NewApi")
                    val nativeBuilder = Notification.Builder(context, autoAlarmChannelId)
                        .setContentTitle(liveTitle)
                        .setContentText(liveBody)
                        .setSubText(stationName.take(14))
                        .setShortCriticalText(chipText)
                        .setSmallIcon(R.drawable.ic_bus_notification)
                        .setCategory(Notification.CATEGORY_PROGRESS)
                        .setContentIntent(contentPendingIntent)
                        .setOngoing(true)
                        .setAutoCancel(false)
                        .setOnlyAlertOnce(true)
                        .setShowWhen(true)
                        .setColor(busTypeColor)
                        .setColorized(true)
                        .setVisibility(Notification.VISIBILITY_PUBLIC)
                        .setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
                        .addAction(Notification.Action.Builder(
                            android.graphics.drawable.Icon.createWithResource(context, R.drawable.ic_cancel),
                            "알람 끄기",
                            stopPendingIntent
                        ).build())

                    Log.d(TAG, "🎯 상태칩: '$chipText'  제목: '$liveTitle'")

                    val arrivalTimeMillis = if (remainingMinutes > 0) {
                        System.currentTimeMillis() + remainingMinutes * 60_000L
                    } else {
                        System.currentTimeMillis() + 60_000L
                    }
                    nativeBuilder.setWhen(arrivalTimeMillis)
                    nativeBuilder.setUsesChronometer(true)
                    nativeBuilder.setChronometerCountDown(true)

                    nativeBuilder.setExtras(android.os.Bundle().apply {
                        putBoolean("android.requestPromotedOngoing", true)
                    })
                    try {
                        nativeBuilder.javaClass
                            .getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType)
                            .invoke(nativeBuilder, true)
                    } catch (_: ReflectiveOperationException) { }

                    val MAX_STOPS = 30
                    val MAX_MINUTES = 30
                    val progressPercent = when {
                        stopsInt > 0         -> ((MAX_STOPS - stopsInt.coerceIn(0, MAX_STOPS)) * 100 / MAX_STOPS)
                        remainingMinutes > 0 -> ((MAX_MINUTES - remainingMinutes.coerceIn(0, MAX_MINUTES)) * 100 / MAX_MINUTES)
                        else                 -> 100
                    }.coerceIn(0, 100)
                    val remainingPercent = (100 - progressPercent).coerceIn(0, 100)
                    val progress = progressPercent.coerceIn(0, 100)

                    @Suppress("NewApi")
                    try {
                        val progressStyle = Notification.ProgressStyle()
                            .setProgress(progress)

                        try { progressStyle.setStyledByProgress(true) } catch (_: Exception) {}

                        val busIcon = android.graphics.drawable.Icon.createWithResource(context, R.drawable.ic_bus_tracker)
                        progressStyle.setProgressTrackerIcon(busIcon)

                        try {
                            val segments = mutableListOf<Notification.ProgressStyle.Segment>()
                            if (progress > 0) {
                                segments.add(Notification.ProgressStyle.Segment(progress).setColor(busTypeColor))
                            }
                            if (remainingPercent > 0) {
                                segments.add(Notification.ProgressStyle.Segment(remainingPercent).setColor(0xFFE0E0E0.toInt()))
                            }
                            if (segments.isNotEmpty()) {
                                progressStyle.setProgressSegments(segments)
                            }
                        } catch (_: Exception) {}

                        try {
                            val startPt = Notification.ProgressStyle.Point(1)
                                .setColor(0xFF4CAF50.toInt())
                            val endPt = Notification.ProgressStyle.Point(99)
                                .setColor(0xFFFF5722.toInt())
                            progressStyle.setProgressPoints(listOf(startPt, endPt))
                        } catch (_: Exception) {}

                        nativeBuilder.setStyle(progressStyle)
                        nativeBuilder.setProgress(100, progress, false)
                    } catch (e: Exception) {
                        Log.w(TAG, "⚠️ 자동알람 ProgressStyle 설정 실패: ${e.message}")
                        nativeBuilder.setProgress(100, progress, false)
                    }

                    val chipApplied = setLiveUpdateStatusChip(nativeBuilder, chipText)

                    if (isSamsungOneUi()) {
                        val detailText = chipText
                        val statusText = detailText.ifBlank { "정보 없음" }
                        val secondaryInfo = if (currentStation.isNotBlank() && currentStation != "정보 없음") {
                            "$stationName: $currentStation"
                        } else {
                            stationName
                        }
                        val oneUiBundle = android.os.Bundle().apply {
                            putInt("style", 1)
                            putString("primaryInfo", busNo)
                            putString("secondaryInfo", "$secondaryInfo ($statusText)")
                            putString("chipExpandedText", statusText)
                            putString("chipText", statusText)
                            putString("nowbarSecondaryText", statusText)
                            putInt("chipBgColor", busTypeColor)
                            val chipIcon = android.graphics.drawable.Icon.createWithResource(
                                context,
                                R.drawable.ic_bus_tracker
                            )
                            putParcelable("chipIcon", chipIcon)
                            if (remainingMinutes > 0) {
                                putInt("progress", progress)
                                putInt("progressMax", 100)
                                val trackerIcon = android.graphics.drawable.Icon.createWithResource(
                                    context,
                                    R.drawable.ic_bus_tracker
                                )
                                putParcelable("progressSegments.icon", trackerIcon)
                                putInt("progressSegments.progressColor", busTypeColor)
                            }
                            putString("nowbarPrimaryInfo", busNo)
                            putString("nowbarSecondaryInfo", statusText)
                            putInt("actionType", 1)
                            putInt("actionPrimarySet", 0)
                        }
                        val samsungExtras = android.os.Bundle()
                        applyOneUiOngoingExtras(samsungExtras, oneUiBundle)
                        nativeBuilder.addExtras(samsungExtras)
                    }

                    var builtNotification = nativeBuilder.build()
                    @Suppress("NewApi")
                    val hasPromotableCharacteristics = if (Build.VERSION.SDK_INT >= 36) {
                        try {
                            builtNotification.hasPromotableCharacteristics()
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ hasPromotableCharacteristics 호출 실패: ${e.message}")
                            false
                        }
                    } else {
                        false
                    }
                    Log.d(TAG, "📋 builtNotification.hasPromotableCharacteristics(): $hasPromotableCharacteristics")

                    val canPostPromoted = if (Build.VERSION.SDK_INT >= 36) {
                        try {
                            notificationManager.canPostPromotedNotifications()
                        } catch (e: Exception) {
                            Log.w(
                                TAG,
                                "⚠️ NotificationManager.canPostPromotedNotifications() 호출 실패: ${e.message}"
                            )
                            false
                        }
                    } else {
                        false
                    }
                    Log.d(TAG, "📋 NotificationManager.canPostPromotedNotifications(): $canPostPromoted")

                    val isPromotedEnabled = canPostPromoted && hasPromotableCharacteristics
                    Log.d(TAG, if (chipApplied && isPromotedEnabled)
                        "✅ 상태칩 적용 완료: '$chipText'"
                    else
                        "⚠️ 상태칩 미승격: chipApplied=$chipApplied, hasPromotable=$hasPromotableCharacteristics, canPostPromoted=$canPostPromoted"
                    )
                    @Suppress("NewApi")
                    builtNotification.flags = builtNotification.flags or
                        Notification.FLAG_ONGOING_EVENT or
                        Notification.FLAG_NO_CLEAR or
                        Notification.FLAG_PROMOTED_ONGOING

                    notificationManager.notify(BusAlertService.ONGOING_NOTIFICATION_ID, builtNotification)
                    Log.d(TAG, "✅ 자동알람 Live Update 알림 갱신: $busNo, ${chipText}, 위치=$currentStation")
                    return

                } catch (e: Exception) {
                    Log.e(TAG, "❌ 자동알람 Android 16 알림 오류, fallback 사용: ${e.message}")
                }
            }

            val arrivalInfoText = when {
                stopsInt == 1        -> "곧 도착"
                stopsInt > 1         -> "${stopsInt}개소 전"
                remainingMinutes <= 0 -> "곧 도착"
                else                 -> "${remainingMinutes}분 후 도착"
            }
            val arrivalTimeText = when {
                remainingMinutes <= 0 -> "곧 도착"
                else -> "${remainingMinutes}분"
            }
            val stopsText = if (stopsInt > 0) "${stopsInt}정거장 남음" else ""

            val smallView = RemoteViews(context.packageName, R.layout.notification_auto_alarm_small).apply {
                setTextViewText(R.id.tv_bus_no, busNo)
                setTextViewText(R.id.tv_arrival_info, "$arrivalInfoText ($stopsText)")
                setTextViewText(R.id.tv_station_name, stationName)
            }

            val maxStops = 30
            val progressPercent = if (stopsInt > 0) {
                ((maxStops - stopsInt.coerceIn(0, maxStops)) * 100) / maxStops
            } else if (remainingMinutes > 0) {
                ((30 - remainingMinutes.coerceIn(0, 30)) * 100) / 30
            } else {
                100
            }

            val bigView = RemoteViews(context.packageName, R.layout.notification_auto_alarm_big).apply {
                setTextViewText(R.id.tv_bus_no, busNo)
                setTextViewText(R.id.tv_arrival_time, arrivalTimeText)
                setTextViewText(R.id.tv_remaining_stops, stopsText)
                setTextViewText(R.id.tv_station_name, stationName)
                setProgressBar(R.id.progress_bar, 100, progressPercent, false)
                if (currentStation.isNotBlank() && currentStation != "정보 없음") {
                    setTextViewText(R.id.tv_current_location, "📍 $currentStation")
                    setViewVisibility(R.id.tv_current_location, android.view.View.VISIBLE)
                } else {
                    setViewVisibility(R.id.tv_current_location, android.view.View.GONE)
                }
            }

            val notification = NotificationCompat.Builder(context, autoAlarmChannelId)
                .setSmallIcon(R.drawable.ic_bus_notification)
                .setStyle(NotificationCompat.DecoratedCustomViewStyle())
                .setCustomContentView(smallView)
                .setCustomBigContentView(bigView)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setAutoCancel(false)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(contentPendingIntent)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .addAction(R.drawable.ic_cancel, "알람 끄기", stopPendingIntent)
                .setColor(busTypeColor)
                .setShowWhen(true)
                .setWhen(System.currentTimeMillis())
                .build()

            notificationManager.notify(BusAlertService.ONGOING_NOTIFICATION_ID, notification)
            Log.d(TAG, "✅ 자동알람 맞춤 레이아웃 알림 갱신: $busNo $arrivalInfoText ($stopsText)")

        } catch (e: Exception) {
            Log.e(TAG, "❌ 자동알람 알림 업데이트 실패: ${e.message}", e)
        }
    }

    @Suppress("NewApi")
    @android.annotation.SuppressLint("NewApi")
    fun setLiveUpdateStatusChip(
        nativeBuilder: Notification.Builder,
        chipText: String
    ): Boolean {
        val safeChipText = chipText.trim().take(7).ifBlank { "???" }
        val legacyChipText = chipText.trim().ifBlank { "정보 없음" }
        var success = false
        try {
            nativeBuilder.setShortCriticalText(safeChipText)
            Log.d(TAG, "✅ setShortCriticalText('$safeChipText') 직접 호출 성공")
            success = true
        } catch (e: Exception) {
            Log.w(TAG, "⚠️ setShortCriticalText 호출 실패: ${e.message}")
        }

        try {
            nativeBuilder.setContentInfo(safeChipText)
        } catch (_: Exception) { }

        return success
    }

    fun buildLiveUpdateStatusChipText(
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

    fun applyOneUiOngoingExtras(targetBundle: android.os.Bundle, oneUiBundle: android.os.Bundle) {
        val namespaceList = listOf(
            "android.ongoingActivityNoti",
            "android.ongoingActivity",
            "android.ongoingActivityInfo",
            "android.ongoingActivityInfoV2"
        )
        fun putExtraByType(bundle: android.os.Bundle, key: String, value: Any?) {
            when (value) {
                is String -> bundle.putString(key, value)
                is Int -> bundle.putInt(key, value)
                is Long -> bundle.putLong(key, value)
                is Float -> bundle.putFloat(key, value)
                is Double -> bundle.putDouble(key, value)
                is Boolean -> bundle.putBoolean(key, value)
                is android.graphics.drawable.Icon -> bundle.putParcelable(key, value)
                is android.os.Parcelable -> bundle.putParcelable(key, value)
                is IntArray -> bundle.putIntArray(key, value)
                is LongArray -> bundle.putLongArray(key, value)
                is FloatArray -> bundle.putFloatArray(key, value)
                is DoubleArray -> bundle.putDoubleArray(key, value)
                is BooleanArray -> bundle.putBooleanArray(key, value)
                null -> {}
                else -> bundle.putString(key, value.toString())
            }
        }

        namespaceList.forEach { namespace ->
            targetBundle.putBundle(namespace, oneUiBundle)
            oneUiBundle.keySet().forEach { key ->
                val value = oneUiBundle.get(key)
                val namespacedKey = "$namespace.$key"
                putExtraByType(targetBundle, key, value)
                putExtraByType(targetBundle, namespacedKey, value)
            }
        }
    }

    // handleAutoAlarmLightweight/stopAutoAlarmLightweight/updateAutoAlarmBusInfo는
    // BusAlertService에서 이관 (2026-07-25). Log 태그는 원래 동작 그대로
    // "BusAlertService"를 유지한다 (이 클래스 자체 TAG와 다름).
    fun handleAutoAlarmLightweight(busNo: String, stationName: String, remainingMinutes: Int, currentStation: String, routeId: String, stationId: String, useTTS: Boolean = true, isCommuteAlarm: Boolean = false, alarmHour: Int = -1, alarmMinute: Int = -1, targetAlarmTime: Long = 0L, excludeHolidays: Boolean = false) {
        try {
            Log.d("BusAlertService", "🔔 자동알람 경량화 모드 처리: $busNo 번, $stationName, routeId=$routeId, stationId=$stationId, TTS=$useTTS")

            // 동기 중복 방지: coroutine 시작 전 즉시 체크 (6ms 간격 중복 호출 차단)
            if (routeId.isNotBlank() && (service.pendingAutoAlarms.contains(routeId) || service.activeTrackings.containsKey(routeId))) {
                Log.w("BusAlertService", "⚠️ 자동알람 중복 방지 (동기): $routeId 이미 처리 중 - 무시")
                return
            }
            if (routeId.isNotBlank()) service.pendingAutoAlarms.add(routeId)

            // 자동알람 모드 활성화
            service.isAutoAlarmMode = true
            service.autoAlarmStartTime = System.currentTimeMillis()

            // 정확한 알람 발화 시각 계산 (toggle OFF 모드용) - TrackingInfo에 저장 (다중 알람 독립 관리)
            val computedTriggerTime = if (targetAlarmTime > 0L) {
                targetAlarmTime
            } else if (alarmHour >= 0 && alarmMinute >= 0) {
                val cal = java.util.Calendar.getInstance().apply {
                    set(java.util.Calendar.HOUR_OF_DAY, alarmHour)
                    set(java.util.Calendar.MINUTE, alarmMinute)
                    set(java.util.Calendar.SECOND, 0)
                    set(java.util.Calendar.MILLISECOND, 0)
                }
                // 이미 지났으면 현재 시각 사용
                if (cal.timeInMillis < service.autoAlarmStartTime) service.autoAlarmStartTime else cal.timeInMillis
            } else {
                service.autoAlarmStartTime // Flutter 트리거: 즉시 발화
            }
            Log.d("BusAlertService", "⏰ 알람 발화 시각: ${java.util.Date(computedTriggerTime)}, alarmHour=$alarmHour, alarmMinute=$alarmMinute, targetAlarmTime=$targetAlarmTime")

            // 정보 저장
            service.currentAutoAlarmBusNo = busNo
            service.currentAutoAlarmStationName = stationName
            service.currentAutoAlarmRouteId = routeId

            // 자동알람: 포그라운드 서비스 즉시 시작 (5초 제한 대응, ONGOING 알림 재사용)
            if (!service.isInForeground) {
                try {
                    val placeholder = service.notificationHandler.buildOngoingNotification(mapOf())
                    if (Build.VERSION.SDK_INT >= 36) {
                        service.startForeground(BusAlertService.ONGOING_NOTIFICATION_ID, placeholder, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
                    } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        service.startForeground(BusAlertService.ONGOING_NOTIFICATION_ID, placeholder, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
                    } else {
                        service.startForeground(BusAlertService.ONGOING_NOTIFICATION_ID, placeholder)
                    }
                    service.isInForeground = true
                    Log.d("BusAlertService", "🔔 자동알람: 포그라운드 서비스 시작")
                } catch (e: Exception) {
                    Log.e("BusAlertService", "❌ 자동알람 포그라운드 시작 실패: ${e.message}", e)
                }
            }

            // 발화 시점 공휴일 게이트 2단계: CDN 신선 조회 (백그라운드, 3초 타임아웃).
            // 스케줄 등록 이후 지정된 임시공휴일을 앱 실행 없이도 잡는다.
            // 조회 실패(null)면 알람을 막지 않는다.
            if (excludeHolidays) {
                service.serviceScope.launch {
                    val isHoliday = withContext(Dispatchers.IO) {
                        com.devground.daegubus.utils.HolidayGate.isTodayHolidayFresh()
                    }
                    if (isHoliday == true) {
                        Log.w("BusAlertService", "🚫 오늘이 공휴일로 확인됨(신선 조회) - 자동알람 중단: $busNo")
                        stopAutoAlarmLightweight()
                    }
                }
            }

            // 🔊 TTS 미사용 시 알람 사운드 재생 (퇴근 알람은 이어폰 연결 시에만)
            if (!useTTS) {
                val isReturnAlarmStart = !isCommuteAlarm
                if (!isReturnAlarmStart || service.ttsController.isHeadsetConnected()) {
                    service.alarmSoundPlayer.play()
                } else {
                    Log.d("BusAlertService", "📵 퇴근 알람: 이어폰 미연결 → 알람 사운드 재생 안함")
                }
            }

            // 📌 핵심: 실시간 추적 시작 → 첫 API 응답 시 실제 도착 정보로 TTS 발화
            // (기존: 의미 없는 "알람이 시작되었습니다" 멘트 제거 → 실제 "N분 후 도착" 발화)
            if (routeId.isNotBlank() && stationId.isNotBlank()) {
                Log.d("BusAlertService", "🔔 자동알람: 실시간 추적 시작 ($routeId, $stationId)")
                service.addMonitoredRoute(routeId, stationId, stationName)
                service.startTracking(routeId, stationId, stationName, busNo, isAutoAlarm = true, isCommuteAlarm = isCommuteAlarm, exactAlarmTriggerTime = computedTriggerTime)
            } else {
                Log.e("BusAlertService", "❌ 자동알람: routeId 또는 stationId 누락으로 추적 불가")
            }

            // Flutter에 시작 알림 전송 (중복 실행 방지용)
            MainActivity.sendFlutterEvent("onAutoAlarmStarted", mapOf(
                "busNo" to busNo,
                "stationName" to stationName,
                "routeId" to routeId,
                "timestamp" to System.currentTimeMillis()
            ))

            // 설정 기반 자동 종료 스케줄링 (취소 가능한 Runnable 사용)
            service.autoAlarmTimeoutRunnable?.let { service.mainHandler.removeCallbacks(it) }
            service.autoAlarmTimeoutRunnable = Runnable {
                service.autoAlarmTimeoutRunnable = null
                if (service.isAutoAlarmMode && (System.currentTimeMillis() - service.autoAlarmStartTime) >= service.autoAlarmTimeoutMs) {
                    Log.d("BusAlertService", "🔔 자동알람 경량화 모드 타임아웃으로 종료")
                    stopAutoAlarmLightweight()
                }
            }
            service.mainHandler.postDelayed(service.autoAlarmTimeoutRunnable!!, service.autoAlarmTimeoutMs)

            Log.d("BusAlertService", "✅ 자동알람 경량화 모드 시작 완료")

        } catch (e: Exception) {
            Log.e("BusAlertService", "❌ 자동알람 경량화 모드 처리 오류: ${e.message}", e)
        }
    }

    /**
     * 자동알람 경량화 모드 종료
     */
    fun stopAutoAlarmLightweight() {
        try {
            Log.d("BusAlertService", "🔔 자동알람 경량화 모드 종료")

            service.autoAlarmTimeoutRunnable?.let { service.mainHandler.removeCallbacks(it) }
            service.autoAlarmTimeoutRunnable = null

            service.alarmSoundPlayer.stop()

            // TTS 추적 중지
            try {
                service.ttsController.stopTtsServiceTracking()
                Log.d("BusAlertService", "✅ TTS 추적 중지 완료")
            } catch (e: Exception) {
                Log.w("BusAlertService", "⚠️ TTS 추적 중지 오류 (무시): ${e.message}")
            }

            // 자동알람 추적에 해당하는 모니터링 작업 취소
            val autoAlarmRouteId = service.currentAutoAlarmRouteId
            if (autoAlarmRouteId.isNotBlank()) {
                try {
                    service.monitoringJobs[autoAlarmRouteId]?.cancel()
                    service.monitoringJobs.remove(autoAlarmRouteId)
                    service.activeTrackings.remove(autoAlarmRouteId)
                    service.monitoredRoutes.remove(autoAlarmRouteId)
                    service.cachedBusInfo.remove(autoAlarmRouteId)
                    Log.d("BusAlertService", "✅ 자동알람 모니터링 작업 취소 완료: $autoAlarmRouteId")
                } catch (e: Exception) {
                    Log.w("BusAlertService", "⚠️ 자동알람 모니터링 취소 오류 (무시): ${e.message}")
                }
            }

            service.isAutoAlarmMode = false
            service.autoAlarmStartTime = 0L
            if (autoAlarmRouteId.isNotBlank()) service.pendingAutoAlarms.remove(autoAlarmRouteId)

            val notificationManager = service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancel(BusAlertService.AUTO_ALARM_NOTIFICATION_ID)

            // activeTrackings이 비었으면 포그라운드 서비스 + ONGOING 노티도 중지
            service.updateForegroundNotification()

            // Flutter에 종료 알림 전송 (재실행 방지용)
            MainActivity.sendFlutterEvent("onAutoAlarmStopped", mapOf(
                "timestamp" to System.currentTimeMillis(),
                "busNo" to service.currentAutoAlarmBusNo,
                "stationName" to service.currentAutoAlarmStationName,
                "routeId" to service.currentAutoAlarmRouteId
            ))

            Log.d("BusAlertService", "✅ 자동알람 경량화 모드 종료 완료")

        } catch (e: Exception) {
            Log.e("BusAlertService", "❌ 자동알람 경량화 모드 종료 오류: ${e.message}", e)
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
        Log.d("BusAlertService", "🔄 updateAutoAlarmBusInfo: $busNo, $stationName, $remainingMinutes, '$currentStation'")
        val info = service.activeTrackings[routeId] ?: TrackingInfo(
            routeId = routeId,
            stationName = stationName,
            busNo = busNo,
            stationId = stationId
        ).also { service.activeTrackings[routeId] = it }

        // 운행종료 판단 로직 개선 - 기점출발예정, 차고지행 등은 운행종료가 아님
        val isOutOfService = (currentStation.contains("운행종료")) ||
                            (currentStation.contains("차고지") && remainingMinutes < 0)

        Log.d("BusAlertService", "🔍 [updateAutoAlarmBusInfo] 운행종료 판단: remainingMinutes=$remainingMinutes, currentStation='$currentStation', isOutOfService=$isOutOfService")

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

        service.showOngoingBusTracking(
            busNo = busNo,
            stationName = stationName,
            remainingMinutes = busInfo.getRemainingMinutes(),
            currentStation = busInfo.currentStation,
            isUpdate = true,
            notificationId = BusAlertService.ONGOING_NOTIFICATION_ID,
            allBusesSummary = null,
            routeId = routeId,
            stationId = stationId
        )
    }
}
