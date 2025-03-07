package com.example.daegu_bus_app

import android.os.Bundle
import android.content.pm.PackageManager
import android.Manifest
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.app.ActivityCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.daegu_bus_app/bus_api"
    private val NOTIFICATION_CHANNEL = "com.example.daegu_bus_app/notification" // 알림 채널 추가
    private val TAG = "MainActivity"
    private lateinit var busApiService: BusApiService
    private lateinit var busAlertService: BusAlertService // BusAlertService 인스턴스 추가
    
    private val NOTIFICATION_PERMISSION_REQUEST_CODE = 123
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        busApiService = BusApiService(context)
        busAlertService = BusAlertService.getInstance(context) // BusAlertService 초기화
        
        // Android 13+ (API 33+) 알림 권한 요청
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    NOTIFICATION_PERMISSION_REQUEST_CODE
                )
            }
        }
    }
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // 기존 API 채널 설정
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "searchStations" -> {
                        val searchText = call.argument<String>("searchText") ?: ""
                        if (searchText.isEmpty()) {
                            result.error("INVALID_ARGUMENT", "검색어가 비어있습니다", null)
                            return@setMethodCallHandler
                        }
                        
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                val stations = busApiService.searchStations(searchText)
                                Log.d(TAG, "정류장 검색 결과: ${stations.size}개")
                                result.success(busApiService.convertToJson(stations))
                            } catch (e: Exception) {
                                Log.e(TAG, "정류장 검색 오류: ${e.message}", e)
                                result.error("API_ERROR", "정류장 검색 중 오류 발생: ${e.message}", null)
                            }
                        }
                    }
                    
                    "getStationInfo" -> {
                        val stationId = call.argument<String>("stationId") ?: ""
                        if (stationId.isEmpty()) {
                            result.error("INVALID_ARGUMENT", "정류장 ID가 비어있습니다", null)
                            return@setMethodCallHandler
                        }
                        
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                val arrivalInfo = busApiService.getBusArrivalInfo(stationId)
                                Log.d(TAG, "버스 도착 정보 조회 결과: ${arrivalInfo.size}개")
                                result.success(busApiService.convertToJson(arrivalInfo))
                            } catch (e: Exception) {
                                Log.e(TAG, "버스 도착 정보 조회 오류: ${e.message}", e)
                                result.error("API_ERROR", "버스 도착 정보 조회 중 오류 발생: ${e.message}", null)
                            }
                        }
                    }
                    
                    "getBusArrivalByRouteId" -> {
                        val stationId = call.argument<String>("stationId") ?: ""
                        val routeId = call.argument<String>("routeId") ?: ""
                        
                        if (stationId.isEmpty() || routeId.isEmpty()) {
                            result.error("INVALID_ARGUMENT", "정류장 ID 또는 노선 ID가 비어있습니다", null)
                            return@setMethodCallHandler
                        }
                        
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                val arrivalInfo = busApiService.getBusArrivalInfoByRouteId(stationId, routeId)
                                if (arrivalInfo != null) {
                                    result.success(busApiService.convertToJson(arrivalInfo))
                                } else {
                                    result.error("NOT_FOUND", "해당 노선의 도착 정보를 찾을 수 없습니다", null)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "노선별 버스 도착 정보 조회 오류: ${e.message}", e)
                                result.error("API_ERROR", "노선별 버스 도착 정보 조회 중 오류 발생: ${e.message}", null)
                            }
                        }
                    }
                    
                    "getBusRouteInfo" -> {
                        val routeId = call.argument<String>("routeId") ?: ""
                        
                        if (routeId.isEmpty()) {
                            result.error("INVALID_ARGUMENT", "노선 ID가 비어있습니다", null)
                            return@setMethodCallHandler
                        }
                        
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                val routeInfo = busApiService.getBusRouteInfo(routeId)
                                result.success(routeInfo)
                            } catch (e: Exception) {
                                Log.e(TAG, "버스 노선 정보 조회 오류: ${e.message}", e)
                                result.error("API_ERROR", "버스 노선 정보 조회 중 오류 발생: ${e.message}", null)
                            }
                        }
                    }
                    
                    "getBusPositionInfo" -> {
                        val routeId = call.argument<String>("routeId") ?: ""
                        
                        if (routeId.isEmpty()) {
                            result.error("INVALID_ARGUMENT", "노선 ID가 비어있습니다", null)
                            return@setMethodCallHandler
                        }
                        
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                val positionInfo = busApiService.getBusPositionInfo(routeId)
                                result.success(positionInfo)
                            } catch (e: Exception) {
                                Log.e(TAG, "실시간 버스 위치 정보 조회 오류: ${e.message}", e)
                                result.error("API_ERROR", "실시간 버스 위치 정보 조회 중 오류 발생: ${e.message}", null)
                            }
                        }
                    }
                    
                    else -> {
                        result.notImplemented()
                    }
                }
            }
            
        // 알림 채널 설정 추가
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialize" -> {
                        busAlertService.initialize()
                        result.success(true)
                    }
                    
                    "showNotification" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val busNo = call.argument<String>("busNo") ?: ""
                        val stationName = call.argument<String>("stationName") ?: ""
                        val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
                        val currentStation = call.argument<String>("currentStation")
                        val payload = call.argument<String>("payload")
                        
                        busAlertService.showNotification(
                            id = id,
                            busNo = busNo,
                            stationName = stationName,
                            remainingMinutes = remainingMinutes,
                            currentStation = currentStation,
                            payload = payload
                        )
                        result.success(true)
                    }
                    
                    "showOngoingBusTracking" -> {
                        val busNo = call.argument<String>("busNo") ?: ""
                        val stationName = call.argument<String>("stationName") ?: ""
                        val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
                        val currentStation = call.argument<String>("currentStation")
                        val isUpdate = call.argument<Boolean>("isUpdate") ?: false
                        
                        busAlertService.showOngoingBusTracking(
                            busNo = busNo,
                            stationName = stationName,
                            remainingMinutes = remainingMinutes,
                            currentStation = currentStation,
                            isUpdate = isUpdate
                        )
                        result.success(true)
                    }
                    
                    "showBusArrivingSoon" -> {
                        val busNo = call.argument<String>("busNo") ?: ""
                        val stationName = call.argument<String>("stationName") ?: ""
                        val currentStation = call.argument<String>("currentStation")
                        
                        busAlertService.showBusArrivingSoon(
                            busNo = busNo,
                            stationName = stationName,
                            currentStation = currentStation
                        )
                        result.success(true)
                    }
                    
                    "cancelNotification" -> {
                        val id = call.argument<Int>("id") ?: 0
                        busAlertService.cancelNotification(id)
                        result.success(true)
                    }
                    
                    "cancelOngoingTracking" -> {
                        busAlertService.cancelOngoingTracking()
                        result.success(true)
                    }
                    
                    "cancelAllNotifications" -> {
                        busAlertService.cancelAllNotifications()
                        result.success(true)
                    }
                    
                    "showTestNotification" -> {
                        busAlertService.showTestNotification()
                        result.success(true)
                    }
                    
                    else -> {
                        result.notImplemented()
                    }
                }
            }
            
        // 알림 서비스 초기화
        val busAlertService = BusAlertService.getInstance(applicationContext)
        busAlertService.initialize(flutterEngine)
    }
    
    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "알림 권한이 허용됨")
                // 권한이 허용되면 BusAlertService 초기화
                busAlertService.initialize()
            } else {
                Log.d(TAG, "알림 권한이 거부됨")
                // 필요하다면 사용자에게 알림 권한 필요성 설명
            }
        }
    }
}