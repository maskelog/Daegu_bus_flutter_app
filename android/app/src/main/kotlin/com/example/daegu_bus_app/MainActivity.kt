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
import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.daegu_bus_app/bus_api" // 단일 채널로 통합
    private val NOTIFICATION_CHANNEL = "com.example.daegu_bus_app/notification"
    private val TAG = "MainActivity"
    private lateinit var busApiService: BusApiService
    private var busAlertService: BusAlertService? = null
    private val NOTIFICATION_PERMISSION_REQUEST_CODE = 123

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        busApiService = BusApiService(this)

        // BusAlertService 초기화 및 시작
        try {
            val serviceIntent = Intent(this, BusAlertService::class.java)
            startService(serviceIntent)
            busAlertService = BusAlertService.getInstance(this)
        } catch (e: Exception) {
            Log.e(TAG, "BusAlertService 초기화 실패: ${e.message}", e)
        }

        // Android 13+ 알림 권한 요청
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

        // 단일 채널(bus_api)로 모든 메서드 처리
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
                            val searchRoutes = busApiService.searchBusRoutes(routeId)
                            val routeInfo = busApiService.getBusRouteInfo(routeId)
                            val mergedRoute = routeInfo ?: searchRoutes.firstOrNull()
                            result.success(busApiService.convertToJson(mergedRoute ?: "{}"))
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
                            Log.d(TAG, "노선 검색 결과: ${routes.size}개")
                            if (routes.isEmpty()) Log.d(TAG, "검색 결과 없음: $searchText")
                            val jsonRoutes = routes.map { it.toMap() }
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
                            val arrivalInfo = busApiService.getStationInfo(stationId)
                            Log.d(TAG, "정류장 정보 조회 결과: ${arrivalInfo.size}개")
                            result.success(convertBusArrivalInfoToJson(arrivalInfo))
                        } catch (e: Exception) {
                            Log.e(TAG, "정류장 정보 조회 오류: ${e.message}", e)
                            result.error("API_ERROR", "정류장 정보 조회 중 오류 발생: ${e.message}", null)
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
                            result.success(busApiService.convertToJson(arrivalInfo ?: "{}"))
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
                            result.success(busApiService.convertToJson(routeInfo ?: "{}"))
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
                            result.success(busApiService.convertRouteStationsToJson(stations))
                        } catch (e: Exception) {
                            Log.e(TAG, "노선도 조회 오류: ${e.message}", e)
                            result.error("API_ERROR", "노선도 조회 중 오류 발생: ${e.message}", null)
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }

        // 알림 채널 설정 (별도 유지)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL).setMethodCallHandler { call, result ->
            if (busAlertService == null) {
                result.error("SERVICE_UNAVAILABLE", "알림 서비스가 초기화되지 않았습니다", null)
                return@setMethodCallHandler
            }
            when (call.method) {
                "initialize" -> {
                    try {
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
                        busAlertService?.showNotification(id, busNo, stationName, remainingMinutes, currentStation, payload)
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
                        busAlertService?.showOngoingBusTracking(busNo, stationName, remainingMinutes, currentStation, isUpdate)
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
                        busAlertService?.showBusArrivingSoon(busNo, stationName, currentStation)
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
                else -> result.notImplemented()
            }
        }

        // 알림 서비스 초기화
        try {
            busAlertService?.initialize(this, flutterEngine)
        } catch (e: Exception) {
            Log.e(TAG, "알림 서비스 초기화 오류: ${e.message}", e)
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == NOTIFICATION_PERMISSION_REQUEST_CODE) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                Log.d(TAG, "알림 권한이 허용됨")
                try {
                    busAlertService?.initialize(this)
                } catch (e: Exception) {
                    Log.e(TAG, "알림 서비스 초기화 오류: ${e.message}", e)
                }
            } else {
                Log.d(TAG, "알림 권한이 거부됨")
            }
        }
    }

    private fun convertBusArrivalInfoToJson(arrivalInfoList: List<BusArrivalInfo>): String {
        val jsonArray = JSONArray()
        arrivalInfoList.forEach { arrivalInfo ->
            val busesJson = JSONArray()
            arrivalInfo.buses.forEach { bus ->
                val busJson = JSONObject().apply {
                    put("busNumber", bus.busNumber)
                    put("currentStation", bus.currentStation)
                    put("remainingStops", bus.remainingStops)
                    put("estimatedTime", bus.estimatedTime)
                    put("isLowFloor", bus.isLowFloor)
                    put("isOutOfService", bus.isOutOfService)
                }
                busesJson.put(busJson)
            }
            val arrivalInfoJson = JSONObject().apply {
                put("routeId", arrivalInfo.routeId)
                put("routeNo", arrivalInfo.routeNo)
                put("destination", arrivalInfo.destination)
                put("buses", busesJson)
            }
            jsonArray.put(arrivalInfoJson)
        }
        return jsonArray.toString()
    }
}

// BusRoute를 Map으로 변환하는 확장 함수
fun BusRoute.toMap(): Map<String, Any?> {
    return mapOf(
        "id" to id,
        "routeNo" to routeNo,
        "startPoint" to startPoint,
        "endPoint" to endPoint,
        "routeDescription" to routeDescription
    )
}