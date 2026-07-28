package com.devground.daegubus.services

import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import com.devground.daegubus.MainActivity
import com.devground.daegubus.models.BusInfo
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

class BusAlertTrackingManager(
    private val busApiService: BusApiService,
    private val serviceScope: CoroutineScope,
    private val activeTrackings: MutableMap<String, TrackingInfo>,
    private val monitoringJobs: MutableMap<String, Job>,
    private val updateBusInfo: (String, String, String) -> Unit,
    private val showOngoing: (String, String, Int, String, String?, String?) -> Unit,
    private val updateForegroundNotification: () -> Unit,
    private val checkArrivalAndNotify: (TrackingInfo, BusInfo) -> Unit,
    private val checkNextBusAndNotify: (TrackingInfo, BusInfo) -> Unit,
    private val ttsController: BusAlertTtsController,
    private val useTextToSpeechProvider: () -> Boolean,
    private val arrivalThresholdMinutes: Int,
    private val service: Service,
    private val monitoredRoutes: MutableMap<String, Triple<String, String, Job?>>,
    private val arrivingSoonNotified: MutableSet<String>,
    private val hasNotifiedTts: MutableSet<String>,
    private val hasNotifiedArrival: MutableSet<String>,
    private val generateNotificationId: (String) -> Int,
    private val setInForeground: (Boolean) -> Unit,
    private val ongoingNotificationId: Int,
    private val cachedBusInfo: MutableMap<String, BusInfo>,
    private val isServiceActiveProvider: () -> Boolean,
    private val setServiceActive: (Boolean) -> Unit,
    private val isManuallyStoppedByUserProvider: () -> Boolean,
    private val setManuallyStoppedByUser: (Boolean) -> Unit,
    private val setLastManualStopTime: (Long) -> Unit,
    private val setAutoAlarmMode: (Boolean) -> Unit,
    private val setAutoAlarmStartTime: (Long) -> Unit,
    private val clearInstance: () -> Unit,
    private val isInForegroundProvider: () -> Boolean,
    private val stopMonitoringTimer: () -> Unit,
    private val stopTtsTrackingFn: (Boolean) -> Unit,
    private val sendAllCancellationBroadcast: () -> Unit,
    private val checkAndStopServiceIfNeeded: () -> Unit,
    private val autoAlarmNotificationId: Int,
) {
    companion object {
        private const val TAG = "BusAlertService"
    }

    // sendCancellationBroadcast 전용 중복 이벤트 방지 캐시 (2026-07-25, stopSpecificTracking/
    // stopAllTracking과 함께 이관 — 호출부가 이 두 함수뿐이라 여기로 옮겼다)
    private val sentCancellationEvents = mutableSetOf<String>()
    private val eventTimeouts = mutableMapOf<String, Long>()

    suspend fun startTrackingInternal(
        routeId: String,
        stationId: String,
        stationName: String,
        busNo: String,
        isAutoAlarm: Boolean = false,
        alarmId: Int? = null,
        isCommuteAlarm: Boolean = false,
    ) {
        if (monitoringJobs.containsKey(routeId)) {
            Log.d(TAG, "Tracking already active for route $routeId")
            val existingInfo = activeTrackings[routeId]
            if (existingInfo != null) {
                existingInfo.busNo = busNo
                existingInfo.stationName = stationName
                existingInfo.stationId = stationId
                existingInfo.alarmId = alarmId
                Log.d(TAG, "✅ 기존 추적 정보 업데이트: $routeId, $busNo, $stationName")
                updateBusInfo(routeId, stationId, stationName)
            }
            return
        }

        Log.i(TAG, "Starting tracking for route $routeId ($busNo) at station $stationName ($stationId)")

        val routeTCd = try {
            val routeInfo = busApiService.getBusRouteInfo(routeId)
            routeInfo?.routeTp
        } catch (e: Exception) {
            Log.e(TAG, "노선 정보 조회 오류 ($routeId): ${e.message}")
            null
        }

        val trackingInfo = TrackingInfo(
            routeId = routeId,
            stationName = stationName,
            busNo = busNo,
            stationId = stationId,
            isAutoAlarm = isAutoAlarm,
            alarmId = alarmId,
            isCommuteAlarm = isCommuteAlarm,
            routeTCd = routeTCd,
        )
        activeTrackings[routeId] = trackingInfo

        monitoringJobs[routeId] = serviceScope.launch {
            try {
                while (isActive) {
                    try {
                        val arrivals = busApiService.getStationInfo(stationId)
                            .let { jsonString ->
                                if (jsonString.isBlank() || jsonString == "[]") emptyList()
                                else parseJsonBusArrivals(jsonString, routeId)
                            }

                        if (!activeTrackings.containsKey(routeId)) {
                            Log.w(TAG, "Tracking info for $routeId removed. Stopping loop.")
                            break
                        }
                        val currentInfo = activeTrackings[routeId] ?: break
                        currentInfo.consecutiveErrors = 0

                        val firstBus = arrivals.firstOrNull { !it.isOutOfService }
                        if (firstBus != null) {
                            val remainingMinutes = firstBus.getRemainingMinutes()
                            Log.d(TAG, "🚌 Route $routeId ($busNo): Next bus in $remainingMinutes min. At: ${firstBus.currentStation}")

                            currentInfo.lastUpdateTime = System.currentTimeMillis()

                            val currentStation = if (firstBus.currentStation.isNotBlank()) {
                                firstBus.currentStation
                            } else {
                                currentInfo.lastBusInfo?.currentStation ?: trackingInfo.stationName
                            }

                            val allBusesSummary = activeTrackings.values.joinToString("\n") { info ->
                                "${info.busNo}: ${info.lastBusInfo?.estimatedTime ?: "정보 없음"} (${info.lastBusInfo?.currentStation ?: "위치 정보 없음"})"
                            }

                            val prevMinutes = currentInfo.lastBusInfo?.getRemainingMinutes()
                            val prevStation = currentInfo.lastBusInfo?.currentStation

                            if (prevMinutes != remainingMinutes || prevStation != currentStation) {
                                showOngoing(
                                    busNo,
                                    stationName,
                                    remainingMinutes,
                                    currentStation,
                                    routeId,
                                    allBusesSummary,
                                )
                                updateForegroundNotification()
                            }

                            // lastBusInfo는 항상 업데이트 (다음 루프에서 변경 감지용)
                            currentInfo.lastBusInfo = firstBus
                            currentInfo.lastUpdateTime = System.currentTimeMillis()

                            // TTS는 checkArrivalAndNotify에서 일괄 처리 (중복 발화 방지)
                            checkArrivalAndNotify(currentInfo, firstBus)
                            checkNextBusAndNotify(currentInfo, firstBus)
                        } else {
                            Log.w(TAG, "No available buses for route $routeId at $stationId.")
                            activeTrackings[routeId]?.lastBusInfo = null
                            updateForegroundNotification()
                        }

                        if (activeTrackings.isNotEmpty()) {
                            Log.d(TAG, "⏰ 현재 추적 중: ${activeTrackings.size}개 노선, 다음 업데이트 30초 후")
                        }

                        delay(30000)
                    } catch (e: CancellationException) {
                        Log.i(TAG, "Tracking job for $routeId cancelled.")
                        break
                    } catch (e: Exception) {
                        Log.e(TAG, "Error tracking $routeId: ${e.message}", e)
                        val currentInfo = activeTrackings[routeId]
                        if (currentInfo != null) {
                            currentInfo.consecutiveErrors++
                            if (currentInfo.consecutiveErrors >= 3) {
                                if (!currentInfo.isAutoAlarm) {
                                    Log.e(TAG, "Stopping tracking for $routeId due to errors.")
                                    stopTrackingForRoute(routeId, cancelNotification = true)
                                } else {
                                    Log.w(TAG, "⚠️ 자동 알람 ($routeId) 연속 오류 발생. 다음 버스 추적을 위해 서비스 유지.")
                                }
                            }
                        }
                        updateForegroundNotification()
                        delay(30000)
                    }
                }
                Log.i(TAG, "Tracking loop finished for route $routeId")
            } finally {
                val currentTrackingInfo = activeTrackings[routeId]
                if (currentTrackingInfo != null && !currentTrackingInfo.isAutoAlarm) {
                    if (activeTrackings.containsKey(routeId)) {
                        Log.w(TAG, "Tracker coroutine for $routeId ended unexpectedly (scope cancellation?). Triggering cleanup.")
                        stopTrackingForRoute(routeId, cancelNotification = true)
                    }
                } else if (currentTrackingInfo?.isAutoAlarm == true) {
                    Log.d(TAG, "자동 알람 ($routeId) 코루틴 종료. 다음 버스 추적을 위해 서비스 유지.")
                }
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
                    val notificationManager = service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

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
                        service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
                        setInForeground(false)
                        val notificationManager = service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        notificationManager.cancel(ongoingNotificationId)
                        Log.d(TAG, "✅ 모든 추적 종료 - 포그라운드 서비스 중지")
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ 포그라운드 서비스 중지 오류: ${e.message}", e)
                    }
                    service.stopSelf()
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
            service.sendBroadcast(cancellationIntent)
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

    // [ADD] Stop tracking for a specific route (BusAlertService.stopSpecificTracking에서 이관, 2026-07-25)
    fun stopSpecificTracking(routeId: String, busNo: String, stationName: String, shouldRemoveFromList: Boolean = true) {
        Log.d(TAG, "🔔 특정 추적 중지 시작: routeId=$routeId, busNo=$busNo, stationName=$stationName")

        if (!isServiceActiveProvider()) {
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
                    val workManager = androidx.work.WorkManager.getInstance(service)

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
                setAutoAlarmMode(false)
                setAutoAlarmStartTime(0L)

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
            val notificationManagerCompat = NotificationManagerCompat.from(service)
            val systemNotificationManager = service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
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
                    notificationManagerCompat.cancel(autoAlarmNotificationId)
                    systemNotificationManager.cancel(autoAlarmNotificationId)
                    Log.d(TAG, "✅ 자동알람 전용 알림 취소됨: ID=$autoAlarmNotificationId")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 자동알람 전용 알림 취소 실패: ${e.message}")
                }
            }

            // 강제 알림 취소 (로그에서 보인 모든 ID들)
            try {
                val forceIds = listOf(916311223, 954225315, 1, 10000, specificNotificationId, autoAlarmNotificationId, ongoingNotificationId)
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
                    notificationManagerCompat.cancel(ongoingNotificationId)
                    systemNotificationManager.cancel(ongoingNotificationId)

                    // 포그라운드 서비스 강제 중지
                    if (isInForegroundProvider()) {
                        try {
                            service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ stopForeground 실패, 재시도: ${e.message}")
                            try {
                                service.stopForeground(true) // 레거시 방법으로 재시도
                            } catch (e2: Exception) {
                                Log.e(TAG, "❌ stopForeground 완전 실패: ${e2.message}")
                            }
                        }
                        setInForeground(false)
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
                    service.sendBroadcast(cancelAutoAlarmIntent)
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
                     service.stopSelf()
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
                        val workManager = androidx.work.WorkManager.getInstance(service)
                        workManager.cancelAllWorkByTag("autoAlarmTask")
                        workManager.cancelAllWorkByTag("autoAlarm_$busNo")
                        setAutoAlarmMode(false)
                        Log.d(TAG, "⚠️ 오류 복구: 자동알람 WorkManager 작업 취소")
                    } catch (cleanupError: Exception) {
                        Log.e(TAG, "❌ 자동알람 오류 복구 실패: ${cleanupError.message}")
                    }
                }

                monitoringJobs[routeId]?.cancel()
                monitoringJobs.remove(routeId)
                activeTrackings.remove(routeId)
                monitoredRoutes.remove(routeId)
                NotificationManagerCompat.from(service).cancel(generateNotificationId(routeId))
                NotificationManagerCompat.from(service).cancel(autoAlarmNotificationId)
                updateForegroundNotification()
                checkAndStopServiceIfNeeded()
                Log.d(TAG, "⚠️ 오류 복구: 최소한의 정리 작업 완료")
            } catch (cleanupError: Exception) {
                Log.e(TAG, "❌ 오류 복구 실패: ${cleanupError.message}")
            }
        }
    }

    // [ADD] Stop all tracking (BusAlertService.stopAllTracking에서 이관, 2026-07-25)
    fun stopAllTracking() {
        Log.i(TAG, "📱 --- stopAllTracking 시작 ---")

        try {
            // 🛑 서비스 활성화 플래그를 가장 먼저 비활성화 (새로운 요청 차단)
            setServiceActive(false)
            Log.d(TAG, "✅ 서비스 비활성화 플래그 설정")

            // 🛑 사용자 수동 중지 플래그 강화 (이미 설정되어 있지만 재확인)
            if (!isManuallyStoppedByUserProvider()) {
                setManuallyStoppedByUser(true)
                setLastManualStopTime(System.currentTimeMillis())
            }
            Log.w(TAG, "🛑 사용자 수동 중지 플래그 재확인: ${isManuallyStoppedByUserProvider()}")

            // 1. 모니터링 타이머 중지
            stopMonitoringTimer()
            Log.d(TAG, "✅ 모니터링 타이머 중지")

            // 3. TTS 추적 완전 중지
            stopTtsTrackingFn(true)
            Log.d(TAG, "✅ TTS 추적 중지")

            // 4. 자동 알람 WorkManager 작업 강력 취소
            try {
                val workManager = androidx.work.WorkManager.getInstance(service)

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
                setAutoAlarmMode(false)
                setAutoAlarmStartTime(0L)

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
                if (isInForegroundProvider()) {
                    service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
                    setInForeground(false)
                    Log.d(TAG, "✅ 포그라운드 서비스 중지 완료")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ 포그라운드 서비스 중지 오류: ${e.message}")
            }

            // 9. 모든 알림 강력 취소 (다단계 시도)
            Log.d(TAG, "🔔 알림 강력 취소 시작")
            try {
                val notificationManager = service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                // 9.1. 즉시 취소
                notificationManager.cancelAll()
                notificationManager.cancel(ongoingNotificationId)
                notificationManager.cancel(autoAlarmNotificationId)

                // 9.2. NotificationManagerCompat으로도 취소
                val notificationManagerCompat = NotificationManagerCompat.from(service)
                notificationManagerCompat.cancelAll()
                notificationManagerCompat.cancel(ongoingNotificationId)
                notificationManagerCompat.cancel(autoAlarmNotificationId)

                Log.d(TAG, "✅ 즉시 알림 취소 완료")

            } catch (e: Exception) {
                Log.e(TAG, "❌ 알림 취소 오류: ${e.message}")
            }

            // 10. 인스턴스 및 서비스 완전 정리
            try {
                clearInstance()
                service.stopSelf()
                Log.d(TAG, "✅ 서비스 인스턴스 정리 및 중지 요청 완료")
            } catch (e: Exception) {
                Log.e(TAG, "❌ 서비스 중지 오류: ${e.message}")
            }

            Log.i(TAG, "✅✅✅ stopAllTracking 완료 - 강력한 정리 작업 완료! ✅✅✅")
            Log.i(TAG, "✅ 사용자 수동 중지 상태: ${isManuallyStoppedByUserProvider()}")
            Log.i(TAG, "✅ 서비스 활성 상태: ${isServiceActiveProvider()}")
            Log.i(TAG, "✅ 남은 추적: ${activeTrackings.size}개, 모니터링 작업: ${monitoringJobs.size}개")

        } catch (e: Exception) {
            Log.e(TAG, "❌ stopAllTracking 중 오류 발생: ${e.message}", e)
            try {
                Log.w(TAG, "⚠️ 긴급 복구 시작: 최소한의 정리 작업 수행")

                // 긴급 정리
                setServiceActive(false)
                setManuallyStoppedByUser(true)
                setLastManualStopTime(System.currentTimeMillis())

                monitoringJobs.clear()
                activeTrackings.clear()
                monitoredRoutes.clear()

                val notificationManager = service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancelAll()

                if (isInForegroundProvider()) {
                    service.stopForeground(Service.STOP_FOREGROUND_REMOVE)
                    setInForeground(false)
                }

                clearInstance()
                service.stopSelf()

                Log.w(TAG, "⚠️ 긴급 복구 완료")
            } catch (cleanupError: Exception) {
                Log.e(TAG, "❌ 긴급 복구 실패: ${cleanupError.message}")
            }
        }
    }
}
