package com.example.daegu_bus_app.receivers

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.example.daegu_bus_app.services.BusAlertService

class NotificationCancelReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val routeId = intent.getStringExtra("routeId") ?: return
        val busNo = intent.getStringExtra("busNo") ?: return
        val stationName = intent.getStringExtra("stationName") ?: return
        Log.i("NotificationCancelReceiver", "[BR] 알림 종료 브로드캐스트 수신: $busNo, $routeId, $stationName")
        val stopIntent = Intent(context, BusAlertService::class.java).apply {
            action = BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
            putExtra("routeId", routeId)
            putExtra("busNo", busNo)
            putExtra("stationName", stationName)
        }
        context.startService(stopIntent)
        Log.i("NotificationCancelReceiver", "[BR] BusAlertService에 종료 인텐트 전달 완료")
    }
}
