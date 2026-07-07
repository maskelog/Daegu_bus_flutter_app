package com.devground.daegubus.channels

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.database.sqlite.SQLiteException
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.devground.daegubus.MainActivity
import com.devground.daegubus.R
import com.devground.daegubus.services.BusAlertService
import com.devground.daegubus.services.StationTrackingService
import com.devground.daegubus.services.TTSService
import com.devground.daegubus.utils.AutoAlarmScheduleCalculator
import com.devground.daegubus.utils.DatabaseHelper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject

/**
 * com.devground.daegubus/bus_api 채널 핸들러 (메인 채널).
 * 정류장/노선 조회, 버스 추적 시작·중지, 알림 표시, 네이티브 자동알람 예약, TTS 위임을 담당한다.
 */
class BusApiChannelHandler(private val activity: MainActivity) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "BusApiChannel"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // --- 추적 제어 ---
            "cancelAlarmNotification" -> cancelAlarmNotification(call, result)
            "forceStopTracking" -> forceStopTracking(result)
            "startBusMonitoring" -> startBusMonitoring(call, result)
            "stopBusTracking" -> stopBusTracking(call, result)
            "startBusMonitoringService" -> startBusMonitoringService(call, result)
            "stopBusMonitoringService" -> stopBusMonitoringService(result)
            "cancelAlarmByRoute" -> cancelAlarmByRoute(call, result)
            "stopStationTracking" -> stopStationTracking(result)
            "stopAutoAlarm" -> stopAutoAlarm(call, result)
            "cancelOngoingTracking" -> cancelOngoingTracking(result)
            "cancelAllNotifications" -> cancelAllNotifications(result)
            "stopSpecificTracking" -> stopSpecificTracking(call, result)
            "stopAllBusTracking" -> stopAllBusTracking(result)
            "updateBusTrackingNotification" -> updateBusTrackingNotification(call, result)
            "updateBusInfo" -> updateBusInfo(call, result)
            "registerBusArrivalReceiver" -> registerBusArrivalReceiver(result)
            // --- 조회 (DB/웹 API) ---
            "searchStations" -> searchStations(call, result)
            "findNearbyStations" -> findNearbyStations(call, result)
            "getBusRouteDetails" -> getBusRouteDetails(call, result)
            "searchBusRoutes" -> searchBusRoutes(call, result)
            "getStationIdFromBsId" -> getStationIdFromBsId(call, result)
            "getStationInfo" -> getStationInfo(call, result)
            "getBusArrivalByRouteId" -> getBusArrivalByRouteId(call, result)
            "getBusRouteInfo" -> getBusRouteInfo(call, result)
            "getBusPositionInfo" -> getBusPositionInfo(call, result)
            "getRouteStations" -> getRouteStations(call, result)
            // --- 알림·자동알람 ---
            "showNotification" -> showNotification(call, result)
            "startAutoAlarmNow" -> startAutoAlarmNow(call, result)
            "cancelNativeAutoAlarm" -> cancelNativeAutoAlarm(call, result)
            "scheduleNativeAlarm" -> scheduleNativeAlarm(call, result)
            // --- TTS ---
            "startTtsTracking" -> startTtsTracking(call, result)
            "speakTTS" -> speakTTS(call, result)
            "setAudioOutputMode" -> setAudioOutputMode(call, result)
            "setVolume" -> setVolume(call, result)
            "stopTTS" -> stopTTS(result)
            "isHeadphoneConnected" -> isHeadphoneConnected(result)
            else -> result.notImplemented()
        }
    }

    // ------------------------------------------------------------------
    // 추적 제어
    // ------------------------------------------------------------------

    private fun cancelAlarmNotification(call: MethodCall, result: MethodChannel.Result) {
        val routeId = call.argument<String>("routeId") ?: ""
        val busNo = call.argument<String>("busNo") ?: ""
        val stationName = call.argument<String>("stationName") ?: ""

        try {
            Log.i(TAG, "Flutter에서 알람/추적 중지 요청: Bus=$busNo, Route=$routeId, Station=$stationName")

            if (activity.busAlertService != null) {
                // Call stopTrackingForRoute, which handles notification update/cancellation internally.
                // The 'true' for cancelNotification ensures it tries to affect notifications.
                activity.busAlertService?.stopTrackingForRoute(routeId, busNo, stationName, true)
                Log.i(TAG, "BusAlertService.stopTrackingForRoute 호출 완료: $routeId")
            } else {
                // BusAlertService가 null인 경우, 서비스에 인텐트를 보내 중지 시도
                try {
                    val serviceIntent = Intent(activity, BusAlertService::class.java)
                    serviceIntent.action = BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
                    serviceIntent.putExtra("routeId", routeId)
                    serviceIntent.putExtra("busNo", busNo)
                    serviceIntent.putExtra("stationName", stationName)
                    activity.startService(serviceIntent)
                    Log.i(TAG, "BusAlertService로 특정 노선 추적 중지 인텐트 전송 (서비스 null)")
                } catch (e: Exception) {
                    Log.e(TAG, "BusAlertService 초기화 실패: ${e.message}", e)
                }

                // 직접 서비스 인텐트를 보내서 중지 시도
                val stopIntent = Intent(activity, BusAlertService::class.java).apply {
                    action = BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
                    putExtra("routeId", routeId) // routeId is primary key for tracking
                    putExtra("busNo", busNo)
                    putExtra("stationName", stationName)
                }
                activity.startService(stopIntent)
                Log.i(TAG, "특정 노선 추적 중지 인텐트 전송 완료 (서비스 null, 백업)")
            }

            // NotificationHandler를 사용하여 알림 취소 (백업 방법, 브로드캐스트 없이)
            activity.notificationHandler.cancelBusTrackingNotification(routeId, busNo, stationName, false)
            Log.i(TAG, "NotificationHandler를 통한 알림 취소 완료 (브로드캐스트 없이)")

            // Flutter 측에 알림 취소 완료 이벤트 전송
            val alarmCancelData = mapOf(
                "busNo" to busNo,
                "routeId" to routeId,
                "stationName" to stationName
            )
            activity._methodChannel?.invokeMethod("onAlarmCanceledFromNotification", alarmCancelData)
            Log.i(TAG, "Flutter 측에 알람 취소 알림 전송 완료 (From cancelAlarmNotification handler)")

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "알람/추적 중지 처리 오류: ${e.message}", e)

            // 오류 발생 시에도 Flutter 측에 이벤트는 전송 시도
            try {
                val alarmCancelData = mapOf(
                    "busNo" to busNo,
                    "routeId" to routeId,
                    "stationName" to stationName
                )
                activity._methodChannel?.invokeMethod("onAlarmCanceledFromNotification", alarmCancelData)
            } catch (ex: Exception) {
                Log.e(TAG, "오류 후 알림 취소 시도 실패: ${ex.message}", ex)
            }

            result.error("CANCEL_ERROR", "알람/추적 중지 처리 실패: ${e.message}", null)
        }
    }

    private fun forceStopTracking(result: MethodChannel.Result) {
        try {
            Log.i(TAG, "Flutter에서 강제 전체 추적 중지 요청 받음")
            // WorkManager의 모든 작업 취소
            val workManager = androidx.work.WorkManager.getInstance(activity.applicationContext)
            workManager.cancelAllWork()
            Log.i(TAG, "WorkManager의 모든 작업 취소 완료")

            // Call the comprehensive stopAllBusTracking method in BusAlertService
            activity.busAlertService?.stopAllBusTracking()
            Log.i(TAG, "BusAlertService.stopAllBusTracking() 호출 완료")

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "강제 전체 추적 중지 처리 오류: ${e.message}", e)
            result.error("FORCE_STOP_ERROR", "강제 전체 추적 중지 처리 실패: ${e.message}", null)
        }
    }

    private fun startBusMonitoring(call: MethodCall, result: MethodChannel.Result) {
        val routeId = call.argument<String>("routeId")
        val stationId = call.argument<String>("stationId")
        val stationName = call.argument<String>("stationName")
        try {
            activity.busAlertService?.addMonitoredRoute(routeId!!, stationId!!, stationName!!)
            result.success("추적 시작됨")
        } catch (e: Exception) {
            Log.e(TAG, "버스 추적 시작 오류: ${e.message}", e)
            result.error("MONITOR_ERROR", "버스 추적 실패: ${e.message}", null)
        }
    }

    private fun stopBusTracking(call: MethodCall, result: MethodChannel.Result) {
        val busNo = call.argument<String>("busNo") ?: ""
        val routeId = call.argument<String>("routeId") ?: ""
        val stationId = call.argument<String>("stationId") ?: ""
        val stationName = call.argument<String>("stationName") ?: ""
        try {
            Log.i(TAG, "버스 추적 중지 요청: Bus=$busNo, Route=$routeId, Station=$stationName")

            // 1. 포그라운드 알림 취소
            activity.busAlertService?.cancelOngoingTracking()

            // 2. 추적 중지
            activity.busAlertService?.stopTrackingForRoute(routeId, stationId, busNo)

            // 3. Flutter 측에 알림 취소 이벤트 전송
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

    private fun startBusMonitoringService(call: MethodCall, result: MethodChannel.Result) {
        val routeId = call.argument<String>("routeId") ?: ""
        var stationId = call.argument<String>("stationId") ?: ""
        val stationName = call.argument<String>("stationName") ?: ""
        val busNo = call.argument<String>("busNo") ?: ""

        try {
            Log.i(TAG, "버스 모니터링 서비스 시작 요청: Bus=$busNo, Route=$routeId, Station=$stationName")

            if (routeId.isEmpty() || stationName.isEmpty() || busNo.isEmpty()) {
                result.error("INVALID_ARGUMENT", "필수 인자가 누락되었습니다", null)
                return
            }

            // stationId 보정 - 빈 값으로 설정하여 BusAlertService에서 자동 해결하도록 함
            if (stationId.isEmpty() || stationId == routeId) {
                stationId = ""
                Log.d(TAG, "stationId 보정: $stationName → BusAlertService에서 자동 해결")
            }

            // 1. 모니터링 노선 추가
            activity.busAlertService?.addMonitoredRoute(routeId, stationId, stationName)

            // 2. 포그라운드 서비스 시작
            val intent = Intent(activity, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_START_TRACKING_FOREGROUND
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("stationName", stationName)
                putExtra("busNo", busNo)
                putExtra("remainingMinutes", 5) // 기본값
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.startForegroundService(intent)
                Log.i(TAG, "버스 모니터링 서비스 시작됨 (startForegroundService)")
            } else {
                activity.startService(intent)
                Log.i(TAG, "버스 모니터링 서비스 시작됨 (startService)")
            }

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "버스 모니터링 서비스 시작 오류: ${e.message}", e)
            result.error("SERVICE_ERROR", "버스 모니터링 서비스 시작 실패: ${e.message}", null)
        }
    }

    private fun stopBusMonitoringService(result: MethodChannel.Result) {
        try {
            Log.i(TAG, "버스 모니터링 서비스 중지 요청")

            // BusAlertService의 stopAllBusTracking 호출
            activity.busAlertService?.stopAllBusTracking()

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "버스 모니터링 서비스 중지 오류: ${e.message}", e)
            result.error("STOP_ERROR", "버스 모니터링 서비스 중지 실패: ${e.message}", null)
        }
    }

    private fun cancelAlarmByRoute(call: MethodCall, result: MethodChannel.Result) {
        val busNo = call.argument<String>("busNo")
        val stationName = call.argument<String>("stationName")
        val routeId = call.argument<String>("routeId")

        if (routeId != null) {
            Log.i(TAG, "Flutter에서 알람 취소 요청 받음 (Native Handling): Bus=$busNo, Station=$stationName, Route=$routeId")
            // Intent를 사용하여 서비스에 중지 명령 전달
            val stopIntent = Intent(activity, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
                putExtra("routeId", routeId) // Pass the routeId to stop
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    activity.startForegroundService(stopIntent)
                } else {
                    activity.startService(stopIntent)
                }
                Log.i(TAG, "BusAlertService로 '$routeId' 추적 중지 Intent 전송 완료")
                result.success(true) // Acknowledge the call
            } catch (e: Exception) {
                Log.e(TAG, "BusAlertService로 추적 중지 Intent 전송 실패: ${e.message}", e)
                result.error("SERVICE_START_FAILED", "Failed to send stop command to service.", e.message)
            }
        } else {
            Log.e(TAG, "'cancelAlarmByRoute' 호출 오류: routeId가 null입니다.")
            result.error("INVALID_ARGUMENT", "routeId cannot be null.", null)
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

    private fun cancelOngoingTracking(result: MethodChannel.Result) {
        try {
            Log.i(TAG, "Flutter에서 진행 중 추적 취소 요청 받음")
            activity.busAlertService?.stopAllBusTracking()
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "진행 중 추적 취소 오류: ${e.message}", e)
            result.error("CANCEL_ERROR", "진행 중 추적 취소 실패: ${e.message}", null)
        }
    }

    private fun cancelAllNotifications(result: MethodChannel.Result) {
        try {
            Log.i(TAG, "Flutter에서 모든 알림 취소 요청 받음")
            // BusAlertService에서 모든 추적 중지 (알림, 서비스, TTS 모두 포함)
            activity.busAlertService?.stopAllBusTracking()

            // Flutter 측에 모든 알람 취소 이벤트 전송
            try {
                activity._methodChannel?.invokeMethod("onAllAlarmsCanceled", null)
                Log.i(TAG, "Flutter 측에 모든 알람 취소 알림 전송 완료")
            } catch (e: Exception) {
                Log.e(TAG, "Flutter 측에 모든 알람 취소 알림 전송 오류: ${e.message}")
            }

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "모든 알림 취소 오류: ${e.message}", e)
            result.error("CANCEL_ALL_ERROR", "모든 알림 취소 실패: ${e.message}", null)
        }
    }

    private fun stopSpecificTracking(call: MethodCall, result: MethodChannel.Result) {
        try {
            val busNo = call.argument<String>("busNo") ?: ""
            val routeId = call.argument<String>("routeId") ?: ""
            val stationName = call.argument<String>("stationName") ?: ""

            Log.i(TAG, "Flutter에서 특정 추적 중지 요청: Bus=$busNo, Route=$routeId, Station=$stationName")

            // BusAlertService에서 특정 추적 중지
            if (activity.busAlertService != null) {
                activity.busAlertService?.stopTrackingForRoute(routeId, busNo, stationName, true)
                Log.i(TAG, "BusAlertService 특정 추적 중지 완료: $routeId")
            } else {
                // 서비스가 null인 경우 인텐트로 중지 요청
                val stopIntent = Intent(activity, BusAlertService::class.java).apply {
                    action = BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
                    putExtra("routeId", routeId)
                    putExtra("busNo", busNo)
                    putExtra("stationName", stationName)
                }
                activity.startService(stopIntent)
                Log.i(TAG, "특정 추적 중지 인텐트 전송 완료")
            }

            // Flutter 측에 특정 알람 취소 이벤트 전송
            try {
                val alarmCancelData = mapOf(
                    "busNo" to busNo,
                    "routeId" to routeId,
                    "stationName" to stationName
                )
                activity._methodChannel?.invokeMethod("onAlarmCanceledFromNotification", alarmCancelData)
                Log.i(TAG, "Flutter 측에 특정 알람 취소 알림 전송 완료")
            } catch (e: Exception) {
                Log.e(TAG, "Flutter 특정 알람 취소 알림 전송 오류: ${e.message}")
            }

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "특정 추적 중지 오류: ${e.message}", e)
            result.error("STOP_SPECIFIC_ERROR", "특정 추적 중지 실패: ${e.message}", null)
        }
    }

    private fun stopAllBusTracking(result: MethodChannel.Result) {
        try {
            Log.i(TAG, "모든 버스 추적 중지 요청 수신 (stopAllBusTracking)")
            if (activity.busAlertService != null) {
                activity.busAlertService?.stopAllBusTracking()
            } else {
                // 서비스가 null인 경우 인텐트로 중지 요청
                val intent = Intent(activity, BusAlertService::class.java).apply {
                    action = BusAlertService.ACTION_STOP_TRACKING
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    activity.startForegroundService(intent)
                } else {
                    activity.startService(intent)
                }
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "모든 버스 추적 중지 요청 처리 오류: ${e.message}", e)
            result.error("STOP_ALL_ERROR", "모든 추적 중지 실패", null)
        }
    }

    private fun updateBusTrackingNotification(call: MethodCall, result: MethodChannel.Result) {
        val busNo = call.argument<String>("busNo") ?: ""
        val stationName = call.argument<String>("stationName") ?: ""
        val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
        val currentStation = call.argument<String>("currentStation") ?: ""
        val routeId = call.argument<String>("routeId") ?: ""
        try {
            Log.d(TAG, "Flutter에서 버스 추적 알림 업데이트 요청: $busNo, 남은 시간: $remainingMinutes 분")
            val intent = Intent(activity, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_UPDATE_TRACKING
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("remainingMinutes", remainingMinutes)
                putExtra("currentStation", currentStation)
                putExtra("routeId", routeId)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.startForegroundService(intent)
            } else {
                activity.startService(intent)
            }
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "버스 추적 알림 업데이트 오류: ${e.message}", e)
            result.error("NOTIFICATION_ERROR", "버스 추적 알림 업데이트 중 오류 발생: ${e.message}", null)
        }
    }

    private fun updateBusInfo(call: MethodCall, result: MethodChannel.Result) {
        // Flutter에서 버스 정보 업데이트 수신
        val routeId = call.argument<String>("routeId") ?: ""
        val busNo = call.argument<String>("busNo") ?: ""
        val stationName = call.argument<String>("stationName") ?: ""
        val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
        val currentStation = call.argument<String>("currentStation")
        val estimatedTime = call.argument<String>("estimatedTime")
        val isLowFloor = call.argument<Boolean>("isLowFloor") ?: false

        if (routeId.isEmpty() || busNo.isEmpty() || stationName.isEmpty()) {
            result.error("INVALID_ARGUMENT", "updateBusInfo requires routeId, busNo, stationName", null)
            return
        }

        try {
            Log.d(TAG, "🔄 Flutter에서 버스 정보 업데이트 수신: $busNo, $stationName, ${remainingMinutes}분")

            // BusAlertService에 버스 정보 업데이트 전달
            activity.busAlertService?.updateBusInfoFromFlutter(
                routeId = routeId,
                busNo = busNo,
                stationName = stationName,
                remainingMinutes = remainingMinutes,
                currentStation = currentStation,
                estimatedTime = estimatedTime,
                isLowFloor = isLowFloor
            )

            Log.d(TAG, "✅ BusAlertService에 버스 정보 전달 완료")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "❌ 버스 정보 업데이트 오류: ${e.message}", e)
            result.error("UPDATE_ERROR", "버스 정보 업데이트 실패: ${e.message}", null)
        }
    }

    private fun registerBusArrivalReceiver(result: MethodChannel.Result) {
        try {
            // BusArrivalReceiver registration is not directly available
            // This functionality may need to be implemented differently
            result.success("등록 완료")
        } catch (e: Exception) {
            Log.e(TAG, "BusArrivalReceiver 등록 오류: ${e.message}", e)
            result.error("REGISTER_ERROR", "버스 도착 리시버 등록 실패: ${e.message}", null)
        }
    }

    // ------------------------------------------------------------------
    // 조회 (DB/웹 API)
    // ------------------------------------------------------------------

    private fun searchStations(call: MethodCall, result: MethodChannel.Result) {
        val searchText = call.argument<String>("searchText") ?: ""
        if (searchText.isEmpty()) {
            result.error("INVALID_ARGUMENT", "검색어가 비어있습니다", null)
            return
        }
        val searchType = call.argument<String>("searchType") ?: "web"
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val databaseHelper = DatabaseHelper.getInstance(activity)
                if (searchType == "local") {
                    val stations = databaseHelper.searchStations(searchText)
                    Log.d(TAG, "로컬 정류장 검색 결과: ${stations.size}개")
                    val jsonArray = JSONArray()
                    stations.forEach { station ->
                        val wincId = station.stationId?.takeIf { it.isNotBlank() } ?: station.bsId
                        val jsonObj = JSONObject().apply {
                            put("id", station.bsId)
                            put("name", station.bsNm)
                            put("isFavorite", false)
                            put("wincId", wincId)
                            put("stationId", wincId)
                            put("ngisXPos", station.longitude)
                            put("ngisYPos", station.latitude)
                            put("routeList", JSONArray())
                        }
                        jsonArray.put(jsonObj)
                    }
                    result.success(jsonArray.toString())
                } else {
                    val stations = activity.busApiService.searchStations(searchText)
                    Log.d(TAG, "웹 정류장 검색 결과: ${stations.size}개")
                    val jsonArray = JSONArray()
                    stations.forEach { station ->
                        Log.d(TAG, "Station - ID: ${station.bsId}, Name: ${station.bsNm}")
                        val wincId = databaseHelper.getStationIdByBsId(station.bsId) ?: station.bsId
                        val jsonObj = JSONObject().apply {
                            put("id", station.bsId)
                            put("name", station.bsNm)
                            put("isFavorite", false)
                            put("wincId", wincId)
                            put("stationId", wincId)
                            put("ngisXPos", 0.0)
                            put("ngisYPos", 0.0)
                            put("routeList", JSONArray())
                        }
                        jsonArray.put(jsonObj)
                    }
                    result.success(jsonArray.toString())
                }
            } catch (e: Exception) {
                Log.e(TAG, "정류장 검색 오류: ${e.message}", e)
                result.error("API_ERROR", "정류장 검색 중 오류 발생: ${e.message}", null)
            }
        }
    }

    private fun findNearbyStations(call: MethodCall, result: MethodChannel.Result) {
        val requestTraceId = call.argument<String>("traceId")?.let { input ->
            val trimmed = input.trim()
            if (trimmed.isNotEmpty()) trimmed else null
        } ?: "findNearby_${System.currentTimeMillis()}"

        fun readCoordinate(argumentKey: String): Double? {
            val arg = call.argument<Any>(argumentKey)
            val normalizedString = if (arg is String) arg.trim().replace(",", ".") else null
            return when (arg) {
                is Double -> arg.takeIf { it.isFinite() }
                is Float -> arg.toDouble().takeIf { it.isFinite() }
                is Long -> arg.toDouble()
                is Int -> arg.toDouble()
                is String -> normalizedString?.toDoubleOrNull()?.takeIf { it.isFinite() }
                else -> {
                    Log.w(
                        TAG,
                        "[$requestTraceId] findNearbyStations coord parse failed key=$argumentKey value=$arg type=${arg?.javaClass?.name}",
                    )
                    null
                }
            }
        }

        val traceId = requestTraceId
        val latitude = readCoordinate("latitude")
        val longitude = readCoordinate("longitude")
        val radiusMeters = readCoordinate("radiusMeters")?.takeIf { it > 0 } ?: 500.0

        if (latitude == null || longitude == null) {
            Log.w(TAG, "[$traceId] findNearbyStations invalid coordinates: lat=$latitude, lon=$longitude")
            result.error("INVALID_ARGUMENT", "위도 또는 경도가 유효하지 않습니다", null)
            return
        }

        CoroutineScope(Dispatchers.Main).launch {
            try {
                Log.d(TAG, "[$traceId] 주변 정류장 검색 요청: lat=$latitude, lon=$longitude, radius=${radiusMeters}m")

                val databaseHelper = DatabaseHelper.getInstance(activity)

                fun buildStationJsonArray(stations: List<com.devground.daegubus.models.LocalStationSearchResult>): JSONArray {
                    val jsonArray = JSONArray()
                    stations.forEach { station ->
                        val jsonObj = JSONObject().apply {
                            val wincId = station.stationId ?: station.bsId
                            put("id", wincId)
                            put("name", station.bsNm)
                            put("isFavorite", false)
                            put("wincId", wincId)
                            put("stationId", wincId)
                            put("distance", station.distance)
                            put("ngisXPos", station.longitude)
                            put("ngisYPos", station.latitude)
                            put("routeList", JSONArray())
                        }
                        jsonArray.put(jsonObj)
                    }
                    return jsonArray
                }

                try {
                    val nearbyStations = databaseHelper.searchStations(
                        searchText = "",
                        latitude = latitude,
                        longitude = longitude,
                        radiusInMeters = radiusMeters
                    )

                    Log.d(TAG, "[$traceId] 주변 정류장 검색 완료: ${nearbyStations.size}개 발견 (반경: ${radiusMeters}m)")

                    val jsonArray = buildStationJsonArray(nearbyStations)
                    result.success(jsonArray.toString())
                } catch (e: SQLiteException) {
                    Log.e(TAG, "[$traceId] SQLite 오류 발생, DB 재설치 시도", e)
                    databaseHelper.forceReinstallDatabase()

                    val nearbyStations = databaseHelper.searchStations(
                        searchText = "",
                        latitude = latitude,
                        longitude = longitude,
                        radiusInMeters = radiusMeters
                    )
                    result.success(buildStationJsonArray(nearbyStations).toString())
                }
            } catch (e: Exception) {
                Log.e(TAG, "[$traceId] 주변 정류장 검색 오류: ${e.message}", e)
                result.error("DB_ERROR", "주변 정류장 검색 중 오류 발생: ${e.message}", null)
            }
        }
    }

    private fun getBusRouteDetails(call: MethodCall, result: MethodChannel.Result) {
        val routeId = call.argument<String>("routeId") ?: ""
        if (routeId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "노선 ID가 비어있습니다", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val searchRoutes = activity.busApiService.searchBusRoutes(routeId)
                val routeInfo = activity.busApiService.getBusRouteInfo(routeId)
                val mergedRoute = routeInfo ?: searchRoutes.firstOrNull()
                result.success(activity.busApiService.convertToJson(mergedRoute ?: "{}"))
            } catch (e: Exception) {
                Log.e(TAG, "버스 노선 상세 정보 조회 오류: ${e.message}", e)
                result.error("API_ERROR", "버스 노선 상세 정보 조회 중 오류 발생: ${e.message}", null)
            }
        }
    }

    private fun searchBusRoutes(call: MethodCall, result: MethodChannel.Result) {
        val searchText = call.argument<String>("searchText") ?: ""
        if (searchText.isEmpty()) {
            result.error("INVALID_ARGUMENT", "검색어가 비어있습니다", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val routes = activity.busApiService.searchBusRoutes(searchText)
                Log.d(TAG, "노선 검색 결과: ${routes.size}개")
                if (routes.isEmpty()) Log.d(TAG, "검색 결과 없음: $searchText")
                val jsonArray = JSONArray()
                routes.forEach { route ->
                    val jsonObj = JSONObject().apply {
                        put("id", route.id)
                        put("routeNo", route.routeNo)
                        put("routeTp", route.routeTp)
                        put("startPoint", route.startPoint)
                        put("endPoint", route.endPoint)
                        put("routeDescription", route.routeDescription)
                    }
                    jsonArray.put(jsonObj)
                }
                result.success(jsonArray.toString())
            } catch (e: Exception) {
                Log.e(TAG, "노선 검색 오류: ${e.message}", e)
                result.error("API_ERROR", "노선 검색 중 오류 발생: ${e.message}", null)
            }
        }
    }

    private fun getStationIdFromBsId(call: MethodCall, result: MethodChannel.Result) {
        val bsId = call.argument<String>("bsId") ?: ""
        if (bsId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "bsId가 비어있습니다", null)
            return
        }
        if (bsId.startsWith("7") && bsId.length == 10) {
            Log.d(TAG, "bsId '$bsId'는 이미 stationId 형식입니다")
            result.success(bsId)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val stationId = activity.busApiService.getStationIdFromBsId(bsId)
                if (stationId != null && stationId.isNotEmpty()) {
                    Log.d(TAG, "bsId '${bsId}'에 대한 stationId '$stationId' 조회 성공")
                    result.success(stationId)
                } else {
                    Log.e(TAG, "stationId 조회 실패: $bsId")
                    result.error("NOT_FOUND", "stationId를 찾을 수 없습니다: $bsId", null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "정류장 ID 변환 오류: ${e.message}", e)
                result.error("API_ERROR", "stationId 변환 중 오류 발생: ${e.message}", null)
            }
        }
    }

    private fun getStationInfo(call: MethodCall, result: MethodChannel.Result) {
        val stationId = call.argument<String>("stationId") ?: ""
        if (stationId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "정류장 ID가 비어있습니다", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val jsonString = runBlocking { activity.busApiService.getStationInfo(stationId) }
                Log.d(TAG, "정류장 정보 조회 완료: $stationId")
                result.success(jsonString)
            } catch (e: Exception) {
                Log.e(TAG, "정류장 정보 조회 오류: ${e.message}", e)
                result.error("API_ERROR", "정류장 정보 조회 중 오류 발생: ${e.message}", null)
            }
        }
    }

    private fun getBusArrivalByRouteId(call: MethodCall, result: MethodChannel.Result) {
        val stationId = call.argument<String>("stationId") ?: ""
        val routeId = call.argument<String>("routeId") ?: ""
        if (stationId.isEmpty() || routeId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "정류장 ID 또는 노선 ID가 비어있습니다", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val arrivalInfo = activity.busApiService.getBusArrivalInfoByRouteId(stationId, routeId)
                result.success(activity.busApiService.convertToJson(arrivalInfo ?: "{}"))
            } catch (e: Exception) {
                Log.e(TAG, "노선별 버스 도착 정보 조회 오류: ${e.message}", e)
                result.error("API_ERROR", "노선별 버스 도착 정보 조회 중 오류 발생: ${e.message}", null)
            }
        }
    }

    private fun getBusRouteInfo(call: MethodCall, result: MethodChannel.Result) {
        val routeId = call.argument<String>("routeId") ?: ""
        if (routeId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "노선 ID가 비어있습니다", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val routeInfo = activity.busApiService.getBusRouteInfo(routeId)
                result.success(activity.busApiService.convertToJson(routeInfo ?: "{}"))
            } catch (e: Exception) {
                Log.e(TAG, "버스 노선 정보 조회 오류: ${e.message}", e)
                result.error("API_ERROR", "버스 노선 정보 조회 중 오류 발생: ${e.message}", null)
            }
        }
    }

    private fun getBusPositionInfo(call: MethodCall, result: MethodChannel.Result) {
        val routeId = call.argument<String>("routeId") ?: ""
        if (routeId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "노선 ID가 비어있습니다", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val positionInfo = activity.busApiService.getBusPositionInfo(routeId)
                result.success(positionInfo)
            } catch (e: Exception) {
                Log.e(TAG, "실시간 버스 위치 정보 조회 오류: ${e.message}", e)
                result.error("API_ERROR", "실시간 버스 위치 정보 조회 중 오류 발생: ${e.message}", null)
            }
        }
    }

    private fun getRouteStations(call: MethodCall, result: MethodChannel.Result) {
        val routeId = call.argument<String>("routeId") ?: ""
        if (routeId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "routeId가 비어있습니다", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val stations = activity.busApiService.getBusRouteMap(routeId)
                Log.d(TAG, "노선도 조회 결과: ${stations.size}개 정류장")
                result.success(activity.busApiService.convertRouteStationsToJson(stations))
            } catch (e: Exception) {
                Log.e(TAG, "노선도 조회 오류: ${e.message}", e)
                result.error("API_ERROR", "노선도 조회 중 오류 발생: ${e.message}", null)
            }
        }
    }

    // ------------------------------------------------------------------
    // 알림·자동알람
    // ------------------------------------------------------------------

    private fun showNotification(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Int>("id") ?: 0
        val busNo = call.argument<String>("busNo") ?: ""
        val stationName = call.argument<String>("stationName") ?: ""
        val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
        val currentStation = call.argument<String>("currentStation") ?: ""
        val isOngoing = call.argument<Boolean>("isOngoing") ?: false
        val isAutoAlarm = call.argument<Boolean>("isAutoAlarm") ?: false

        try {
            val routeId = call.argument<String>("routeId")

            Log.d(TAG, "showNotification: ID=$id, Bus=$busNo, Station=$stationName, Remaining=$remainingMinutes, isOngoing=$isOngoing, isAutoAlarm=$isAutoAlarm")

            if (isOngoing) {
                // 진행 중인 추적 알림 - BusAlertService 통해 처리
                Log.d(TAG, "진행 중인 추적 알림 - BusAlertService로 전달")
                val busIntent = Intent(activity, BusAlertService::class.java).apply {
                    action = if (isAutoAlarm) {
                        BusAlertService.ACTION_START_AUTO_ALARM_LIGHTWEIGHT
                    } else {
                        BusAlertService.ACTION_SHOW_NOTIFICATION
                    }
                    putExtra("busNo", busNo)
                    putExtra("stationName", stationName)
                    putExtra("routeId", routeId)
                    putExtra("remainingMinutes", remainingMinutes)
                    putExtra("currentStation", currentStation)
                    putExtra("isAutoAlarm", isAutoAlarm)
                }
                activity.startService(busIntent)
                Log.d(TAG, "✅ BusAlertService로 진행 중 추적 알림 요청 전송")
            } else {
                // 간단한 일회성 알림 - 직접 생성 (잠금화면 표시용)
                Log.d(TAG, "간단한 일회성 알림 직접 생성 (잠금화면 표시용)")

                // Build notification content
                val title = if (remainingMinutes <= 0) {
                    "${busNo}번 버스 도착 알람"
                } else {
                    "${busNo}번 버스 알람"
                }
                val contentText = if (remainingMinutes <= 0) {
                    "${busNo}번 버스가 ${stationName} 정류장에 곧 도착합니다."
                } else {
                    "${busNo}번 버스가 약 ${remainingMinutes}분 후 도착 예정입니다."
                }
                val subText = if (currentStation.isNotEmpty()) "현재 위치: $currentStation" else null

                // Intent to open app
                val openAppIntent = activity.packageManager.getLaunchIntentForPackage(activity.packageName)?.apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                }
                val pendingIntent = if (openAppIntent != null) PendingIntent.getActivity(
                    activity, id, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                ) else null

                // Cancel action - 명시적 브로드캐스트로 변경 (Android 8.0+ 호환)
                Log.d(TAG, "🔴 '종료' 버튼 PendingIntent 생성 시작")
                val cancelIntent = Intent(activity, com.devground.daegubus.receivers.NotificationCancelReceiver::class.java).apply {
                    action = "com.devground.daegubus.ACTION_NOTIFICATION_CANCEL"
                    putExtra("routeId", routeId)
                    putExtra("busNo", busNo)
                    putExtra("stationName", stationName)
                    putExtra("notificationId", id)
                    putExtra("isAutoAlarm", isAutoAlarm)
                }
                Log.d(TAG, "🔴 Cancel Intent 생성: routeId=$routeId, busNo=$busNo, stationName=$stationName")
                val cancelPendingIntent = PendingIntent.getBroadcast(
                    activity, id + 1000, cancelIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                Log.d(TAG, "🔴 Cancel PendingIntent 생성 완료: requestCode=${id + 1000}")

                // 잠금화면 표시를 위한 간단한 알림 생성
                val builder = NotificationCompat.Builder(activity, MainActivity.ALARM_NOTIFICATION_CHANNEL_ID)
                    .setContentTitle(title)
                    .setContentText(contentText)
                    .setSmallIcon(R.mipmap.ic_launcher)
                    .setPriority(NotificationCompat.PRIORITY_MAX) // 최고 우선순위로 변경
                    .setCategory(NotificationCompat.CATEGORY_ALARM)
                    .setVisibility(NotificationCompat.VISIBILITY_PUBLIC) // 잠금화면에서 공개
                    .setColor(ContextCompat.getColor(activity, R.color.alert_color))
                    .setAutoCancel(true) // 터치 시 자동 삭제
                    .setDefaults(NotificationCompat.DEFAULT_ALL) // 소리, 진동 포함
                    .addAction(R.drawable.ic_cancel, "종료", cancelPendingIntent)
                    .setOnlyAlertOnce(false) // 매번 알림음 재생
                    .setShowWhen(true) // 시간 표시
                    .setWhen(System.currentTimeMillis())
                    .setFullScreenIntent(pendingIntent, false) // 잠금화면에서 강력한 표시
                    .setTimeoutAfter(0) // 자동 삭제되지 않도록 설정
                    .setLocalOnly(false) // 웨어러블 기기에도 표시

                if (pendingIntent != null) builder.setContentIntent(pendingIntent)
                if (subText != null) builder.setSubText(subText)

                val notificationManager = activity.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.notify(id, builder.build())
                Log.d(TAG, "✅ 간단한 일회성 알림 표시 완료: ID=$id")
            }

            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "알림 표시 오류: ${e.message}", e)
            result.error("NOTIFICATION_ERROR", "알림 표시 중 오류 발생: ${e.message}", null)
        }
    }

    private fun startAutoAlarmNow(call: MethodCall, result: MethodChannel.Result) {
        val alarmId = call.argument<Int>("alarmId") ?: 0
        val busNo = call.argument<String>("busNo") ?: ""
        val stationName = call.argument<String>("stationName") ?: ""
        val routeId = call.argument<String>("routeId") ?: ""
        val stationId = call.argument<String>("stationId") ?: ""
        val useTTS = call.argument<Boolean>("useTTS") ?: true
        val isCommuteAlarm = call.argument<Boolean>("isCommuteAlarm") ?: false
        val alarmHour = call.argument<Int>("alarmHour") ?: -1
        val alarmMinute = call.argument<Int>("alarmMinute") ?: -1

        if (busNo.isBlank() || stationName.isBlank() || routeId.isBlank() || stationId.isBlank()) {
            result.error("INVALID_ARGUMENT", "필수 인자가 누락되었습니다", null)
            return
        }

        try {
            val busIntent = Intent(activity, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_START_AUTO_ALARM_LIGHTWEIGHT
                putExtra("alarmId", alarmId)
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("remainingMinutes", -1)
                putExtra("currentStation", "")
                putExtra("useTTS", useTTS)
                putExtra("isCommuteAlarm", isCommuteAlarm)
                putExtra("alarmHour", alarmHour)
                putExtra("alarmMinute", alarmMinute)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                activity.startForegroundService(busIntent)
            } else {
                activity.startService(busIntent)
            }

            Log.i(TAG, "✅ 즉시 자동알람 시작 요청 완료: $busNo, $stationName, alarmId=$alarmId")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "❌ 즉시 자동알람 시작 실패: ${e.message}", e)
            result.error("START_AUTO_ALARM_ERROR", "Failed to start auto alarm immediately", e.message)
        }
    }

    private fun cancelNativeAutoAlarm(call: MethodCall, result: MethodChannel.Result) {
        val alarmId = call.argument<Int>("alarmId") ?: 0
        try {
            val alarmManager = activity.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            val alarmIntent = Intent(activity.applicationContext, com.devground.daegubus.receivers.AlarmReceiver::class.java).apply {
                action = "com.devground.daegubus.AUTO_ALARM"
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE
            } else {
                PendingIntent.FLAG_NO_CREATE
            }
            val pendingIntent = PendingIntent.getBroadcast(
                activity.applicationContext,
                alarmId,
                alarmIntent,
                flags
            )

            if (pendingIntent != null) {
                alarmManager.cancel(pendingIntent)
                pendingIntent.cancel()
                Log.i(TAG, "✅ 네이티브 자동알람 예약 취소 완료: alarmId=$alarmId")
            } else {
                Log.i(TAG, "ℹ️ 취소할 네이티브 자동알람 예약 없음: alarmId=$alarmId")
            }
            // 재부팅 재등록 저장소에서도 제거
            activity.applicationContext
                .getSharedPreferences("auto_alarm_store", Context.MODE_PRIVATE)
                .edit().remove(alarmId.toString()).apply()
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "❌ 네이티브 자동알람 예약 취소 실패: ${e.message}", e)
            result.error("CANCEL_NATIVE_ALARM_FAILED", "Failed to cancel native alarm.", e.message)
        }
    }

    private fun scheduleNativeAlarm(call: MethodCall, result: MethodChannel.Result) {
        val alarmId = call.argument<Int>("alarmId") ?: 0
        val busNo = call.argument<String>("busNo") ?: ""
        val stationName = call.argument<String>("stationName") ?: ""
        val routeId = call.argument<String>("routeId") ?: ""
        val stationId = call.argument<String>("stationId") ?: ""
        val useTTS = call.argument<Boolean>("useTTS") ?: true
        val isCommuteAlarm = call.argument<Boolean>("isCommuteAlarm") ?: false
        val alertOnArrivalOnly = call.argument<Boolean>("alertOnArrivalOnly") ?: false
        val hour = call.argument<Int>("hour") ?: 0
        val minute = call.argument<Int>("minute") ?: 0
        val repeatDays = call.argument<ArrayList<Int>>("repeatDays")?.toIntArray() ?: intArrayOf()
        val requestedTargetTime = call.argument<Long>("scheduledTimeMillis") ?: 0L
        val excludeHolidays = call.argument<Boolean>("excludeHolidays") ?: false

        if (busNo.isBlank() || stationName.isBlank() || routeId.isBlank() || stationId.isBlank() || repeatDays.isEmpty()) {
            result.error("INVALID_ARGUMENT", "필수 인자가 누락되었습니다", null)
            return
        }

        try {
            val alarmManager = activity.getSystemService(Context.ALARM_SERVICE) as android.app.AlarmManager
            val nowMillis = System.currentTimeMillis()
            val excludedDates = if (excludeHolidays) {
                AutoAlarmScheduleCalculator.loadExcludedDates(activity.applicationContext)
            } else {
                emptySet()
            }
            val targetAlarmTime = requestedTargetTime.takeIf { it > nowMillis }
                ?: AutoAlarmScheduleCalculator.findNextTargetTime(nowMillis, hour, minute, repeatDays, excludedDates)

            if (targetAlarmTime == null) {
                result.error("SCHEDULE_ERROR", "유효한 반복 요일을 찾을 수 없습니다", null)
                return
            }

            val trackingStartTime =
                AutoAlarmScheduleCalculator.trackingStartTime(targetAlarmTime, nowMillis)

            val alarmIntent = Intent(activity.applicationContext, com.devground.daegubus.receivers.AlarmReceiver::class.java).apply {
                action = "com.devground.daegubus.AUTO_ALARM"
                putExtra("alarmId", alarmId)
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("useTTS", useTTS)
                putExtra("hour", hour)
                putExtra("minute", minute)
                putExtra("repeatDays", repeatDays)
                putExtra("isCommuteAlarm", isCommuteAlarm)
                putExtra("alertOnArrivalOnly", alertOnArrivalOnly)
                putExtra("excludeHolidays", excludeHolidays)
                putExtra("scheduledTime", trackingStartTime)
                putExtra("targetAlarmTime", targetAlarmTime)
            }

            val pendingIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.getBroadcast(
                    activity.applicationContext, alarmId, alarmIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            } else {
                PendingIntent.getBroadcast(
                    activity.applicationContext, alarmId, alarmIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT
                )
            }

            val exact = AutoAlarmScheduleCalculator.scheduleExactAlarm(
                alarmManager, trackingStartTime, pendingIntent, TAG
            )
            if (!exact) {
                Log.w(TAG, "⚠️ ${busNo}번 자동알람이 부정확 알람으로 등록됨 — 설정에서 '알람 및 리마인더' 권한 확인 필요")
            }

            // 재부팅 재등록(BootReceiver)용 네이티브 저장소에 기록.
            // alarmId를 그대로 저장해 두므로 재등록 시 재계산이 필요 없다.
            val storeEntry = JSONObject().apply {
                put("alarmId", alarmId)
                put("busNo", busNo)
                put("stationName", stationName)
                put("routeId", routeId)
                put("stationId", stationId)
                put("useTTS", useTTS)
                put("isCommuteAlarm", isCommuteAlarm)
                put("alertOnArrivalOnly", alertOnArrivalOnly)
                put("excludeHolidays", excludeHolidays)
                put("hour", hour)
                put("minute", minute)
                put("repeatDays", JSONArray(repeatDays.toList()))
            }
            activity.applicationContext
                .getSharedPreferences("auto_alarm_store", Context.MODE_PRIVATE)
                .edit().putString(alarmId.toString(), storeEntry.toString()).apply()

            Log.d(TAG, "✅ Native AlarmManager 스케줄링 완료: ${busNo}번 버스, tracking=${java.util.Date(trackingStartTime)}, target=${java.util.Date(targetAlarmTime)}")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Native AlarmManager 스케줄링 실패: ${e.message}", e)
            result.error("SCHEDULE_ERROR", "Failed to schedule native alarm", e.message)
        }
    }

    // ------------------------------------------------------------------
    // TTS
    // ------------------------------------------------------------------

    private fun startTtsTracking(call: MethodCall, result: MethodChannel.Result) {
        val routeId = call.argument<String>("routeId") ?: ""
        val stationId = call.argument<String>("stationId") ?: ""
        val busNo = call.argument<String>("busNo") ?: ""
        val stationName = call.argument<String>("stationName") ?: ""
        val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
        if (routeId.isEmpty() || stationId.isEmpty() || busNo.isEmpty() || stationName.isEmpty()) {
            result.error("INVALID_ARGUMENT", "startTtsTracking requires routeId, stationId, busNo, stationName", null)
            return
        }
        try {
            val ttsIntent = Intent(activity, TTSService::class.java).apply {
                action = "START_TTS_TRACKING"
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("remainingMinutes", remainingMinutes)
            }
            // 포그라운드 알림 제거 요구사항에 따라 일반 Service로 실행
            activity.startService(ttsIntent)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "startTtsTracking 호출 오류: ${e.message}", e)
            result.error("TTS_ERROR", "startTtsTracking 실패: ${e.message}", null)
        }
    }

    private fun speakTTS(call: MethodCall, result: MethodChannel.Result) {
        val message = call.argument<String>("message") ?: ""
        val isHeadphoneMode = call.argument<Boolean>("isHeadphoneMode") ?: false
        val forceSpeaker = call.argument<Boolean>("forceSpeaker") ?: false
        if (message.isEmpty()) {
            result.error("INVALID_ARGUMENT", "메시지가 비어있습니다", null)
            return
        }
        try {
            val busAlertService = activity.busAlertService
            if (busAlertService != null) {
                // 강제 스피커 모드인 경우 이어폰 체크 무시
                if (forceSpeaker) {
                    Log.d(TAG, "🔊 강제 스피커 모드로 TTS 발화: $message")
                    busAlertService.speakTts(message, earphoneOnly = false, forceSpeaker = true)
                } else {
                    // BusAlertService의 speakTts 호출 (오디오 포커스 관리 포함)
                    busAlertService.speakTts(message, earphoneOnly = isHeadphoneMode, forceSpeaker = false)
                }
            } else {
                // BusAlertService가 null인 경우 MainActivity의 TTS 사용
                activity.speakFallbackTts(message)
            }
            result.success(true) // 비동기 호출이므로 일단 성공으로 응답
        } catch (e: Exception) {
            Log.e(TAG, "TTS 발화 오류: ${e.message}", e)
            result.success(true) // TTS 실패도 성공으로 처리
        }
    }

    private fun setAudioOutputMode(call: MethodCall, result: MethodChannel.Result) {
        val mode = call.argument<Int>("mode") ?: 2 // Default to Auto
        try {
            Log.i(TAG, "Flutter에서 오디오 출력 모드 변경 요청: $mode")
            activity.busAlertService?.setAudioOutputMode(mode)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "오디오 출력 모드 변경 오류: ${e.message}", e)
            result.error("SET_MODE_ERROR", "오디오 출력 모드 변경 실패: ${e.message}", null)
        }
    }

    private fun setVolume(call: MethodCall, result: MethodChannel.Result) {
        val volume = call.argument<Double>("volume") ?: 1.0
        try {
            Log.i(TAG, "Flutter에서 TTS 볼륨 변경 요청: $volume")
            activity.busAlertService?.setTtsVolume(volume)
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "TTS 볼륨 변경 오류: ${e.message}", e)
            result.error("SET_VOLUME_ERROR", "TTS 볼륨 변경 실패: ${e.message}", null)
        }
    }

    private fun stopTTS(result: MethodChannel.Result) {
        try {
            if (activity.busAlertService != null) {
                // BusAlertService의 stopTtsTracking을 호출하여 TTS 중지
                activity.busAlertService?.stopTtsTracking(forceStop = true)
            } else {
                // MainActivity TTS 중지
                activity.stopFallbackTts()
            }
            Log.d(TAG, "네이티브 TTS 중지 요청")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "TTS 중지 오류: ${e.message}", e)
            result.success(true)
        }
    }

    private fun isHeadphoneConnected(result: MethodChannel.Result) {
        try {
            val isConnected = if (activity.busAlertService != null) {
                activity.busAlertService?.isHeadsetConnected() ?: false
            } else {
                // 대안: AudioManager를 사용하여 이어폰 연결 상태 확인
                activity.isHeadphoneConnectedViaAudioManager()
            }
            Log.d(TAG, "🎧 이어폰 연결 상태 확인: $isConnected")
            result.success(isConnected)
        } catch (e: Exception) {
            Log.e(TAG, "🎧 이어폰 연결 상태 확인 오류: ${e.message}")
            result.success(false)
        }
    }
}
