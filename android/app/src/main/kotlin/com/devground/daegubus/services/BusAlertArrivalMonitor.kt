package com.devground.daegubus.services

import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.devground.daegubus.models.BusInfo
import com.devground.daegubus.utils.NotificationHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * 추적 중인 버스 정보 갱신, 도착 임박 판정, TTS·알림 갱신을 담당한다.
 * 추적 작업의 생성·중지와 공유 상태의 수명주기는 BusAlertTrackingManager가 소유한다.
 */
internal class BusAlertArrivalMonitor(
    private val busApiService: BusApiService,
    private val serviceScope: CoroutineScope,
    private val activeTrackings: MutableMap<String, TrackingInfo>,
    private val showOngoing: (String, String, Int, String, String?, String?) -> Unit,
    private val updateForegroundNotification: () -> Unit,
    private val ttsController: BusAlertTtsController,
    private val useTextToSpeechProvider: () -> Boolean,
    private val arrivalThresholdMinutes: Int,
    private val service: Service,
    private val hasNotifiedArrival: MutableSet<String>,
    private val ongoingNotificationId: Int,
    private val notificationHandler: NotificationHandler,
    private val isManuallyStoppedByUserProvider: () -> Boolean,
    private val setManuallyStoppedByUser: (Boolean) -> Unit,
    private val setLastManualStopTime: (Long) -> Unit,
    private val lastManualStopTimeProvider: () -> Long,
    private val restartPreventionDurationMs: Long,
    private val alertOnArrivalOnlyProvider: () -> Boolean,
    private val stopTrackingForRoute: (String, Boolean) -> Unit,
) {
    companion object {
        private const val TAG = "BusAlertService"
        private const val MAX_CONSECUTIVE_ERRORS = 3
    }

    // 버스 업데이트 함수 개선 — BusAlertService.updateBusInfo에서 이관 (2026-07-28, 1b-3)
    fun updateBusInfo(routeId: String, stationId: String, stationName: String) {
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
                                showOngoing(trackingInfo.busNo, stationName, remainingMinutes, firstBus.currentStation, routeId, null)
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
                                stopTrackingForRoute(routeId, true)
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

    // Flutter에서 버스 정보 업데이트 수신 (공개 함수) — BusAlertService.updateBusInfoFromFlutter에서
    // 이관 (2026-07-28, 1b-3). Public 시그니처는 BusApiChannelHandler가 호출하므로
    // BusAlertService에 위임 스텁 유지.
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

    // [추가] 다음 버스로 전환되었는지 확인하고 TTS 안내 — BusAlertService.checkNextBusAndNotify에서
    // 이관 (2026-07-28, 1b-3)
    fun checkNextBusAndNotify(trackingInfo: TrackingInfo, newBusInfo: BusInfo) {
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

            if (useTextToSpeechProvider()) {
                val ttsMessage = "다음 버스, 약 ${newMinutes}분 후 도착"
                val isReturnAlarm = trackingInfo.isAutoAlarm && !trackingInfo.isCommuteAlarm
                ttsController.speakTts(ttsMessage, earphoneOnly = isReturnAlarm, forceSpeaker = trackingInfo.isCommuteAlarm)
                Log.d(TAG, "[TTS] 다음 버스 안내: $ttsMessage")

                // 안내 상태 업데이트
                trackingInfo.lastTtsAnnouncedMinutes = newMinutes
                trackingInfo.lastTtsAnnouncedStation = newBusInfo.currentStation
            }
        }
    }

    // BusAlertService.checkArrivalAndNotify에서 이관 (2026-07-28, 1b-3)
    fun checkArrivalAndNotify(trackingInfo: TrackingInfo, busInfo: BusInfo) {
        // Check if the bus is out of service
        if (busInfo.isOutOfService || busInfo.estimatedTime == "운행종료") {
            Log.d(TAG, "버스 운행종료 상태입니다. 알림을 표시하지 않습니다: ${trackingInfo.busNo}번")
            return
        }

        // Log current time but don't restrict notifications
        val currentHour = java.util.Calendar.getInstance().get(java.util.Calendar.HOUR_OF_DAY)
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
                remainingMinutes >= 0 && remainingMinutes <= arrivalThresholdMinutes
            alertOnArrivalOnlyProvider() -> {
                val stops = busInfo.remainingStops.toIntOrNull() ?: 99
                // "전"/"도착"/"출발" 같은 상태 문자열이 remainingMinutes=0으로 잘못 매핑되는 것을 방지
                // 시간 기반 조건은 실제 분 단위 데이터("N분", "곧 도착")에만 적용
                val isTimeBasedClose = busInfo.estimatedTime == "곧 도착" ||
                    (busInfo.estimatedTime.contains("분") && remainingMinutes in 0..3)
                stops < 3 || isTimeBasedClose
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

                // 퇴근 알람: 이어폰 연결 시 이어폰으로만 TTS, 미연결 시 노티알림만
                val isReturnAlarm = trackingInfo.isAutoAlarm && !trackingInfo.isCommuteAlarm

                if (isReturnAlarm && !ttsController.isHeadsetConnected()) {
                    // 퇴근 알람 + 이어폰 미연결: 노티알림만 (진동/TTS 없음)
                    Log.d(TAG, "📵 퇴근 알람: 이어폰 미연결 → 노티알림만 (진동/TTS 없음)")
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
                            isAutoAlarm = trackingInfo.isAutoAlarm,
                            isCommuteAlarm = trackingInfo.isCommuteAlarm
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
                        ttsController.speakTts(message, earphoneOnly = isReturnAlarm, forceSpeaker = forceSpeaker)

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

    // BusAlertService.updateTrackingInfoFromFlutter에서 이관 (2026-07-28, 1b-3). Public
    // 시그니처는 BusTrackingChannelHandler가 호출하므로 BusAlertService에 위임 스텁 유지.
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
            if (isManuallyStoppedByUserProvider()) {
                val timeSinceStop = System.currentTimeMillis() - lastManualStopTimeProvider()
                if (timeSinceStop < restartPreventionDurationMs) {
                    Log.w(TAG, "🛑 User manually stopped ${timeSinceStop / 1000}sec ago - rejecting updateTrackingInfoFromFlutter: $busNo")
                    return
                } else {
                    // 30초가 지났으면 플래그 해제
                    setManuallyStoppedByUser(false)
                    setLastManualStopTime(0L)
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
            showOngoing(busNo, stationName, remainingMinutes, currentStation, routeId, null)

            // 4. 메인 스레드에서 알림 강제 업데이트 (추가)
            Handler(Looper.getMainLooper()).post {
                try {
                    val notification = notificationHandler.buildOngoingNotification(activeTrackings)
                    val notificationManager = service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.notify(ongoingNotificationId, notification)
                    Log.d(TAG, "✅ 메인 스레드에서 알림 강제 업데이트 완료: ${System.currentTimeMillis()}")
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 메인 스레드 알림 업데이트 오류: ${e.message}", e)
                }
            }

            // 5. 1초 후 다시 한번 업데이트 (지연 백업)
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    val notification = notificationHandler.buildOngoingNotification(activeTrackings)
                    val notificationManager = service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.notify(ongoingNotificationId, notification)
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
}
