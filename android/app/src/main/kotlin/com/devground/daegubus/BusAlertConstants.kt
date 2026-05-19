package com.devground.daegubus

import com.devground.daegubus.utils.NotificationHandler

object BusActions {
    const val ACTION_START_TRACKING = "com.devground.daegubus.action.START_TRACKING"
    const val ACTION_STOP_TRACKING = "com.devground.daegubus.action.STOP_TRACKING"
    const val ACTION_STOP_SPECIFIC_ROUTE_TRACKING = "com.devground.daegubus.action.STOP_SPECIFIC_ROUTE_TRACKING"
    const val ACTION_CANCEL_NOTIFICATION = "com.devground.daegubus.action.CANCEL_NOTIFICATION"
    const val ACTION_START_TTS_TRACKING = "com.devground.daegubus.action.START_TTS_TRACKING"
    const val ACTION_STOP_TTS_TRACKING = "com.devground.daegubus.action.STOP_TTS_TRACKING"
    const val ACTION_START_TRACKING_FOREGROUND = "com.devground.daegubus.action.START_TRACKING_FOREGROUND"
    const val ACTION_UPDATE_TRACKING = "com.devground.daegubus.action.UPDATE_TRACKING"
    const val ACTION_STOP_BUS_ALERT_TRACKING = "com.devground.daegubus.action.STOP_BUS_ALERT_TRACKING"
    const val ACTION_START_AUTO_ALARM_LIGHTWEIGHT = "com.devground.daegubus.action.START_AUTO_ALARM_LIGHTWEIGHT"
    const val ACTION_STOP_AUTO_ALARM = "com.devground.daegubus.action.STOP_AUTO_ALARM"
    const val ACTION_SET_ALARM_SOUND = "com.devground.daegubus.action.SET_ALARM_SOUND"
    const val ACTION_SHOW_NOTIFICATION = "com.devground.daegubus.action.SHOW_NOTIFICATION"
}

object BusNotificationIds {
    const val ONGOING = NotificationHandler.ONGOING_NOTIFICATION_ID
    const val AUTO_ALARM = 9999
}

object BusOutputMode {
    const val HEADSET = 0
    const val SPEAKER = 1
    const val AUTO = 2
}

object BusDisplayMode {
    const val ALARMED_ONLY = 0
}
