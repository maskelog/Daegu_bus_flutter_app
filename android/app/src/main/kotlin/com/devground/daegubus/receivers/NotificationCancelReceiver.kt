package com.devground.daegubus.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.core.content.ContextCompat
import com.devground.daegubus.services.BusAlertService

class NotificationCancelReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.i("NotificationCancelReceiver", "🔴🔴🔴 브로드캐스트 수신! 🔴🔴🔴")
        Log.i("NotificationCancelReceiver", "🔴 Intent Action: ${intent.action}")
        Log.i("NotificationCancelReceiver", "🔴 Intent Extras: ${intent.extras?.keySet()?.joinToString()}")
        
        val routeId = intent.getStringExtra("routeId")
        val busNo = intent.getStringExtra("busNo")
        val stationName = intent.getStringExtra("stationName")
        
        Log.i("NotificationCancelReceiver", "🔴 routeId=$routeId, busNo=$busNo, stationName=$stationName")
        
        if (routeId == null || busNo == null || stationName == null) {
            Log.e("NotificationCancelReceiver", "❌ 필수 데이터 누락!")
            return
        }
        
        Log.i("NotificationCancelReceiver", "🔴 알림 종료 브로드캐스트 수신: $busNo, $routeId, $stationName")
        
        val stopIntent = Intent(context, BusAlertService::class.java).apply {
            action = BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
            putExtra("routeId", routeId)
            putExtra("busNo", busNo)
            putExtra("stationName", stationName)
        }
        
        ContextCompat.startForegroundService(context, stopIntent)
        Log.i("NotificationCancelReceiver", "✅ BusAlertService에 종료 인텐트 전달 완료")
    }
}
