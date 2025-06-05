package com.example.daegu_bus_app.core

import android.content.Context
import android.content.Intent
import android.util.Log
import com.example.daegu_bus_app.services.BusAlertService
import com.example.daegu_bus_app.services.TTSService
import kotlinx.coroutines.*

/**
 * 서비스 관리를 담당하는 경량화된 매니저 클래스
 * BusAlertService의 복잡성을 줄이기 위해 분리
 */
class ServiceManager private constructor() {
    companion object {
        private const val TAG = "ServiceManager"
        
        @Volatile
        private var INSTANCE: ServiceManager? = null
        
        fun getInstance(): ServiceManager {
            return INSTANCE ?: synchronized(this) {
                INSTANCE ?: ServiceManager().also { INSTANCE = it }
            }
        }
    }
    
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var isServiceRunning = false
    
    /**
     * 서비스 상태 확인
     */
    fun isServiceActive(): Boolean = isServiceRunning
    
    /**
     * 버스 추적 서비스 시작 (경량화)
     */
    fun startBusTracking(
        context: Context,
        routeId: String,
        stationId: String,
        stationName: String,
        busNo: String
    ) {
        try {
            val intent = Intent(context, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_START_TRACKING
                putExtra("routeId", routeId)
                putExtra("stationId", stationId)
                putExtra("stationName", stationName)
                putExtra("busNo", busNo)
            }
            context.startForegroundService(intent)
            isServiceRunning = true
            Log.d(TAG, "버스 추적 서비스 시작: $busNo")
        } catch (e: Exception) {
            Log.e(TAG, "버스 추적 서비스 시작 오류: ${e.message}")
        }
    }
    
    /**
     * 서비스 중지 (경량화)
     */
    fun stopAllServices(context: Context) {
        try {
            val intent = Intent(context, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_STOP_TRACKING
            }
            context.startService(intent)
            isServiceRunning = false
            Log.d(TAG, "모든 서비스 중지")
        } catch (e: Exception) {
            Log.e(TAG, "서비스 중지 오류: ${e.message}")
        }
    }
    
    /**
     * 리소스 정리
     */
    fun cleanup() {
        try {
            serviceScope.cancel()
            isServiceRunning = false
            Log.d(TAG, "ServiceManager 리소스 정리 완료")
        } catch (e: Exception) {
            Log.e(TAG, "ServiceManager 정리 오류: ${e.message}")
        }
    }
} 