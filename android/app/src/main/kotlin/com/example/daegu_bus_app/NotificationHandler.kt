package com.example.daegu_bus_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class NotificationHandler(private val context: Context) {

    companion object {
        private const val TAG = "NotificationHandler"

        // Notification Channel IDs
        private const val CHANNEL_ID_ONGOING = "bus_tracking_ongoing"
        private const val CHANNEL_NAME_ONGOING = "실시간 버스 추적"
        private const val CHANNEL_ID_ALERT = "bus_tracking_alert"
        private const val CHANNEL_NAME_ALERT = "버스 도착 임박 알림"
        private const val CHANNEL_ID_ERROR = "bus_tracking_error"
        private const val CHANNEL_NAME_ERROR = "추적 오류 알림"

        // Notification IDs
        const val ONGOING_NOTIFICATION_ID = 1 // Referenced by BusAlertService
        private const val ALERT_NOTIFICATION_ID_BASE = 1000 // Base for dynamic alert IDs
        const val ARRIVING_SOON_NOTIFICATION_ID = 2 // For arriving soon notifications

        // Intent Actions (referenced by notifications)
        private const val ACTION_STOP_TRACKING = "com.example.daegu_bus_app.action.STOP_TRACKING"
        private const val ACTION_CANCEL_NOTIFICATION = "com.example.daegu_bus_app.action.CANCEL_NOTIFICATION"
    }

     // --- Notification Channel Creation ---

    fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

                // Ongoing Channel (Low importance, silent)
                val ongoingChannel = NotificationChannel(
                    CHANNEL_ID_ONGOING,
                    CHANNEL_NAME_ONGOING,
                    NotificationManager.IMPORTANCE_LOW // Silent, minimal interruption
                ).apply {
                    description = "실시간 버스 추적 상태 알림"
                    enableVibration(false)
                    enableLights(false)
                    setShowBadge(false)
                    lockscreenVisibility = Notification.VISIBILITY_PRIVATE
                }

                // Alert Channel (High importance, sound/vibration)
                val alertChannel = NotificationChannel(
                    CHANNEL_ID_ALERT,
                    CHANNEL_NAME_ALERT,
                    NotificationManager.IMPORTANCE_HIGH // Alerting!
                ).apply {
                    description = "버스 도착 임박 시 알림"
                    enableVibration(true)
                    vibrationPattern = longArrayOf(0, 400, 200, 400)
                    lightColor = ContextCompat.getColor(context, R.color.tracking_color) // Use context
                    enableLights(true)
                    setShowBadge(true)
                    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                }

                // Error Channel (Default importance)
                 val errorChannel = NotificationChannel(
                    CHANNEL_ID_ERROR,
                    CHANNEL_NAME_ERROR,
                    NotificationManager.IMPORTANCE_DEFAULT
                ).apply {
                    description = "버스 추적 중 오류 발생 알림"
                    enableVibration(true)
                    setShowBadge(true)
                }

                notificationManager.createNotificationChannel(ongoingChannel)
                notificationManager.createNotificationChannel(alertChannel)
                notificationManager.createNotificationChannel(errorChannel)
                Log.d(TAG, "Notification channels created.")
            } catch (e: Exception) {
                Log.e(TAG, "Error creating notification channels: ${e.message}", e)
            }
        }
    }

    // --- Ongoing Notification ---

    fun buildOngoingNotification(activeTrackings: Map<String, BusAlertService.TrackingInfo>): Notification {
        val title = "버스 알람 추적 중"
        var contentText = "추적 중인 버스: ${activeTrackings.size}개"
        val currentTime = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())

        val inboxStyle = NotificationCompat.InboxStyle()
            .setBigContentTitle("$title ($currentTime)")

        if (activeTrackings.isEmpty()) {
            contentText = "추적 중인 버스가 없습니다."
            inboxStyle.addLine(contentText)
        } else {
            activeTrackings.values.take(5).forEach { trackingInfo ->
                val busInfo = trackingInfo.lastBusInfo
                val busNo = trackingInfo.busNo
                val stationNameShort = trackingInfo.stationName.take(10) + if (trackingInfo.stationName.length > 10) "..." else ""
                val timeStr = when {
                    trackingInfo.consecutiveErrors > 0 -> "오류"
                    busInfo == null -> "정보 없음"
                    busInfo.estimatedTime == "운행종료" -> "운행종료"
                    busInfo.estimatedTime == "곧 도착" -> "곧 도착"
                    busInfo.estimatedTime.contains("분") -> busInfo.estimatedTime
                    else -> "정보 없음"
                }
                 val lowFloorStr = if (busInfo?.isLowFloor == true) "(저)" else ""
                inboxStyle.addLine("$busNo$lowFloorStr (${stationNameShort}): $timeStr")
            }
            if (activeTrackings.size > 5) {
                inboxStyle.setSummaryText("+${activeTrackings.size - 5}개 더 추적 중")
            }
            val firstTracking = activeTrackings.values.firstOrNull()
            if(firstTracking != null) {
                 val busInfo = firstTracking.lastBusInfo
                 val busNo = firstTracking.busNo
                 val timeStr = when {
                     firstTracking.consecutiveErrors > 0 -> "오류"
                     busInfo == null -> "정보 없음"
                     busInfo.estimatedTime == "운행종료" -> "운행종료"
                     busInfo.estimatedTime == "곧 도착" -> "곧 도착"
                     busInfo.estimatedTime.contains("분") -> busInfo.estimatedTime
                     else -> "정보 없음"
                 }
                 contentText = "$busNo (${firstTracking.stationName.take(5)}..): $timeStr ${if (activeTrackings.size > 1) "+${activeTrackings.size - 1}" else ""}"
            }
        }

        val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
        }
        val pendingIntent = if (openAppIntent != null) PendingIntent.getActivity(
            context, 0, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        ) else null

        val stopAllIntent = Intent(context, BusAlertService::class.java).apply { // Target BusAlertService
            action = ACTION_STOP_TRACKING
            // 명시적으로 서비스 중지 플래그 추가
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val stopAllPendingIntent = PendingIntent.getService( // Use getService
            context, 1, stopAllIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID_ONGOING)
            .setContentTitle(title)
            .setContentText(contentText)
            .setSmallIcon(R.drawable.ic_bus_notification)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setStyle(inboxStyle)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setAutoCancel(false)
            .setOnlyAlertOnce(true)
            .setShowWhen(true)
            .setWhen(System.currentTimeMillis())
             .setColor(ContextCompat.getColor(context, R.color.tracking_color)) // Use context
             .setColorized(true)
            .addAction(R.drawable.ic_stop_tracking, "추적 중지", stopAllPendingIntent)

        return builder.build()
    }

     // --- Alert Notification ---

     fun sendAlertNotification(routeId: String, busNo: String, stationName: String) {
        val notificationId = ALERT_NOTIFICATION_ID_BASE + routeId.hashCode()
        val contentText = "$busNo 번 버스가 $stationName 정류장에 곧 도착합니다."
        Log.d(TAG, "Sending ALERT notification: $contentText (ID: $notificationId)")

        val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val pendingIntent = if (openAppIntent != null) PendingIntent.getActivity(
            context, notificationId, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        ) else null

        val cancelIntent = Intent(context, BusAlertService::class.java).apply { // Target BusAlertService
             action = ACTION_CANCEL_NOTIFICATION
             putExtra("notificationId", notificationId)
         }
         val cancelPendingIntent = PendingIntent.getService( // Use getService
             context, notificationId + 1, cancelIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
         )

        val builder = NotificationCompat.Builder(context, CHANNEL_ID_ALERT)
            .setContentTitle("버스 도착 임박!")
            .setContentText(contentText)
            .setSmallIcon(R.drawable.ic_bus_notification)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
             .setColor(ContextCompat.getColor(context, R.color.alert_color)) // Use context
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .addAction(R.drawable.ic_cancel, "닫기", cancelPendingIntent)
            .setDefaults(NotificationCompat.DEFAULT_ALL)

        val notificationManager = NotificationManagerCompat.from(context)
        notificationManager.notify(notificationId, builder.build())
    }

     // --- Error Notification ---

     fun sendErrorNotification(routeId: String?, busNo: String?, stationName: String?, message: String) {
        val notificationId = ALERT_NOTIFICATION_ID_BASE + (routeId ?: "error").hashCode() + 1
        val title = "버스 추적 오류"
        var contentText = message
        if (!busNo.isNullOrEmpty() && !stationName.isNullOrEmpty()) {
             contentText = "$busNo ($stationName): $message"
        }
         Log.w(TAG, "Sending ERROR notification: $contentText (ID: $notificationId)")

         val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
         val pendingIntent = if (openAppIntent != null) PendingIntent.getActivity(
             context, notificationId, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
         ) else null

         val builder = NotificationCompat.Builder(context, CHANNEL_ID_ERROR)
             .setContentTitle(title)
             .setContentText(contentText)
             .setSmallIcon(R.drawable.ic_bus_notification) // Consider an error icon
             .setPriority(NotificationCompat.PRIORITY_DEFAULT)
             .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
             .setContentIntent(pendingIntent)
             .setAutoCancel(true)

         val notificationManager = NotificationManagerCompat.from(context)
         notificationManager.notify(notificationId, builder.build())
     }

     // --- Notification Cancellation ---

     fun cancelNotification(id: Int) {
         Log.d(TAG, "Request to cancel notification ID: $id")
         try {
             val notificationManager = NotificationManagerCompat.from(context)
             notificationManager.cancel(id)

             // 진행 중인 추적 알림인 경우 BusAlertService에도 알림
             if (id == ONGOING_NOTIFICATION_ID) {
                 // 1. 서비스에 중지 요청 전송
                 val stopIntent = Intent(context, BusAlertService::class.java).apply {
                     action = BusAlertService.ACTION_STOP_TRACKING
                     flags = Intent.FLAG_ACTIVITY_NEW_TASK
                 }
                 if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                     context.startForegroundService(stopIntent)
                 } else {
                     context.startService(stopIntent)
                 }
                 Log.d(TAG, "Sent stop tracking request to BusAlertService")

                 // 2. 전체 취소 이벤트 브로드캐스트
                 val allCancelIntent = Intent("com.example.daegu_bus_app.ALL_TRACKING_CANCELLED")
                 context.sendBroadcast(allCancelIntent)
                 Log.d(TAG, "Sent ALL_TRACKING_CANCELLED broadcast")
             }
         } catch (e: Exception) {
             Log.e(TAG, "Error cancelling notification ID $id: ${e.message}", e)
         }
     }

     fun cancelOngoingTrackingNotification() {
         Log.d(TAG, "Canceling ongoing tracking notification ID: $ONGOING_NOTIFICATION_ID")
         try {
             // 1. 알림 직접 취소
             val notificationManager = NotificationManagerCompat.from(context)
             notificationManager.cancel(ONGOING_NOTIFICATION_ID)

             // 2. BusAlertService에 중지 요청
             val stopIntent = Intent(context, BusAlertService::class.java).apply {
                 action = BusAlertService.ACTION_STOP_TRACKING
                 flags = Intent.FLAG_ACTIVITY_NEW_TASK
             }
             if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                 context.startForegroundService(stopIntent)
             } else {
                 context.startService(stopIntent)
             }
             Log.d(TAG, "Sent stop tracking request to BusAlertService")

             // 3. 전체 취소 이벤트 브로드캐스트 (즉시)
             val allCancelIntent = Intent("com.example.daegu_bus_app.ALL_TRACKING_CANCELLED")
             context.sendBroadcast(allCancelIntent)
             Log.d(TAG, "Sent ALL_TRACKING_CANCELLED broadcast")

             // 4. 지연된 두 번째 브로드캐스트 (서비스 정리 후)
             Handler(Looper.getMainLooper()).postDelayed({
                 context.sendBroadcast(allCancelIntent)
                 Log.d(TAG, "Sent delayed ALL_TRACKING_CANCELLED broadcast")
             }, 500)
         } catch (e: Exception) {
             Log.e(TAG, "Error cancelling ongoing tracking notification: ${e.message}", e)
         }
     }

     fun cancelAllNotifications() {
         Log.d(TAG, "Request to cancel ALL notifications")
         try {
             // 1. 모든 알림 직접 취소
             val notificationManager = NotificationManagerCompat.from(context)
             notificationManager.cancelAll()

             // 2. BusAlertService에 중지 요청
             val stopIntent = Intent(context, BusAlertService::class.java).apply {
                 action = BusAlertService.ACTION_STOP_TRACKING
             }
             if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                 context.startForegroundService(stopIntent)
             } else {
                 context.startService(stopIntent)
             }
             Log.d(TAG, "Sent stop tracking request to BusAlertService")

             // 3. 전체 취소 이벤트 브로드캐스트
             val allCancelIntent = Intent("com.example.daegu_bus_app.ALL_TRACKING_CANCELLED")
             context.sendBroadcast(allCancelIntent)
             Log.d(TAG, "Sent ALL_TRACKING_CANCELLED broadcast")

         } catch (e: Exception) {
             Log.e(TAG, "Error cancelling all notifications: ${e.message}", e)
         }
     }

     // --- Regular Notification ---

     fun buildNotification(
         id: Int,
         busNo: String,
         stationName: String,
         remainingMinutes: Int,
         currentStation: String?
     ): Notification {
         val title = "$busNo Bus Alert"
         val contentText = if (remainingMinutes <= 0) {
             "Bus $busNo arriving soon at $stationName station."
         } else {
             "Bus $busNo will arrive at $stationName station in about ${remainingMinutes} minutes."
         }

         val subText = currentStation?.let { "Current location: $it" } ?: ""

         Log.d(TAG, "Building notification: $contentText (ID: $id)")

         val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
             flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
         }
         val pendingIntent = if (openAppIntent != null) PendingIntent.getActivity(
             context, id, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
         ) else null

         val cancelIntent = Intent(context, BusAlertService::class.java).apply {
             action = ACTION_CANCEL_NOTIFICATION
             putExtra("notificationId", id)
         }
         val cancelPendingIntent = PendingIntent.getService(
             context, id + 1, cancelIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
         )

         val builder = NotificationCompat.Builder(context, CHANNEL_ID_ALERT)
             .setContentTitle(title)
             .setContentText(contentText)
             .setSubText(subText)
             .setSmallIcon(R.drawable.ic_bus_notification)
             .setPriority(NotificationCompat.PRIORITY_HIGH)
             .setCategory(NotificationCompat.CATEGORY_ALARM)
             .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
             .setColor(ContextCompat.getColor(context, R.color.alert_color))
             .setContentIntent(pendingIntent)
             .setAutoCancel(true)
             .addAction(R.drawable.ic_cancel, "Cancel", cancelPendingIntent)
             .setDefaults(NotificationCompat.DEFAULT_ALL)

         return builder.build()
     }

     // --- Arriving Soon Notification ---

     fun buildArrivingSoonNotification(
         busNo: String,
         stationName: String,
         currentStation: String?
     ): Notification {
         val title = "Bus Arriving Soon!"
         val contentText = "Bus $busNo is arriving soon at $stationName station."
         val subText = currentStation?.let { "Current location: $it" } ?: ""

         Log.d(TAG, "Building arriving soon notification: $contentText (ID: $ARRIVING_SOON_NOTIFICATION_ID)")

         val openAppIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
             flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
         }
         val pendingIntent = if (openAppIntent != null) PendingIntent.getActivity(
             context, ARRIVING_SOON_NOTIFICATION_ID, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
         ) else null

         val cancelIntent = Intent(context, BusAlertService::class.java).apply {
             action = ACTION_CANCEL_NOTIFICATION
             putExtra("notificationId", ARRIVING_SOON_NOTIFICATION_ID)
         }
         val cancelPendingIntent = PendingIntent.getService(
             context, ARRIVING_SOON_NOTIFICATION_ID + 1, cancelIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
         )

         val builder = NotificationCompat.Builder(context, CHANNEL_ID_ALERT)
             .setContentTitle(title)
             .setContentText(contentText)
             .setSubText(subText)
             .setSmallIcon(R.drawable.ic_bus_notification)
             .setPriority(NotificationCompat.PRIORITY_HIGH)
             .setCategory(NotificationCompat.CATEGORY_ALARM)
             .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
             .setColor(ContextCompat.getColor(context, R.color.alert_color))
             .setContentIntent(pendingIntent)
             .setAutoCancel(true)
             .addAction(R.drawable.ic_cancel, "Close", cancelPendingIntent)
             .setDefaults(NotificationCompat.DEFAULT_ALL)

         return builder.build()
     }
}