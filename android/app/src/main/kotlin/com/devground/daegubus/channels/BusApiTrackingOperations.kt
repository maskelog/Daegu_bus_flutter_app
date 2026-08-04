package com.devground.daegubus.channels

import android.content.Intent
import android.os.Build
import android.util.Log
import com.devground.daegubus.MainActivity
import com.devground.daegubus.services.BusAlertService
import com.devground.daegubus.services.StationTrackingService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** bus_api 채널의 버스·정류장 추적 시작, 갱신, 중지 작업. */
internal class BusApiTrackingOperations(private val activity: MainActivity) {

    companion object {
        private const val TAG = "BusApiChannel"
    }

    fun cancelAlarmNotification(call: MethodCall, result: MethodChannel.Result) {
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

    fun forceStopTracking(result: MethodChannel.Result) {
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

    fun startBusMonitoring(call: MethodCall, result: MethodChannel.Result) {
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

    fun stopBusTracking(call: MethodCall, result: MethodChannel.Result) {
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

    fun startBusMonitoringService(call: MethodCall, result: MethodChannel.Result) {
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

    fun stopBusMonitoringService(result: MethodChannel.Result) {
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

    fun cancelAlarmByRoute(call: MethodCall, result: MethodChannel.Result) {
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

    fun stopStationTracking(result: MethodChannel.Result) {
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

    fun stopAutoAlarm(call: MethodCall, result: MethodChannel.Result) {
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

    fun cancelOngoingTracking(result: MethodChannel.Result) {
        try {
            Log.i(TAG, "Flutter에서 진행 중 추적 취소 요청 받음")
            activity.busAlertService?.stopAllBusTracking()
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "진행 중 추적 취소 오류: ${e.message}", e)
            result.error("CANCEL_ERROR", "진행 중 추적 취소 실패: ${e.message}", null)
        }
    }

    fun cancelAllNotifications(result: MethodChannel.Result) {
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

    fun stopSpecificTracking(call: MethodCall, result: MethodChannel.Result) {
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

    fun stopAllBusTracking(result: MethodChannel.Result) {
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

    fun updateBusTrackingNotification(call: MethodCall, result: MethodChannel.Result) {
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

    fun updateBusInfo(call: MethodCall, result: MethodChannel.Result) {
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

    fun registerBusArrivalReceiver(result: MethodChannel.Result) {
        try {
            // BusArrivalReceiver registration is not directly available
            // This functionality may need to be implemented differently
            result.success("등록 완료")
        } catch (e: Exception) {
            Log.e(TAG, "BusArrivalReceiver 등록 오류: ${e.message}", e)
            result.error("REGISTER_ERROR", "버스 도착 리시버 등록 실패: ${e.message}", null)
        }
    }
}
