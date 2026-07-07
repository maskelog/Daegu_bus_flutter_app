package com.devground.daegubus.channels

import android.content.Intent
import android.os.Build
import android.os.Handler
import android.util.Log
import com.devground.daegubus.MainActivity
import com.devground.daegubus.services.BusAlertService
import com.devground.daegubus.services.StationTrackingService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * com.devground.daegubus/bus_tracking 채널 핸들러.
 * 버스 추적 알림 업데이트·추적 중지·정류장 추적 시작/중지·자동알람 중지를 담당한다.
 */
class BusTrackingChannelHandler(private val activity: MainActivity) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "BusTrackingChannel"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "BUS_TRACKING_CHANNEL 호출: ${call.method}")
        when (call.method) {
            "updateBusTrackingNotification" -> updateBusTrackingNotification(call, result)
            "stopBusTracking" -> stopBusTracking(call, result)
            "startStationTracking" -> startStationTracking(call, result)
            "stopStationTracking" -> stopStationTracking(result)
            "stopAutoAlarm" -> stopAutoAlarm(call, result)
            else -> result.notImplemented()
        }
    }

    private fun updateBusTrackingNotification(call: MethodCall, result: MethodChannel.Result) {
        val busNo = call.argument<String>("busNo") ?: ""
        val stationName = call.argument<String>("stationName") ?: ""
        val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
        val currentStation = call.argument<String>("currentStation") ?: ""
        val routeId = call.argument<String>("routeId") ?: ""

        try {
            Log.d(TAG, "Flutter에서 버스 추적 알림 업데이트 요청 (BUS_TRACKING_CHANNEL): $busNo, 남은 시간: ${remainingMinutes}분, 현재 위치: $currentStation")

            // 여러 방법으로 알림 업데이트 시도 (병렬 실행)

            // 1. BusAlertService를 통해 알림 업데이트 (직접 메서드 호출)
            val busAlertService = activity.busAlertService
            if (busAlertService != null) {
                // 1.1. updateTrackingNotification 메서드 직접 호출 (가장 확실한 방법)
                busAlertService.updateTrackingNotification(
                    busNo = busNo,
                    stationName = stationName,
                    remainingMinutes = remainingMinutes,
                    currentStation = currentStation,
                    routeId = routeId
                )
                Log.d(TAG, "🚌 업데이트 완료 - 버스 $busNo, 현재 위치: $currentStation")

                // 1.2. updateTrackingInfoFromFlutter 메서드 직접 호출 (백업)
                busAlertService.updateTrackingInfoFromFlutter(
                    routeId = routeId,
                    busNo = busNo,
                    stationName = stationName,
                    remainingMinutes = remainingMinutes,
                    currentStation = currentStation
                )

                // 1.3. showOngoingBusTracking 메서드 직접 호출 (추가 백업)
                busAlertService.showOngoingBusTracking(
                    busNo = busNo,
                    stationName = stationName,
                    remainingMinutes = remainingMinutes,
                    currentStation = currentStation,
                    isUpdate = true,
                    notificationId = BusAlertService.ONGOING_NOTIFICATION_ID,
                    allBusesSummary = null,
                    routeId = routeId
                )

                Log.d(TAG, "✅ 버스 추적 알림 직접 메서드 호출 완료")
            }

            // 2. 인텐트를 통한 업데이트 (서비스가 null이거나 직접 호출이 실패한 경우를 대비)
            // 2.1. ACTION_UPDATE_TRACKING 인텐트 전송
            val updateIntent = Intent(activity, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_UPDATE_TRACKING
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("remainingMinutes", remainingMinutes)
                putExtra("currentStation", currentStation)
                putExtra("routeId", routeId)
            }

            // Android 버전에 따라 적절한 방법으로 서비스 시작
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.startForegroundService(updateIntent)
            } else {
                activity.startService(updateIntent)
            }
            Log.d(TAG, "✅ 버스 추적 알림 업데이트 인텐트 전송 완료")

            // 3. BusAlertService가 null인 경우 서비스 시작 및 바인딩 시도
            if (activity.busAlertService == null) {
                activity.startAndBindBusAlertService()
            }

            // 4. 1초 후 지연 업데이트 시도 (백업)
            Handler(activity.mainLooper).postDelayed({
                try {
                    // 지연 인텐트 전송
                    val delayedIntent = Intent(activity, BusAlertService::class.java).apply {
                        action = BusAlertService.ACTION_UPDATE_TRACKING
                        putExtra("busNo", busNo)
                        putExtra("stationName", stationName)
                        putExtra("remainingMinutes", remainingMinutes)
                        putExtra("currentStation", currentStation)
                        putExtra("routeId", routeId)
                    }
                    activity.startService(delayedIntent)
                    Log.d(TAG, "✅ 지연 업데이트 인텐트 전송 완료")

                    // 서비스가 초기화되었으면 직접 메서드 호출도 시도
                    if (activity.busAlertService != null) {
                        activity.busAlertService?.updateTrackingNotification(
                            busNo = busNo,
                            stationName = stationName,
                            remainingMinutes = remainingMinutes,
                            currentStation = currentStation,
                            routeId = routeId
                        )
                        Log.d(TAG, "✅ 지연 직접 메서드 호출 완료")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "❌ 지연 업데이트 오류: ${e.message}", e)
                }
            }, 1000)

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "❌ 버스 추적 알림 업데이트 오류: ${e.message}", e)

            // 오류 발생 시에도 인텐트 전송 시도 (최후의 수단)
            try {
                val fallbackIntent = Intent(activity, BusAlertService::class.java).apply {
                    action = BusAlertService.ACTION_UPDATE_TRACKING
                    putExtra("busNo", busNo)
                    putExtra("stationName", stationName)
                    putExtra("remainingMinutes", remainingMinutes)
                    putExtra("currentStation", currentStation)
                    putExtra("routeId", routeId)
                }
                activity.startService(fallbackIntent)
                Log.d(TAG, "✅ 오류 후 인텐트 전송 완료")
                result.success(true)
            } catch (ex: Exception) {
                Log.e(TAG, "❌ 오류 후 인텐트 전송 실패: ${ex.message}", ex)
                result.error("UPDATE_ERROR", "버스 추적 알림 업데이트 실패: ${e.message}", null)
            }
        }
    }

    private fun stopBusTracking(call: MethodCall, result: MethodChannel.Result) {
        val busNo = call.argument<String>("busNo") ?: ""
        val routeId = call.argument<String>("routeId") ?: ""
        val stationId = call.argument<String>("stationId") ?: ""
        val stationName = call.argument<String>("stationName") ?: ""
        try {
            Log.i(TAG, "버스 추적 중지 요청 (BUS_TRACKING_CHANNEL): Bus=$busNo, Route=$routeId, Station=$stationName")

            // stopTrackingForRoute만 호출 (내부에서 알림 취소 처리)
            activity.busAlertService?.stopTrackingForRoute(routeId, stationId, busNo)

            // Flutter 측에 알림 취소 이벤트 전송
            try {
                val alarmCancelData = mapOf(
                    "busNo" to busNo,
                    "routeId" to routeId,
                    "stationName" to stationName
                )
                activity._methodChannel?.invokeMethod("onAlarmCanceledFromNotification", alarmCancelData)
                Log.i(TAG, "Flutter 측에 알람 취소 알림 전송 완료: $busNo, $routeId")
            } catch (e: Exception) {
                Log.e(TAG, "Flutter 측에 알람 취소 알림 전송 오류: ${e.message}")
            }

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "버스 추적 중지 오류: ${e.message}", e)
            result.error("STOP_ERROR", "버스 추적 중지 실패: ${e.message}", null)
        }
    }

    private fun startStationTracking(call: MethodCall, result: MethodChannel.Result) {
        val stationId = call.argument<String>("stationId")
        val stationName = call.argument<String>("stationName")
        if (stationId.isNullOrEmpty() || stationName.isNullOrEmpty()) {
            Log.e(TAG, "startStationTracking 오류: stationId 또는 stationName 누락")
            result.error("INVALID_ARGUMENT", "Station ID 또는 Station Name이 누락되었습니다.", null)
            return
        }
        try {
            val intent = Intent(activity, StationTrackingService::class.java).apply {
                action = StationTrackingService.ACTION_START_TRACKING
                putExtra(StationTrackingService.EXTRA_STATION_ID, stationId)
                putExtra(StationTrackingService.EXTRA_STATION_NAME, stationName)
            }
            // Foreground 서비스 시작 방식 사용 고려 (Android 8 이상)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.startForegroundService(intent)
            } else {
                activity.startService(intent)
            }
            Log.i(TAG, "StationTrackingService 시작 요청: $stationId ($stationName)")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "StationTrackingService 시작 오류: ${e.message}", e)
            result.error("SERVICE_ERROR", "StationTrackingService 시작 중 오류 발생: ${e.message}", null)
        }
    }

    private fun stopStationTracking(result: MethodChannel.Result) {
        try {
            Log.i(TAG, "StationTrackingService 중지 요청 받음")
            val intent = Intent(activity, StationTrackingService::class.java).apply {
                action = StationTrackingService.ACTION_STOP_TRACKING
            }
            activity.startService(intent)
            Log.i(TAG, "StationTrackingService 중지 명령 전송 완료")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "StationTrackingService 중지 오류: ${e.message}", e)
            result.error("SERVICE_ERROR", "StationTrackingService 중지 중 오류 발생: ${e.message}", null)
        }
    }

    private fun stopAutoAlarm(call: MethodCall, result: MethodChannel.Result) {
        val busNo = call.argument<String>("busNo") ?: ""
        val stationName = call.argument<String>("stationName") ?: ""
        val routeId = call.argument<String>("routeId") ?: ""

        try {
            Log.i(TAG, "자동알람 중지 요청 (stopAutoAlarm): Bus=$busNo, Station=$stationName, Route=$routeId")

            // BusAlertService의 stopAllBusTracking 호출하여 모든 추적 중지
            activity.busAlertService?.stopAllBusTracking()
            Log.i(TAG, "✅ BusAlertService.stopAllBusTracking() 호출 완료")

            // Flutter 측에 자동알람 중지 완료 이벤트 전송
            try {
                val autoAlarmCancelData = mapOf(
                    "busNo" to busNo,
                    "stationName" to stationName,
                    "routeId" to routeId,
                    "isAutoAlarm" to true
                )
                activity._methodChannel?.invokeMethod("onAutoAlarmStopped", autoAlarmCancelData)
                Log.i(TAG, "✅ Flutter 측에 자동알람 중지 이벤트 전송 완료")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Flutter 측 자동알람 중지 이벤트 전송 오류: ${e.message}")
            }

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "❌ 자동알람 중지 오류: ${e.message}", e)
            result.error("STOP_AUTO_ALARM_ERROR", "자동알람 중지 실패: ${e.message}", null)
        }
    }
}
