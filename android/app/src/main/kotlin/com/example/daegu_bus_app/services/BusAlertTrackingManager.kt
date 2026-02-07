package com.example.daegu_bus_app.services

import android.util.Log
import com.example.daegu_bus_app.models.BusInfo
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
    private val stopTrackingForRoute: (String, Boolean) -> Unit,
    private val ttsController: BusAlertTtsController,
    private val useTextToSpeechProvider: () -> Boolean,
    private val arrivalThresholdMinutes: Int,
) {
    companion object {
        private const val TAG = "BusAlertService"
    }

    suspend fun startTrackingInternal(
        routeId: String,
        stationId: String,
        stationName: String,
        busNo: String,
        isAutoAlarm: Boolean = false,
        alarmId: Int? = null,
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
                                    stopTrackingForRoute(routeId, true)
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
                        stopTrackingForRoute(routeId, true)
                    }
                } else if (currentTrackingInfo?.isAutoAlarm == true) {
                    Log.d(TAG, "자동 알람 ($routeId) 코루틴 종료. 다음 버스 추적을 위해 서비스 유지.")
                }
            }
        }
    }
}
