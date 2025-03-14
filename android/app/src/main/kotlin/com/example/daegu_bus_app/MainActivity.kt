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
import kotlinx.coroutines.withContext
import android.content.Intent
import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.daegu_bus_app/bus_api"
    private val METHOD_CHANNEL = "com.example.daegu_bus_app/methods"
    private val NOTIFICATION_CHANNEL = "com.example.daegu_bus_app/notification"
    private val TAG = "MainActivity"
    private lateinit var busApiService: BusApiService
    // 지연 초기화로 변경
    private var busAlertService: BusAlertService? = null
    
    private val NOTIFICATION_PERMISSION_REQUEST_CODE = 123
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // 수정: applicationContext 대신 this (Context) 사용
        busApiService = BusApiService(this)
        
        try {
            // 서비스 시작을 위한 인텐트 생성
            val serviceIntent = Intent(this, BusAlertService::class.java)
            startService(serviceIntent)
            
            // 서비스 인스턴스 가져오기 (수정: this 컨텍스트 전달)
            busAlertService = BusAlertService.getInstance(this)
        } catch (e: Exception) {
            Log.e(TAG, "BusAlertService 초기화 실패: ${e.message}", e)
            // 실패해도 앱은 계속 실행
        }
        
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

                    "getBusRouteDetails" -> {
                        val routeId = call.argument<String>("routeId") ?: ""
                        
                        if (routeId.isEmpty()) {
                            result.error("INVALID_ARGUMENT", "노선 ID가 비어있습니다", null)
                            return@setMethodCallHandler
                        }
                        
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                // 노선 기본 정보 조회
                                val searchRoutes = busApiService.searchBusRoutes(routeId)
                                
                                // 노선 상세 정보 조회
                                val routeInfo = busApiService.getBusRouteInfo(routeId)
                                
                                // 결과 병합
                                val mergedRoute = if (routeInfo != null) {
                                    BusRoute(
                                        id = routeInfo.id,
                                        routeNo = routeInfo.routeNo,
                                        startPoint = routeInfo.startPoint,
                                        endPoint = routeInfo.endPoint,
                                        routeDescription = routeInfo.routeDescription
                                    )
                                } else if (searchRoutes.isNotEmpty()) {
                                    searchRoutes.first()
                                } else {
                                    null
                                }
                                
                                if (mergedRoute != null) {
                                    result.success(busApiService.convertToJson(mergedRoute))
                                } else {
                                    result.success("{}")
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "버스 노선 상세 정보 조회 오류: ${e.message}", e)
                                result.error("API_ERROR", "버스 노선 상세 정보 조회 중 오류 발생: ${e.message}", null)
                            }
                        }
                    }
                    
                    "searchBusRoutes" -> {
                        val searchText = call.argument<String>("searchText") ?: ""
                        
                        if (searchText.isEmpty()) {
                            result.error("INVALID_ARGUMENT", "검색어가 비어있습니다", null)
                            return@setMethodCallHandler
                        }
                        
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                val routes = busApiService.searchBusRoutes(searchText)
                                
                                // 로깅 추가
                                Log.d(TAG, "노선 검색 결과: ${routes.size}개")
                                
                                if (routes.isEmpty()) {
                                    Log.d(TAG, "검색 결과 없음: $searchText")
                                }
                                
                                // JSON으로 변환하여 반환
                                val jsonRoutes = routes.map { route ->
                                    mapOf(
                                        "id" to route.id,
                                        "routeNo" to route.routeNo,
                                        "startPoint" to route.startPoint,
                                        "endPoint" to route.endPoint,
                                        "routeDescription" to route.routeDescription
                                    )
                                }
                                
                                result.success(jsonRoutes)
                            } catch (e: Exception) {
                                Log.e(TAG, "노선 검색 오류: ${e.message}", e)
                                result.error("API_ERROR", "노선 검색 중 오류 발생: ${e.message}", null)
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
                                if (routeInfo != null) {
                                    result.success(busApiService.convertToJson(routeInfo))
                                } else {
                                    // 노선 정보가 없는 경우 빈 JSON 객체 반환
                                    result.success("{}")
                                }
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
        
        // 메서드 채널 설정 - 중복 코드 통합
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getRouteStations" -> {
                        val routeId = call.argument<String>("routeId") ?: ""
                        
                        if (routeId.isEmpty()) {
                            result.error("INVALID_ARGUMENT", "routeId가 비어있습니다", null)
                            return@setMethodCallHandler
                        }
                        
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                val stations = busApiService.getBusRouteMap(routeId)
                                Log.d(TAG, "노선도 조회 결과: ${stations.size}개 정류장")
                                
                                if (stations.isEmpty()) {
                                    result.success("[]")
                                } else {
                                    // 인코딩 문제를 확인하기 위해 샘플 정류장 이름 로깅
                                    if (stations.isNotEmpty()) {
                                        val sampleName = stations[0].stationName
                                        Log.d(TAG, "샘플 정류장 이름: $sampleName, 바이트 길이: ${sampleName.toByteArray().size}")
                                    }
                                    
                                    val json = busApiService.convertRouteStationsToJson(stations)
                                    result.success(json)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "노선도 조회 오류: ${e.message}", e)
                                result.error("API_ERROR", "노선도 조회 중 오류 발생: ${e.message}", null)
                            }
                        }
                    }
                    "getStationInfo" -> { // ApiService.dart에서 호출하는 getStationInfo 처리
                        val stationId = call.argument<String>("stationId") ?: ""
                        if (stationId.isEmpty()) {
                            result.error("INVALID_ARGUMENT", "정류장 ID가 비어있습니다", null)
                            return@setMethodCallHandler
                        }

                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                // BusApiService를 사용하여 정류장 정보 가져오기
                                val arrivalInfo = busApiService.getStationInfo(stationId)
                                // JSON으로 변환하여 Flutter에 반환
                                val jsonResult = convertBusArrivalInfoToJson(arrivalInfo)
                                result.success(jsonResult)
                            } catch (e: Exception) {
                                Log.e(TAG, "정류장 정보 조회 오류: ${e.message}", e)
                                result.error("API_ERROR", "정류장 정보 조회 중 오류 발생: ${e.message}", null)
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
                // BusAlertService가 초기화되지 않았을 경우 오류 처리
                if (busAlertService == null) {
                    result.error("SERVICE_UNAVAILABLE", "알림 서비스가 초기화되지 않았습니다", null)
                    return@setMethodCallHandler
                }
                
                when (call.method) {
                    "initialize" -> {
                        try {
                            // 수정: this 컨텍스트와 flutterEngine 전달
                            busAlertService?.initialize(this, flutterEngine)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "알림 서비스 초기화 오류: ${e.message}", e)
                            result.error("INIT_ERROR", "알림 서비스 초기화 중 오류 발생: ${e.message}", null)
                        }
                    }
                    
                    "showNotification" -> {
                        val id = call.argument<Int>("id") ?: 0
                        val busNo = call.argument<String>("busNo") ?: ""
                        val stationName = call.argument<String>("stationName") ?: ""
                        val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
                        val currentStation = call.argument<String>("currentStation")
                        val payload = call.argument<String>("payload")
                        
                        try {
                            busAlertService?.showNotification(
                                id = id,
                                busNo = busNo,
                                stationName = stationName,
                                remainingMinutes = remainingMinutes,
                                currentStation = currentStation,
                                payload = payload
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "알림 표시 오류: ${e.message}", e)
                            result.error("NOTIFICATION_ERROR", "알림 표시 중 오류 발생: ${e.message}", null)
                        }
                    }
                    
                    "showOngoingBusTracking" -> {
                        val busNo = call.argument<String>("busNo") ?: ""
                        val stationName = call.argument<String>("stationName") ?: ""
                        val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
                        val currentStation = call.argument<String>("currentStation")
                        val isUpdate = call.argument<Boolean>("isUpdate") ?: false
                        
                        try {
                            busAlertService?.showOngoingBusTracking(
                                busNo = busNo,
                                stationName = stationName,
                                remainingMinutes = remainingMinutes,
                                currentStation = currentStation,
                                isUpdate = isUpdate
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "지속 알림 표시 오류: ${e.message}", e)
                            result.error("NOTIFICATION_ERROR", "지속 알림 표시 중 오류 발생: ${e.message}", null)
                        }
                    }
                    
                    "showBusArrivingSoon" -> {
                        val busNo = call.argument<String>("busNo") ?: ""
                        val stationName = call.argument<String>("stationName") ?: ""
                        val currentStation = call.argument<String>("currentStation")
                        
                        try {
                            busAlertService?.showBusArrivingSoon(
                                busNo = busNo,
                                stationName = stationName,
                                currentStation = currentStation
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "도착 임박 알림 표시 오류: ${e.message}", e)
                            result.error("NOTIFICATION_ERROR", "도착 임박 알림 표시 중 오류 발생: ${e.message}", null)
                        }
                    }
                    
                    "cancelNotification" -> {
                        val id = call.argument<Int>("id") ?: 0
                        busAlertService?.cancelNotification(id)
                        result.success(true)
                    }
                    
                    "cancelOngoingTracking" -> {
                        busAlertService?.cancelOngoingTracking()
                        result.success(true)
                    }
                    
                    "cancelAllNotifications" -> {
                        busAlertService?.cancelAllNotifications()
                        result.success(true)
                    }
                    
                    "showTestNotification" -> {
                        try {
                            busAlertService?.showTestNotification()
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "테스트 알림 표시 오류: ${e.message}", e)
                            result.error("NOTIFICATION_ERROR", "테스트 알림 표시 중 오류 발생: ${e.message}", null)
                        }
                    }
                    
                    else -> {
                        result.notImplemented()
                    }
                }
            }
            
        // 알림 서비스 초기화 - 오류가 나도 앱은 계속 실행되도록 예외 처리
        try {
            if (busAlertService != null) {
                // 수정: this 컨텍스트와 flutterEngine 전달
                busAlertService?.initialize(this, flutterEngine)
            }
        } catch (e: Exception) {
            Log.e(TAG, "알림 서비스 초기화 오류: ${e.message}", e)
            // 오류가 발생해도 앱 실행 계속
        }
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
                try {
                    busAlertService?.initialize()
                } catch (e: Exception) {
                    Log.e(TAG, "알림 서비스 초기화 오류: ${e.message}", e)
                }
            } else {
                Log.d(TAG, "알림 권한이 거부됨")
                // 필요하다면 사용자에게 알림 권한 필요성 설명
            }
        }
    }

    // BusArrivalInfo 목록을 JSON 문자열로 변환하는 함수
    private fun convertBusArrivalInfoToJson(arrivalInfoList: List<BusArrivalInfo>): String {
        val jsonArray = JSONArray()
        for (arrivalInfo in arrivalInfoList) {
            val busesJson = JSONArray()
            for (bus in arrivalInfo.buses) {
                val busJson = JSONObject().apply {
                    put("버스번호", bus.busNumber)
                    put("현재정류소", bus.currentStation)
                    put("남은정류소", bus.remainingStops)
                    put("도착예정소요시간", bus.estimatedTime)
                }
                busesJson.put(busJson)
            }

            val arrivalInfoJson = JSONObject().apply {
                put("name", arrivalInfo.routeNo)
                put("sub", "default")
                put("id", arrivalInfo.routeId)
                put("forward", arrivalInfo.destination)
                put("bus", busesJson)
            }
            jsonArray.put(arrivalInfoJson)
        }
        return jsonArray.toString()
    }
}