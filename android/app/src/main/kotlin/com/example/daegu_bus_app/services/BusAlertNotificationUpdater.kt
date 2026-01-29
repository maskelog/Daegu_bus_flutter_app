package com.example.daegu_bus_app.services

import android.app.Notification
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import com.example.daegu_bus_app.utils.NotificationHandler

class BusAlertNotificationUpdater(
    private val service: Service,
    private val notificationHandler: NotificationHandler,
) {
    companion object {
        private const val TAG = "BusAlertService"
    }

    fun buildOngoing(activeTrackings: Map<String, TrackingInfo>): Notification {
        return notificationHandler.buildOngoingNotification(activeTrackings)
    }

    fun updateOngoing(
        notificationId: Int,
        activeTrackings: Map<String, TrackingInfo>,
        isInForeground: Boolean,
        setInForeground: (Boolean) -> Unit,
    ) {
        val notification = buildOngoing(activeTrackings)
        val notificationManager =
            service.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        if (!isInForeground) {
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    service.startForeground(
                        notificationId,
                        notification,
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                    )
                } else {
                    service.startForeground(notificationId, notification)
                }
                setInForeground(true)
                Log.d(TAG, "✅ 포그라운드 서비스 시작됨: ID=$notificationId")
            } catch (e: Exception) {
                Log.e(TAG, "❌ 포그라운드 서비스 시작 오류: ${e.message}")
                notificationManager.notify(notificationId, notification)
            }
        } else {
            notificationManager.notify(notificationId, notification)
        }
    }
}
