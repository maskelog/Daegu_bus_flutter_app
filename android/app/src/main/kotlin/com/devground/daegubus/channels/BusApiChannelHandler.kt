package com.devground.daegubus.channels

import com.devground.daegubus.MainActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * com.devground.daegubus/bus_api 채널의 단일 진입점.
 * 메서드 이름을 책임별 operation으로 라우팅하고 알 수 없는 호출만 직접 거절한다.
 */
class BusApiChannelHandler(activity: MainActivity) : MethodChannel.MethodCallHandler {

    private val trackingOperations = BusApiTrackingOperations(activity)
    private val queryOperations = BusApiQueryOperations(activity)
    private val alarmOperations = BusApiAlarmOperations(activity)
    private val ttsOperations = BusApiTtsOperations(activity)

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // --- 추적 제어 ---
            "cancelAlarmNotification" -> trackingOperations.cancelAlarmNotification(call, result)
            "forceStopTracking" -> trackingOperations.forceStopTracking(result)
            "startBusMonitoring" -> trackingOperations.startBusMonitoring(call, result)
            "stopBusTracking" -> trackingOperations.stopBusTracking(call, result)
            "startBusMonitoringService" -> trackingOperations.startBusMonitoringService(call, result)
            "stopBusMonitoringService" -> trackingOperations.stopBusMonitoringService(result)
            "cancelAlarmByRoute" -> trackingOperations.cancelAlarmByRoute(call, result)
            "stopStationTracking" -> trackingOperations.stopStationTracking(result)
            "stopAutoAlarm" -> trackingOperations.stopAutoAlarm(call, result)
            "cancelOngoingTracking" -> trackingOperations.cancelOngoingTracking(result)
            "cancelAllNotifications" -> trackingOperations.cancelAllNotifications(result)
            "stopSpecificTracking" -> trackingOperations.stopSpecificTracking(call, result)
            "stopAllBusTracking" -> trackingOperations.stopAllBusTracking(result)
            "updateBusTrackingNotification" -> trackingOperations.updateBusTrackingNotification(call, result)
            "updateBusInfo" -> trackingOperations.updateBusInfo(call, result)
            "registerBusArrivalReceiver" -> trackingOperations.registerBusArrivalReceiver(result)

            // --- 조회 (DB/웹 API) ---
            "searchStations" -> queryOperations.searchStations(call, result)
            "findNearbyStations" -> queryOperations.findNearbyStations(call, result)
            "getBusRouteDetails" -> queryOperations.getBusRouteDetails(call, result)
            "searchBusRoutes" -> queryOperations.searchBusRoutes(call, result)
            "getStationIdFromBsId" -> queryOperations.getStationIdFromBsId(call, result)
            "getStationInfo" -> queryOperations.getStationInfo(call, result)
            "getBusArrivalByRouteId" -> queryOperations.getBusArrivalByRouteId(call, result)
            "getBusRouteInfo" -> queryOperations.getBusRouteInfo(call, result)
            "getBusPositionInfo" -> queryOperations.getBusPositionInfo(call, result)
            "getRouteStations" -> queryOperations.getRouteStations(call, result)

            // --- 알림·자동알람 ---
            "showNotification" -> alarmOperations.showNotification(call, result)
            "startAutoAlarmNow" -> alarmOperations.startAutoAlarmNow(call, result)
            "cancelNativeAutoAlarm" -> alarmOperations.cancelNativeAutoAlarm(call, result)
            "scheduleNativeAlarm" -> alarmOperations.scheduleNativeAlarm(call, result)

            // --- TTS ---
            "startTtsTracking" -> ttsOperations.startTtsTracking(call, result)
            "speakTTS" -> ttsOperations.speakTTS(call, result)
            "setAudioOutputMode" -> ttsOperations.setAudioOutputMode(call, result)
            "setVolume" -> ttsOperations.setVolume(call, result)
            "stopTTS" -> ttsOperations.stopTTS(result)
            "isHeadphoneConnected" -> ttsOperations.isHeadphoneConnected(result)
            else -> result.notImplemented()
        }
    }
}
