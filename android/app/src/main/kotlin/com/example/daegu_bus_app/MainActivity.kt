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
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import java.util.Locale
import android.content.Context
import android.media.AudioDeviceInfo
import android.speech.tts.UtteranceProgressListener
import java.util.concurrent.ConcurrentHashMap
import android.app.NotificationManager
import android.widget.Toast
import androidx.annotation.NonNull
import com.google.android.material.bottomsheet.BottomSheetBehavior
import com.google.android.material.bottomsheet.BottomSheetDialog
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import android.widget.Button
import android.widget.ImageButton
import android.os.Build
import android.app.NotificationChannel
import android.graphics.Color
import android.media.AudioAttributes
import android.net.Uri
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    private val BUS_API_CHANNEL = "com.example.daegu_bus_app/bus_api"
    private val NOTIFICATION_CHANNEL = "com.example.daegu_bus_app/notification"
    private val TTS_CHANNEL = "com.example.daegu_bus_app/tts"
    private val TAG = "MainActivity"
    private val ONGOING_NOTIFICATION_ID = 10000
    private lateinit var busApiService: BusApiService
    private var busAlertService: BusAlertService? = null
    private val NOTIFICATION_PERMISSION_REQUEST_CODE = 123
    private lateinit var audioManager: AudioManager
    private lateinit var tts: TextToSpeech
    private var _methodChannel: MethodChannel? = null
    private var bottomSheetDialog: BottomSheetDialog? = null
    private var bottomSheetBehavior: BottomSheetBehavior<View>? = null

    // TTS 중복 방지를 위한 트래킹 맵
    private val ttsTracker = ConcurrentHashMap<String, Long>()
    private val TTS_DUPLICATE_THRESHOLD_MS = 300 // 0.3초 이내 중복 발화 방지

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        _methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BUS_API_CHANNEL)
        Log.d("MainActivity", "🔌 메서드 채널 초기화 완료")
        setupMethodChannels(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            super.onCreate(savedInstanceState)
            Log.d("MainActivity", " MainActivity 생성")

            // 승차 완료 액션 처리
            if (intent?.action == "com.example.daegu_bus_app.BOARDING_COMPLETE") {
                handleBoardingComplete()
            }

            busApiService = BusApiService(this)
            audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
            
            // TTS 초기화
            try {
                tts = TextToSpeech(this, this)
            } catch (e: Exception) {
                Log.e(TAG, "TTS 초기화 오류: ${e.message}", e)
            }

            try {
                val serviceIntent = Intent(this, BusAlertService::class.java)
                startService(serviceIntent)
                busAlertService = BusAlertService.getInstance(this)
            } catch (e: Exception) {
                Log.e(TAG, "BusAlertService 초기화 실패: ${e.message}", e)
            }

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
        } catch (e: Exception) {
            Log.e(TAG, "MainActivity onCreate 오류: ${e.message}", e)
        }
    }

    override fun onInit(status: Int) {
        try {
            if (status == TextToSpeech.SUCCESS) {
                try {
                    val result = tts.setLanguage(Locale.KOREAN)
                    if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
                        Log.e(TAG, "Korean language is not supported")
                    }
                    
                    // 발화 속도와 피치 최적화
                    tts.setSpeechRate(1.2f)  // 0.9f에서 1.2f로 증가
                    tts.setPitch(1.1f)       // 피치 추가
                    
                    // TTS 리스너 설정
                    tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {
                            Log.d(TAG, "TTS 발화 시작: $utteranceId")
                        }

                        override fun onDone(utteranceId: String?) {
                            Log.d(TAG, "TTS 발화 완료: $utteranceId")
                        }

                        override fun onError(utteranceId: String?) {
                            Log.e(TAG, "TTS 발화 오류: $utteranceId")
                        }
                    })
                    Log.d(TAG, "TTS 초기화 성공")
                } catch (e: Exception) {
                    Log.e(TAG, "TTS 설정 오류: ${e.message}", e)
                }
            } else {
                Log.e(TAG, "TTS 초기화 실패: $status")
            }
        } catch (e: Exception) {
            Log.e(TAG, "TTS onInit 오류: ${e.message}", e)
        }
    }

    private fun setupMethodChannels(flutterEngine: FlutterEngine) {
        try {
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BUS_API_CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "searchStations" -> {
                        val searchText = call.argument<String>("searchText") ?: ""
                        if (searchText.isEmpty()) {
                            result.error("INVALID_ARGUMENT", "검색어가 비어있습니다", null)
                            return@setMethodCallHandler
                        }
                        val searchType = call.argument<String>("searchType") ?: "web"
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                if (searchType == "local") {
                                    val databaseHelper = DatabaseHelper.getInstance(this@MainActivity)
                                    val stations = databaseHelper.searchStations(searchText)
                                    Log.d(TAG, "로컬 정류장 검색 결과: ${stations.size}개")
                                    val jsonArray = JSONArray()
                                    stations.forEach { station ->
                                        val jsonObj = JSONObject().apply {
                                            put("id", station.bsId)
                                            put("name", station.bsNm)
                                            put("isFavorite", false)
                                            put("wincId", station.bsId)
                                            put("ngisXPos", station.longitude)
                                            put("ngisYPos", station.latitude)
                                            put("routeList", JSONArray())
                                        }
                                        jsonArray.put(jsonObj)
                                    }
                                    result.success(jsonArray.toString())
                                } else {
                                    val stations = busApiService.searchStations(searchText)
                                    Log.d(TAG, "웹 정류장 검색 결과: ${stations.size}개")
                                    val jsonArray = JSONArray()
                                    stations.forEach { station ->
                                        Log.d(TAG, "Station - ID: ${station.bsId}, Name: ${station.bsNm}")
                                        val jsonObj = JSONObject().apply {
                                            put("id", station.bsId)
                                            put("name", station.bsNm)
                                            put("isFavorite", false)
                                            put("wincId", station.bsId)
                                            put("ngisXPos", 0.0)
                                            put("ngisYPos", 0.0)
                                            put("routeList", JSONArray())
                                        }
                                        jsonArray.put(jsonObj)
                                    }
                                    result.success(jsonArray.toString())
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "정류장 검색 오류: ${e.message}", e)
                                result.error("API_ERROR", "정류장 검색 중 오류 발생: ${e.message}", null)
                            }
                        }
                    }
                    "startTtsTracking" -> {
                        val routeId = call.argument<String>("routeId") ?: ""
                        val stationId = call.argument<String>("stationId") ?: ""
                        val busNo = call.argument<String>("busNo") ?: ""
                        val stationName = call.argument<String>("stationName") ?: ""
                        
                        // 유효성 검사 - 빈 인자를 대체 값으로 채우기
                        val effectiveRouteId = routeId.takeIf { it.isNotEmpty() } ?: busNo
                        val effectiveStationId = stationId.takeIf { it.isNotEmpty() } ?: effectiveRouteId
                        val effectiveBusNo = busNo.takeIf { it.isNotEmpty() } ?: effectiveRouteId
                        
                        if (effectiveRouteId.isEmpty() || effectiveStationId.isEmpty() || 
                            effectiveBusNo.isEmpty() || stationName.isEmpty()) {
                            Log.e(TAG, "필수 인자 오류 - routeId:$routeId, stationId:$stationId, busNo:$busNo, stationName:$stationName")
                            result.error("INVALID_ARGUMENT", "필수 인자 누락", null)
                            return@setMethodCallHandler
                        }
                        
                        try {
                            Log.d(TAG, "TTS 추적 시작 요청: $effectiveBusNo, $stationName")
                            busAlertService?.startTtsTracking(effectiveRouteId, effectiveStationId, effectiveBusNo, stationName)
                            result.success("TTS 추적 시작됨")
                        } catch (e: Exception) {
                            Log.e(TAG, "TTS 추적 시작 오류: ${e.message}", e)
                            result.error("TTS_ERROR", "TTS 추적 시작 실패: ${e.message}", null)
                        }
                    }
                    "updateBusTrackingNotification" -> {
                        val busNo = call.argument<String>("busNo") ?: ""
                        val stationName = call.argument<String>("stationName") ?: ""
                        // Ensure remainingMinutes is an Integer
                        val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
                        val currentStation = call.argument<String>("currentStation") ?: ""
                        try {
                            Log.d(TAG, "Flutter에서 버스 추적 알림 업데이트 요청: $busNo, 남은 시간: $remainingMinutes 분")
                            busAlertService?.showNotification(
                                id = ONGOING_NOTIFICATION_ID,
                                busNo = busNo,
                                stationName = stationName,
                                remainingMinutes = remainingMinutes,
                                currentStation = currentStation,
                                isOngoing = true
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "버스 추적 알림 업데이트 오류: ${e.message}", e)
                            result.error("NOTIFICATION_ERROR", "버스 추적 알림 업데이트 중 오류 발생: ${e.message}", null)
                        }
                    }
                    "registerBusArrivalReceiver" -> {
                        try {
                            busAlertService?.registerBusArrivalReceiver()
                            result.success("등록 완료")
                        } catch (e: Exception) {
                            Log.e(TAG, "BusArrivalReceiver 등록 오류: ${e.message}", e)
                            result.error("REGISTER_ERROR", "버스 도착 리시버 등록 실패: ${e.message}", null)
                        }
                    }
                    "startBusMonitoring" -> {
                        val routeId = call.argument<String>("routeId")
                        val stationId = call.argument<String>("stationId")
                        val stationName = call.argument<String>("stationName")
                        try {
                            busAlertService?.addMonitoredRoute(routeId!!, stationId!!, stationName!!)
                            result.success("추적 시작됨")
                        } catch (e: Exception) {
                            Log.e(TAG, "버스 추적 시작 오류: ${e.message}", e)
                            result.error("MONITOR_ERROR", "버스 추적 실패: ${e.message}", null)
                        }
                    }
                    "findNearbyStations" -> {
                        val latitude = call.argument<Double>("latitude") ?: 0.0
                        val longitude = call.argument<Double>("longitude") ?: 0.0
                        val radiusMeters = call.argument<Double>("radiusMeters") ?: 500.0
                        if (latitude == 0.0 || longitude == 0.0) {
                            result.error("INVALID_ARGUMENT", "위도 또는 경도가 유효하지 않습니다", null)
                            return@setMethodCallHandler
                        }
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                Log.d(TAG, "주변 정류장 검색 요청: lat=$latitude, lon=$longitude, radius=${radiusMeters}m")
                                val databaseHelper = DatabaseHelper.getInstance(this@MainActivity)
                                val nearbyStations = databaseHelper.searchStations(
                                    searchText = "",
                                    latitude = latitude,
                                    longitude = longitude,
                                    radiusInMeters = radiusMeters
                                )
                                Log.d(TAG, "주변 정류장 검색 결과: ${nearbyStations.size}개 (검색 반경: ${radiusMeters}m)")
                                val jsonArray = JSONArray()
                                nearbyStations.forEach { station ->
                                    val jsonObj = JSONObject().apply {
                                        put("id", station.stationId ?: station.bsId)
                                        put("name", station.bsNm)
                                        put("isFavorite", false)
                                        put("wincId", station.bsId)
                                        put("distance", station.distance)
                                        put("ngisXPos", station.longitude)
                                        put("ngisYPos", station.latitude)
                                        put("routeList", "[]")
                                    }
                                    jsonArray.put(jsonObj)
                                    Log.d(TAG, "정류장 정보 - 이름: ${station.bsNm}, ID: ${station.bsId}, 위치: (${station.longitude}, ${station.latitude}), 거리: ${station.distance}m")
                                }
                                result.success(jsonArray.toString())
                            } catch (e: Exception) {
                                Log.e(TAG, "주변 정류장 검색 오류: ${e.message}", e)
                                result.error("DB_ERROR", "주변 정류장 검색 중 오류 발생: ${e.message}", null)
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
                                val jsonArray = JSONArray()
                                routes.forEach { route ->
                                    val jsonObj = JSONObject().apply {
                                        put("id", route.id)
                                        put("routeNo", route.routeNo)
                                        put("routeTp", route.routeTp)
                                        put("startPoint", route.startPoint)
                                        put("endPoint", route.endPoint)
                                        put("routeDescription", route.routeDescription)
                                    }
                                    jsonArray.put(jsonObj)
                                }
                                result.success(jsonArray.toString())
                            } catch (e: Exception) {
                                Log.e(TAG, "노선 검색 오류: ${e.message}", e)
                                result.error("API_ERROR", "노선 검색 중 오류 발생: ${e.message}", null)
                            }
                        }
                    }
                    "getStationIdFromBsId" -> {
                        val bsId = call.argument<String>("bsId") ?: ""
                        if (bsId.isEmpty()) {
                            result.error("INVALID_ARGUMENT", "bsId가 비어있습니다", null)
                            return@setMethodCallHandler
                        }
                        if (bsId.startsWith("7") && bsId.length == 10) {
                            Log.d(TAG, "bsId '$bsId'는 이미 stationId 형식입니다")
                            result.success(bsId)
                            return@setMethodCallHandler
                        }
                        CoroutineScope(Dispatchers.Main).launch {
                            try {
                                val stationId = busApiService.getStationIdFromBsId(bsId)
                                if (stationId != null && stationId.isNotEmpty()) {
                                    Log.d(TAG, "bsId '${bsId}'에 대한 stationId '$stationId' 조회 성공")
                                    result.success(stationId)
                                } else {
                                    Log.e(TAG, "stationId 조회 실패: $bsId")
                                    result.error("NOT_FOUND", "stationId를 찾을 수 없습니다: $bsId", null)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "정류장 ID 변환 오류: ${e.message}", e)
                                result.error("API_ERROR", "stationId 변환 중 오류 발생: ${e.message}", null)
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
                                val stationInfoJson = busApiService.getStationInfo(stationId)
                                Log.d(TAG, "정류장 정보 조회 완료: $stationId")
                                result.success(stationInfoJson)
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
                            busAlertService?.showNotification(
                                id = ONGOING_NOTIFICATION_ID,
                                busNo = busNo,
                                stationName = stationName,
                                remainingMinutes = remainingMinutes,
                                currentStation = currentStation,
                                payload = "bus_tracking_$busNo",
                                isOngoing = true
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
                    "setAlarmSound" -> {
                        try {
                            val filename = call.argument<String>("filename") ?: ""
                            val useTts = call.argument<Boolean>("useTts") ?: false
                            Log.d(TAG, "알람음 설정 요청: $filename, TTS 사용: $useTts")
                            busAlertService?.setAlarmSound(filename, useTts)
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "알람음 설정 오류: ${e.message}", e)
                            result.error("ALARM_SOUND_ERROR", "알람음 설정 중 오류 발생: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TTS_CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "forceEarphoneOutput" -> {
                        try {
                            // 미디어 출력으로 고정
                            audioManager.mode = AudioManager.MODE_NORMAL
                            audioManager.setStreamVolume(
                                AudioManager.STREAM_MUSIC,
                                audioManager.getStreamVolume(AudioManager.STREAM_MUSIC),
                                0
                            )
                            Log.d(TAG, "미디어 출력 고정 완료")
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "오디오 출력 설정 오류: ${e.message}", e)
                            result.error("AUDIO_ERROR", "오디오 출력 설정 실패: ${e.message}", null)
                        }
                    }
                    "speakTTS" -> {
                        val message = call.argument<String>("message") ?: ""
                        val isHeadphoneMode = call.argument<Boolean>("isHeadphoneMode") ?: false

                        // 중복 발화 방지 로직 추가
                        val currentTime = System.currentTimeMillis()
                        val lastSpeakTime = ttsTracker[message] ?: 0

                        if (currentTime - lastSpeakTime > TTS_DUPLICATE_THRESHOLD_MS) {
                            // 중복 아니면 발화 진행
                            speakTTS(message, isHeadphoneMode)

                            // 발화 시간 기록
                            ttsTracker[message] = currentTime

                            result.success(true)
                        } else {
                            // 중복 발화 방지
                            Log.d(TAG, "중복 TTS 발화 방지: $message")
                            result.success(false)
                        }
                    }
                    "setAudioOutputMode" -> {
                        val mode = call.argument<Int>("mode") ?: 2  // 기본값: 자동 감지
                        try {
                            busAlertService?.setAudioOutputMode(mode)
                            Log.d(TAG, "오디오 출력 모드 설정: $mode")
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "오디오 출력 모드 설정 오류: ${e.message}", e)
                            result.error("AUDIO_MODE_ERROR", "오디오 출력 모드 설정 실패: ${e.message}", null)
                        }
                    }
                    "speakEarphoneOnly" -> {
                        val message = call.argument<String>("message") ?: ""
                        if (message.isEmpty()) {
                            result.error("INVALID_ARGUMENT", "메시지가 비어있습니다", null)
                            return@setMethodCallHandler
                        }
                        try {
                            // 미디어 출력으로 고정
                            audioManager.mode = AudioManager.MODE_NORMAL
                            
                            // 감시 가능한 발화 ID 생성
                            val utteranceId = "EARPHONE_${System.currentTimeMillis()}"
                            val params = Bundle().apply {
                                putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
                                putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, AudioManager.STREAM_MUSIC)
                            }
                            
                            // UI 스레드에서 실행
                            runOnUiThread {
                                try {
                                    val ttsResult = tts.speak(message, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
                                    Log.d(TAG, "TTS 이어폰 발화 시작: $message, 결과: $ttsResult")
                                } catch (e: Exception) {
                                    Log.e(TAG, "TTS 이어폰 발화 오류: ${e.message}", e)
                                }
                            }
                            
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "이어폰 TTS 실행 오류: ${e.message}", e)
                            result.error("TTS_ERROR", "이어폰 TTS 발화 실패: ${e.message}", null)
                        }
                    }
                    "startTtsTracking" -> {
                        val routeId = call.argument<String>("routeId") ?: ""
                        val stationId = call.argument<String>("stationId") ?: ""
                        val busNo = call.argument<String>("busNo") ?: ""
                        val stationName = call.argument<String>("stationName") ?: ""
                        if (routeId.isEmpty() || stationId.isEmpty() || busNo.isEmpty() || stationName.isEmpty()) {
                            result.error("INVALID_ARGUMENT", "필수 인자 누락", null)
                            return@setMethodCallHandler
                        }
                        try {
                            busAlertService?.startTtsTracking(routeId, stationId, busNo, stationName)
                            result.success("TTS 추적 시작됨")
                        } catch (e: Exception) {
                            Log.e(TAG, "TTS 추적 시작 오류: ${e.message}", e)
                            result.error("TTS_ERROR", "TTS 추적 시작 실패: ${e.message}", null)
                        }
                    }
                    "stopTtsTracking" -> {
                        try {
                            busAlertService?.stopTtsTracking(forceStop = true) // forceStop = true로 설정
                            tts.stop()
                            Log.d(TAG, "TTS 추적 중지")
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "TTS 추적 중지 오류: ${e.message}", e)
                            result.error("TTS_ERROR", "TTS 추적 중지 실패: ${e.message}", null)
                        }
                    }
                    "stopTTS" -> {
                        try {
                            tts.stop()
                            Log.d(TAG, "네이티브 TTS 정지")
                            result.success(true)
                        } catch (e: Exception) {
                            Log.e(TAG, "네이티브 TTS 정지 오류: ${e.message}", e)
                            result.error("TTS_ERROR", "TTS 정지 실패: ${e.message}", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

            // 초기화 시도
            try {
                busAlertService?.initialize(this, flutterEngine)
            } catch (e: Exception) {
                Log.e(TAG, "알림 서비스 초기화 오류: ${e.message}", e)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Method 채널 설정 오류: ${e.message}", e)
        }
    }

    private fun speakTTS(text: String, isHeadphoneMode: Boolean) {
        try {
            // 오디오 출력 모드 정보 로깅 (추가)
            val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
            val isWiredHeadsetConnected = audioManager.isWiredHeadsetOn
            val isBluetoothConnected = audioManager.isBluetoothA2dpOn
            Log.d(TAG, "🎧🔊 TTS 오디오 상태 확인 ==========================================")
            Log.d(TAG, "🎧 이어폰 연결 상태: 유선=${isWiredHeadsetConnected}, 블루투스=${isBluetoothConnected}")
            Log.d(TAG, "🎧 요청된 모드: ${if (isHeadphoneMode) "이어폰 전용" else "일반 모드"}")
            if (busAlertService != null) {
                val mode = busAlertService?.getAudioOutputMode() ?: -1
                val modeName = when(mode) {
                    0 -> "이어폰 전용"
                    1 -> "스피커 전용"
                    2 -> "자동 감지"
                    else -> "알 수 없음"
                }
                Log.d(TAG, "🎧 현재 설정된 오디오 모드: $modeName ($mode)")
            } else {
                Log.d(TAG, "🎧 busAlertService가 null이어서 오디오 모드를 확인할 수 없습니다")
            }
            Log.d(TAG, "🎧 발화 텍스트: \"$text\"")
            
            // 간소화된 파라미터 설정
            val utteranceId = "TTS_${System.currentTimeMillis()}"
            val params = Bundle().apply {
                putString(TextToSpeech.Engine.KEY_PARAM_UTTERANCE_ID, utteranceId)
                // 알림 스트림으로 변경하여 우선순위 높임
                putInt(TextToSpeech.Engine.KEY_PARAM_STREAM, AudioManager.STREAM_NOTIFICATION)
                putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, 1.0f)
            }
            
            // UI 스레드에서 직접 실행
            runOnUiThread {
                try {
                    // 항상 QUEUE_FLUSH 모드로 실행하여 지연 없이 즉시 발화
                    val result = tts.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId)
                    Log.d(TAG, "🔊 TTS 발화 결과: $result (0=성공)")
                    Log.d(TAG, "🎧🔊 TTS 발화 요청 완료 ==========================================")
                } catch (e: Exception) {
                    Log.e(TAG, "TTS 발화 오류: ${e.message}", e)
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "speakTTS 호출 오류: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        try {
            // TTS 종료
            if (::tts.isInitialized) {
                try {
                    tts.stop()
                    tts.shutdown()
                    Log.d(TAG, "TTS 자원 해제")
                } catch (e: Exception) {
                    Log.e(TAG, "TTS 자원 해제 오류: ${e.message}", e)
                }
            }
            super.onDestroy()
        } catch (e: Exception) {
            Log.e(TAG, "onDestroy 오류: ${e.message}", e)
            super.onDestroy()
        }
    }

    private fun calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val earthRadius = 6371000.0
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return earthRadius * c
    }

    private fun splitIntoSentences(text: String): List<String> {
        val sentences = mutableListOf<String>()
        
        // 문장 구분자
        val sentenceDelimiters = "[.!?]".toRegex()
        val parts = text.split(sentenceDelimiters)
        
        if (parts.size > 1) {
            // 문장 구분자가 있으면 그대로 분할
            for (part in parts) {
                if (part.trim().isNotEmpty()) {
                    sentences.add(part.trim())
                }
            }
        } else {
            // 쉼표로 분할 시도
            val commaDelimited = text.split(",")
            if (commaDelimited.size > 1) {
                for (part in commaDelimited) {
                    if (part.trim().isNotEmpty()) {
                        sentences.add(part.trim())
                    }
                }
            } else {
                // 길이에 따라 임의로 분할
                val maxLength = 20
                var remaining = text
                while (remaining.length > maxLength) {
                    // 공백을 기준으로 적절한 분할 지점 찾기
                    var cutPoint = maxLength
                    while (cutPoint > 0 && remaining[cutPoint] != ' ') {
                        cutPoint--
                    }
                    // 공백을 찾지 못했으면 그냥 maxLength에서 자르기
                    if (cutPoint == 0) cutPoint = maxLength
                    
                    sentences.add(remaining.substring(0, cutPoint).trim())
                    remaining = remaining.substring(cutPoint).trim()
                }
                if (remaining.isNotEmpty()) {
                    sentences.add(remaining)
                }
            }
        }
        
        return sentences.filter { it.isNotEmpty() }
    }

    private fun handleBoardingComplete() {
        try {
            // 알림 매니저 가져오기
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            
            // 진행 중인 알림 모두 제거
            notificationManager.cancelAll()
            
            // TTS 중지
            _methodChannel?.invokeMethod("stopTTS", null)
            
            // 승차 완료 메시지 표시
            Toast.makeText(
                this,
                "승차가 완료되었습니다. 알림이 중지되었습니다.",
                Toast.LENGTH_SHORT
            ).show()
            
            Log.d(TAG, "✅ 승차 완료 처리됨")
        } catch (e: Exception) {
            Log.e(TAG, "❌ 승차 완료 처리 중 오류: ${e.message}")
        }
    }
}

fun BusRoute.toMap(): Map<String, Any?> {
    return mapOf(
        "id" to id,
        "routeNo" to routeNo,
        "startPoint" to startPoint,
        "endPoint" to endPoint,
        "routeDescription" to routeDescription
    )
}