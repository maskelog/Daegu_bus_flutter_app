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

class MainActivity : FlutterActivity() {
    private val BUS_API_CHANNEL = "com.example.daegu_bus_app/bus_api"
    private val NOTIFICATION_CHANNEL = "com.example.daegu_bus_app/notification"
    private val TTS_CHANNEL = "com.example.daegu_bus_app/tts"
    private val TAG = "MainActivity"
    private lateinit var busApiService: BusApiService
    private var busAlertService: BusAlertService? = null
    private val NOTIFICATION_PERMISSION_REQUEST_CODE = 123
    private lateinit var audioManager: AudioManager
    private lateinit var tts: TextToSpeech

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        busApiService = BusApiService(this)
        audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts.language = Locale.KOREAN
                Log.d(TAG, "TTS 초기화 성공")
            } else {
                Log.e(TAG, "TTS 초기화 실패")
            }
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
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

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
                    val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
                    val currentStation = call.argument<String>("currentStation") ?: ""
                    try {
                        Log.d(TAG, "Flutter에서 버스 추적 알림 업데이트 요청: $busNo, 남은 시간: $remainingMinutes 분")
                        busAlertService?.showOngoingBusTracking(
                            busNo = busNo,
                            stationName = stationName,
                            remainingMinutes = remainingMinutes,
                            currentStation = currentStation,
                            isUpdate = true
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

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TTS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "forceEarphoneOutput" -> {
                    try {
                        audioManager.isSpeakerphoneOn = false
                        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                        Log.d(TAG, "이어폰 출력 강제 설정")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "이어폰 출력 설정 오류: ${e.message}", e)
                        result.error("AUDIO_ERROR", "이어폰 출력 설정 실패: ${e.message}", null)
                    }
                }
                "speakTTS" -> {
                    val message = call.argument<String>("message") ?: ""
                    if (message.isEmpty()) {
                        result.error("INVALID_ARGUMENT", "메시지가 비어있습니다", null)
                        return@setMethodCallHandler
                    }
                    try {
                        audioManager.isSpeakerphoneOn = false
                        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                        tts.speak(message, TextToSpeech.QUEUE_FLUSH, null, null)
                        Log.d(TAG, "네이티브 TTS 발화: $message")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "네이티브 TTS 발화 오류: ${e.message}", e)
                        result.error("TTS_ERROR", "TTS 발화 실패: ${e.message}", null)
                    }
                }
                "speakEarphoneOnly" -> {
                    val message = call.argument<String>("message") ?: ""
                    if (message.isEmpty()) {
                        result.error("INVALID_ARGUMENT", "메시지가 비어있습니다", null)
                        return@setMethodCallHandler
                    }
                    try {
                        audioManager.isSpeakerphoneOn = false
                        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                        if (audioManager.isWiredHeadsetOn || audioManager.isBluetoothA2dpOn) {
                            // 긴 문장은 나눠서 발화
                            if (message.length > 20) {
                                val sentences = splitIntoSentences(message)
                                for (sentence in sentences) {
                                    tts.speak(sentence, TextToSpeech.QUEUE_ADD, null, "EARPHONE_${sentences.indexOf(sentence)}")
                                    Log.d(TAG, "이어폰 TTS 분할 발화 (${sentences.indexOf(sentence) + 1}/${sentences.size}): $sentence")
                                    Thread.sleep(300) // 문장 사이에 약간의 지연
                                }
                            } else {
                                tts.speak(message, TextToSpeech.QUEUE_FLUSH, null, null)
                                Log.d(TAG, "이어폰 전용 TTS 발화: $message")
                            }
                            result.success(true)
                        } else {
                            Log.d(TAG, "이어폰/블루투스 연결 없음, TTS 발화 생략")
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "이어폰 전용 TTS 발화 오류: ${e.message}", e)
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
                        busAlertService?.stopTtsTracking() // BusAlertService에서 호출
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
                Log.d(TAG, "알림 권한 허용됨")
                try {
                    busAlertService?.initialize(this)
                } catch (e: Exception) {
                    Log.e(TAG, "알림 서비스 초기화 오류: ${e.message}", e)
                }
            } else {
                Log.d(TAG, "알림 권한 거부됨")
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        tts.shutdown()
        Log.d(TAG, "TTS 자원 해제")
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