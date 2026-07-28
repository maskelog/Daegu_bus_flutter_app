package com.devground.daegubus.services

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.devground.daegubus.models.BusInfo

class NotificationDismissReceiver : android.content.BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val notificationId = intent.getIntExtra("NOTIFICATION_ID", -1)
        if (notificationId != -1) {
            Log.d("NotificationDismiss", "🔔 Notification dismissed (ID: $notificationId)")
        }
    }
}

internal fun isSamsungOneUi(): Boolean {
    return Build.MANUFACTURER.equals("samsung", ignoreCase = true)
}

fun getNotificationChannels(context: Context): List<NotificationChannel>? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
        val notificationManager =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager?
        notificationManager?.notificationChannels
    } else {
        null
    }
}

fun StationArrivalOutput.toMap(): Map<String, Any?> {
    return mapOf(
        "name" to name, "sub" to sub, "id" to id, "forward" to forward,
        "bus" to bus.map { it.toMap() }
    )
}

fun RouteStation.toMap(): Map<String, Any?> {
    return mapOf(
        "stationId" to stationId, "stationName" to stationName,
        "sequenceNo" to sequenceNo, "direction" to direction
    )
}

fun BusInfo.toMap(): Map<String, Any?> {
    val isLowFloor = false
    val isOutOfService = estimatedTime == "운행종료"
    val remainingMinutes = when {
        estimatedTime == "곧 도착" -> 0
        estimatedTime == "운행종료" -> -1
        estimatedTime.contains("분") -> estimatedTime.filter { it.isDigit() }.toIntOrNull() ?: Int.MAX_VALUE
        else -> Int.MAX_VALUE
    }
    return mapOf(
        "busNumber" to busNumber, "estimatedTime" to estimatedTime,
        "currentStation" to currentStation, "isLowFloor" to isLowFloor,
        "isOutOfService" to isOutOfService, "remainingMinutes" to remainingMinutes
    )
}

fun StationArrivalOutput.BusInfo.toMap(): Map<String, Any?> {
    return mapOf(
        "busNumber" to busNumber, "currentStation" to currentStation,
        "remainingStations" to remainingStations, "estimatedTime" to estimatedTime
    )
}
