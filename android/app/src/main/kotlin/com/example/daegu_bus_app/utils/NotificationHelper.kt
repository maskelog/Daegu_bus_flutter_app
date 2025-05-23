package com.example.daegu_bus_app.utils

import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.app.NotificationManagerCompat
import com.example.daegu_bus_app.services.BusAlertService

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
            // 1. 특정 노선 추적 중지 요청 전송
            val stopSpecificIntent = Intent(context, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
                putExtra("routeId", routeId)
                putExtra("busNo", busNo)
                putExtra("stationName", stationName)
            }
            context.startService(stopSpecificIntent)
            Log.i(TAG, "특정 노선 추적 중지 명령 전송 완료: $busNo, $routeId")

            // 2. 포그라운드 알림 직접 취소 시도
            try {
                val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancel(BusAlertService.ONGOING_NOTIFICATION_ID)
                Log.i(TAG, "포그라운드 알림 직접 취소 완료")
            } catch (e: Exception) {
                Log.e(TAG, "포그라운드 알림 직접 취소 오류: ${e.message}", e)
            }

            // 3. 전체 추적 중지 요청 (백업)
            val stopAllIntent = Intent(context, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_STOP_TRACKING
            }
            context.startService(stopAllIntent)
            Log.i(TAG, "전체 추적 중지 명령 전송 완료 (백업)")

            // 4. Flutter 측에 알림 취소 이벤트 전송 시도
            try {
                val intent = Intent("com.example.daegu_bus_app.NOTIFICATION_CANCELLED")
                intent.putExtra("routeId", routeId)
                intent.putExtra("busNo", busNo)
                intent.putExtra("stationName", stationName)
                intent.putExtra("source", "notification_helper")
                context.sendBroadcast(intent)
                Log.d(TAG, "알림 취소 이벤트 브로드캐스트 전송: $busNo, $routeId, $stationName")
            } catch (e: Exception) {
                Log.e(TAG, "알림 취소 이벤트 전송 오류: ${e.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "버스 추적 알림 취소 오류: ${e.message}", e)

            // 오류 발생 시 강제 취소 시도
            try {
                val notificationManager = NotificationManagerCompat.from(context)
                notificationManager.cancelAll()
                Log.i(TAG, "모든 알림 강제 취소 완료 (오류 복구)")
            } catch (e: Exception) {
                Log.e(TAG, "모든 알림 강제 취소 오류: ${e.message}", e)
            }
        }
    }

    /**
     * 모든 알림 취소
     */
    fun cancelAllNotifications() {
        try {
            // 1. 모든 알림 직접 취소
            val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.cancelAll()
            Log.i(TAG, "모든 알림 직접 취소 완료")

            // 2. 서비스에 중지 명령 전송
            val stopIntent = Intent(context, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_STOP_TRACKING
            }
            context.startService(stopIntent)
            Log.i(TAG, "모든 추적 중지 명령 전송 완료")

            // 3. NotificationManagerCompat을 통한 취소 (백업)
            try {
                val compatNotificationManager = NotificationManagerCompat.from(context)
                compatNotificationManager.cancelAll()
                Log.i(TAG, "NotificationManagerCompat을 통한 모든 알림 취소 완료 (백업)")
            } catch (e: Exception) {
                Log.e(TAG, "NotificationManagerCompat 취소 오류: ${e.message}", e)
            }

            // 4. Flutter 측에 알림 취소 이벤트 전송 시도
            try {
                val intent = Intent("com.example.daegu_bus_app.ALL_TRACKING_CANCELLED")
                context.sendBroadcast(intent)
                Log.d(TAG, "모든 추적 취소 이벤트 브로드캐스트 전송")
            } catch (e: Exception) {
                Log.e(TAG, "알림 취소 이벤트 전송 오류: ${e.message}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "모든 알림 취소 오류: ${e.message}", e)

            // 오류 발생 시 다른 방법으로 재시도
            try {
                // 서비스에 중지 명령 전송
                val stopIntent = Intent(context, BusAlertService::class.java).apply {
                    action = BusAlertService.ACTION_STOP_TRACKING
                }
                context.startService(stopIntent)
                Log.i(TAG, "오류 후 모든 추적 중지 명령 전송 완료")
            } catch (e: Exception) {
                Log.e(TAG, "오류 후 추적 중지 명령 전송 실패: ${e.message}", e)
            }
        }
    }
}
