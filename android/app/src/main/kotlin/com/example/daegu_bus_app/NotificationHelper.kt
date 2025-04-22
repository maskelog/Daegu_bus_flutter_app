package com.example.daegu_bus_app

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationManagerCompat

/**
 * 알림 관련 헬퍼 클래스
 * 알림 취소 및 관리를 위한 유틸리티 메서드 제공
 */
class NotificationHelper(private val context: Context) {
    private val TAG = "NotificationHelper"

    /**
     * 특정 버스 추적 알림 취소
     */
    fun cancelBusTrackingNotification(routeId: String, busNo: String, stationName: String) {
        try {
            // 1. 서비스에 중지 명령 전송
            val stopIntent = Intent(context, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_STOP_TRACKING
                putExtra("routeId", routeId)
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
            }
            context.startService(stopIntent)
            Log.i(TAG, "서비스에 중지 명령 전송 완료: $busNo, $routeId")
        } catch (e: Exception) {
            Log.e(TAG, "버스 추적 알림 취소 오류: ${e.message}", e)
        }
    }

    /**
     * 모든 알림 취소
     */
    fun cancelAllNotifications() {
        try {
            // 1. 서비스에 중지 명령 전송
            val stopIntent = Intent(context, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_STOP_TRACKING
            }
            context.startService(stopIntent)
            Log.i(TAG, "모든 추적 중지 명령 전송 완료")

            // 2. 모든 알림 취소
            val notificationManager = NotificationManagerCompat.from(context)
            notificationManager.cancelAll()
            Log.i(TAG, "모든 알림 취소 완료")
        } catch (e: Exception) {
            Log.e(TAG, "모든 알림 취소 오류: ${e.message}", e)
        }
    }
}
