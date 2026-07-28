package com.devground.daegubus.services

import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import com.devground.daegubus.R
import com.devground.daegubus.models.BusInfo
import com.devground.daegubus.utils.NotificationHandler
import kotlinx.coroutines.launch
import java.util.Calendar

class BusAlertNotificationUpdater(
    private val service: BusAlertService,
    private val notificationHandler: NotificationHandler,
) {
    companion object {
        private const val TAG = "BusAlertService"
    }

    fun buildOngoing(activeTrackings: Map<String, TrackingInfo>): Notification {
        return notificationHandler.buildOngoingNotification(activeTrackings)
    }

    fun updateOngoing(
        notificationId: Int,
        activeTrackings: Map<String, TrackingInfo>,
        isInForeground: Boolean,
        setInForeground: (Boolean) -> Unit,
    ) {
        val notification = buildOngoing(activeTrackings)
        val notificationManager =
            service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (!isInForeground) {
            try {
                if (Build.VERSION.SDK_INT >= 36) {
                    service.startForeground(
                        notificationId,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
                    )
                } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    service.startForeground(
                        notificationId,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                } else {
                    service.startForeground(notificationId, notification)
                }
                setInForeground(true)
                Log.d(TAG, "✅ 포그라운드 서비스 시작됨: ID=$notificationId")
            } catch (e: Exception) {
                Log.e(TAG, "❌ 포그라운드 서비스 시작 오류: ${e.message}")
                notificationManager.notify(notificationId, notification)
            }
        } else {
            notificationManager.notify(notificationId, notification)
        }
    }

    // showOngoingBusTracking/updateTrackingNotification/showBusArrivingSoon은
    // BusAlertService에서 이관 (2026-07-25). 이 클래스의 TAG도 원래 "BusAlertService"라
    // Log 태그 치환은 필요 없다.
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
        val trackingInfo = service.activeTrackings[effectiveRouteId] ?: TrackingInfo(
            routeId = effectiveRouteId,
            stationName = stationName,
            busNo = busNo
        ).also { service.activeTrackings[effectiveRouteId] = it }

        Log.d(TAG, "🔄 showOngoingBusTracking: $busNo, $stationName, $remainingMinutes, currentStation='$currentStation', isIndividualAlarm=$isIndividualAlarm, notificationId=$notificationId")

        // stationId 보정
        var effectiveStationId = stationId ?: trackingInfo.stationId
        if (effectiveStationId.isBlank() || effectiveStationId.length < 10 || !effectiveStationId.startsWith("7")) {
            service.serviceScope.launch {
                val fixedStationId = service.resolveStationIdIfNeeded(effectiveRouteId, stationName, effectiveStationId, wincId)
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
            updateOngoing(
                BusAlertService.ONGOING_NOTIFICATION_ID,
                service.activeTrackings,
                service.isInForeground
            ) { newValue ->
                service.isInForeground = newValue
            }

            Log.d(TAG, "✅ 알림 통합 업데이트: $busNo, $formattedTime, $currentStationFinal, ID=${BusAlertService.ONGOING_NOTIFICATION_ID}")

            // 백업 업데이트 (항상 실행)
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    val backup = buildOngoing(service.activeTrackings)
                    val notificationManager =
                        service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.notify(BusAlertService.ONGOING_NOTIFICATION_ID, backup)
                } catch (_: Exception) {}
            }, 1000)

            // 자동알람 모드에서도 ONGOING 알림(추적 중지)으로 통일 — 별도 알림 없음

        } catch (e: Exception) {
            Log.e(TAG, "❌ 알림 ${if(isIndividualAlarm) "생성" else "업데이트"} 오류: ${e.message}", e)
            if (!isIndividualAlarm) { // 개별 알람이 아닐 때만 포그라운드 알림 업데이트 시도
                service.updateForegroundNotification()
            }
        }
    }

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
            service.serviceScope.launch {
                val fixedStationId = service.resolveStationIdIfNeeded(routeId, stationName, "", wincId)
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
            val info = service.activeTrackings[routeId] ?: TrackingInfo(
                routeId = routeId,
                stationName = stationName,
                busNo = busNo,
                stationId = ""
            ).also {
                service.activeTrackings[routeId] = it
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
                notificationId = BusAlertService.ONGOING_NOTIFICATION_ID,
                allBusesSummary = null,
                routeId = routeId
            )

            // 3.2. 백업 방법으로 알림 업데이트
            service.updateForegroundNotification()

            // 경량화: 불필요한 중복 업데이트 제거
            // 백업 타이머가 주기적으로 업데이트하므로 즉시 업데이트는 최소화

            Log.d(TAG, "✅ 버스 추적 알림 업데이트 완료: $busNo, ${remainingMinutes}분, 현재 위치: $currentStation")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 버스 추적 알림 업데이트 오류: ${e.message}", e)
            // 오류 발생 시에도 알림 업데이트 시도
            service.updateForegroundNotification()
        }
    }

    // [ADD] Show a notification for bus arriving soon
    fun showBusArrivingSoon(busNo: String, stationName: String, currentStation: String?) {
        try {
            val builder = NotificationCompat.Builder(service, BusAlertService.CHANNEL_ID_ALERT)
                .setSmallIcon(R.drawable.ic_bus_notification)
                .setContentTitle("$busNo 버스 곧 도착")
                .setContentText("$busNo bus is arriving at $stationName.")
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)

            if (currentStation != null) {
                builder.setStyle(NotificationCompat.BigTextStyle().bigText("Current location: $currentStation"))
            }

            val notificationManager = service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.notify(9998, builder.build())
            Log.d(TAG, "Arriving soon notification shown: $busNo, $stationName, $currentStation")
        } catch (e: Exception) {
            Log.e(TAG, "Error showing arriving soon notification: ${e.message}", e)
        }
    }
}
