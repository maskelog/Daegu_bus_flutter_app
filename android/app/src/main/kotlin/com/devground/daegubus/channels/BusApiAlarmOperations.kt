package com.devground.daegubus.channels

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.devground.daegubus.MainActivity
import com.devground.daegubus.R
import com.devground.daegubus.services.BusAlertService
import com.devground.daegubus.utils.AutoAlarmScheduleCalculator
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/** bus_api 채널의 일회성 알림과 네이티브 자동알람 작업. */
internal class BusApiAlarmOperations(private val activity: MainActivity) {

    companion object {
        private const val TAG = "BusApiChannel"
    }

    fun showNotification(call: MethodCall, result: MethodChannel.Result) {
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
                    .setSmallIcon(R.drawable.notification_icon)
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

    fun startAutoAlarmNow(call: MethodCall, result: MethodChannel.Result) {
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

    fun cancelNativeAutoAlarm(call: MethodCall, result: MethodChannel.Result) {
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

    fun scheduleNativeAlarm(call: MethodCall, result: MethodChannel.Result) {
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
}
