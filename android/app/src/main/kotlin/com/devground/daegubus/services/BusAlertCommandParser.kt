package com.devground.daegubus.services

import android.content.Intent
import com.devground.daegubus.BusActions

sealed class ServiceCommand {
    object StopAll : ServiceCommand()
    object StopAutoAlarm : ServiceCommand()
    data class StopRoute(
        val routeId: String,
        val busNo: String,
        val stationName: String,
        val notificationId: Int,
        val isAutoAlarm: Boolean,
        val shouldRemoveFromList: Boolean
    ) : ServiceCommand()
    data class StartTracking(
        val routeId: String,
        val stationId: String,
        val stationName: String,
        val busNo: String,
        val notificationId: Int,
        val isAutoAlarm: Boolean
    ) : ServiceCommand()
    data class StartForegroundTracking(
        val stationId: String?,
        val stationName: String?,
        val busNo: String?
    ) : ServiceCommand()
    object StartAutoAlarmLightweight : ServiceCommand()
    object Unknown : ServiceCommand()
    val isStopCommand: Boolean
        get() = this is StopAll || this is StopAutoAlarm || this is StopRoute
}

fun parseCommand(intent: Intent?): ServiceCommand {
    return when (intent?.action) {
        BusActions.ACTION_STOP_TRACKING -> ServiceCommand.StopAll
        BusActions.ACTION_STOP_AUTO_ALARM -> ServiceCommand.StopAutoAlarm
        BusActions.ACTION_STOP_SPECIFIC_ROUTE_TRACKING -> ServiceCommand.StopRoute(
            routeId = intent.getStringExtra("routeId") ?: return ServiceCommand.Unknown,
            busNo = intent.getStringExtra("busNo") ?: return ServiceCommand.Unknown,
            stationName = intent.getStringExtra("stationName") ?: "",
            notificationId = intent.getIntExtra("notificationId", -1),
            isAutoAlarm = intent.getBooleanExtra("isAutoAlarm", false),
            shouldRemoveFromList = intent.getBooleanExtra("shouldRemoveFromList", true)
        )
        BusActions.ACTION_START_TRACKING -> ServiceCommand.StartTracking(
            routeId = intent.getStringExtra("routeId") ?: return ServiceCommand.Unknown,
            stationId = intent.getStringExtra("stationId") ?: return ServiceCommand.Unknown,
            stationName = intent.getStringExtra("stationName") ?: "",
            busNo = intent.getStringExtra("busNo") ?: "",
            notificationId = intent.getIntExtra("notificationId", -1),
            isAutoAlarm = intent.getBooleanExtra("isAutoAlarm", false)
        )
        BusActions.ACTION_START_TRACKING_FOREGROUND, BusActions.ACTION_UPDATE_TRACKING -> ServiceCommand.StartForegroundTracking(
            stationId = intent.getStringExtra("stationId"),
            stationName = intent.getStringExtra("stationName"),
            busNo = intent.getStringExtra("busNo")
        )
        BusActions.ACTION_START_AUTO_ALARM_LIGHTWEIGHT -> ServiceCommand.StartAutoAlarmLightweight
        BusActions.ACTION_CANCEL_NOTIFICATION,
        BusActions.ACTION_START_TTS_TRACKING,
        BusActions.ACTION_STOP_TTS_TRACKING,
        BusActions.ACTION_STOP_BUS_ALERT_TRACKING,
        BusActions.ACTION_SET_ALARM_SOUND,
        BusActions.ACTION_SHOW_NOTIFICATION -> ServiceCommand.Unknown
        else -> ServiceCommand.Unknown
    }
}
