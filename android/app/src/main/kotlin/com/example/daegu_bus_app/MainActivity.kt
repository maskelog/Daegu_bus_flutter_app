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
import androidx.work.Worker
import androidx.work.WorkerParameters
import androidx.work.Configuration
import androidx.work.ListenableWorker
import androidx.work.WorkManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.IntentFilter
import android.content.ServiceConnection
import android.os.IBinder
import io.flutter.plugins.GeneratedPluginRegistrant
import java.util.Calendar
import android.app.Notification
import android.database.sqlite.SQLiteException
import com.example.daegu_bus_app.services.BusApiService
import com.example.daegu_bus_app.services.BusAlertService
import com.example.daegu_bus_app.services.TTSService
import com.example.daegu_bus_app.services.StationTrackingService
import com.example.daegu_bus_app.utils.DatabaseHelper
import com.example.daegu_bus_app.utils.NotificationHelper
import com.example.daegu_bus_app.utils.NotificationHandler
import kotlinx.coroutines.runBlocking
import android.os.PowerManager
import android.provider.Settings
import android.os.Handler
import android.os.Looper

class MainActivity : FlutterActivity(), TextToSpeech.OnInitListener {
    companion object {
        // 싱글톤 인스턴스
        private var instance: MainActivity? = null
        
        fun getInstance(): MainActivity? = instance
        
        // 정적 메서드를 통한 Flutter 이벤트 전송
        fun sendFlutterEvent(methodName: String, arguments: Any?) {
            try {
                instance?._methodChannel?.invokeMethod(methodName, arguments)
                Log.d("MainActivity", "✅ Flutter 이벤트 전송 완료: $methodName")
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ Flutter 이벤트 전송 실패: $methodName, ${e.message}")
            }
        }
    }
    
    private val BUS_API_CHANNEL = "com.example.daegu_bus_app/bus_api"
    private val NOTIFICATION_CHANNEL = "com.example.daegu_bus_app/notification"
    private val TTS_CHANNEL = "com.example.daegu_bus_app/tts"
    private val STATION_TRACKING_CHANNEL = "com.example.daegu_bus_app/station_tracking"
    private val BUS_TRACKING_CHANNEL = "com.example.daegu_bus_app/bus_tracking"
    private val TAG = "MainActivity"
    private val ONGOING_NOTIFICATION_ID = 10000
    private val ALARM_NOTIFICATION_CHANNEL_ID = "bus_alarm_channel"
    private lateinit var busApiService: BusApiService
    private var busAlertService: BusAlertService? = null
    private lateinit var notificationHelper: NotificationHelper
    private lateinit var notificationHandler: NotificationHandler

    // Make _methodChannel public for BusAlertService access
    var _methodChannel: MethodChannel? = null
        private set

    // 서비스 바인딩을 위한 커넥션 객체
    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {
            val binder = service as BusAlertService.LocalBinder
            busAlertService = binder.getService()
            busAlertService?.initialize()
            Log.d(TAG, "BusAlertService 바인딩 성공")
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            busAlertService = null
            Log.d(TAG, "BusAlertService 연결 해제")
        }
    }
    private val NOTIFICATION_PERMISSION_REQUEST_CODE = 123
    private val LOCATION_PERMISSION_REQUEST_CODE = 124
    private lateinit var audioManager: AudioManager
    private lateinit var tts: TextToSpeech
    private var bottomSheetDialog: BottomSheetDialog? = null
    private var bottomSheetBehavior: BottomSheetBehavior<View>? = null
    private var alarmCancelReceiver: BroadcastReceiver? = null

    // 알림 취소 이벤트를 수신하기 위한 BroadcastReceiver는 아래에 정의되어 있음

    // TTS 중복 방지를 위한 트래킹 맵 (BusAlertService로 이동 예정)
    // private val ttsTracker = ConcurrentHashMap<String, Long>()
    // private val TTS_DUPLICATE_THRESHOLD_MS = 300

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GeneratedPluginRegistrant.registerWith(flutterEngine)

        // BUS_API_CHANNEL 설정 (기존과 동일) - _methodChannel에 할당
        _methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BUS_API_CHANNEL)
        _methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "cancelAlarmNotification" -> {
                    val routeId = call.argument<String>("routeId") ?: ""
                    val busNo = call.argument<String>("busNo") ?: ""
                    val stationName = call.argument<String>("stationName") ?: ""

                    try {
                        Log.i(TAG, "Flutter에서 알람/추적 중지 요청: Bus=$busNo, Route=$routeId, Station=$stationName")

                        if (busAlertService != null) {
                            // Call stopTrackingForRoute, which handles notification update/cancellation internally.
                            // The 'true' for cancelNotification ensures it tries to affect notifications.
                            busAlertService?.stopTrackingForRoute(routeId, busNo, stationName, true)
                            Log.i(TAG, "BusAlertService.stopTrackingForRoute 호출 완료: $routeId")
                        } else {
                            // BusAlertService가 null인 경우, 서비스에 인텐트를 보내 중지 시도
                            try {
                                val serviceIntent = Intent(this, BusAlertService::class.java)
                                serviceIntent.action = BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
                                serviceIntent.putExtra("routeId", routeId)
                                serviceIntent.putExtra("busNo", busNo)
                                serviceIntent.putExtra("stationName", stationName)
                                startService(serviceIntent)
                                Log.i(TAG, "BusAlertService로 특정 노선 추적 중지 인텐트 전송 (서비스 null)")
                            } catch (e: Exception) {
                                Log.e(TAG, "BusAlertService 초기화 실패: ${e.message}", e)
                            }

                            // 직접 서비스 인텐트를 보내서 중지 시도
                            val stopIntent = Intent(this, BusAlertService::class.java).apply {
                                action = BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
                                putExtra("routeId", routeId) // routeId is primary key for tracking
                                putExtra("busNo", busNo)
                                putExtra("stationName", stationName)
                            }
                            startService(stopIntent)
                            Log.i(TAG, "특정 노선 추적 중지 인텐트 전송 완료 (서비스 null, 백업)")
                        }

                        // 4. NotificationHelper를 사용하여 알림 취소 (백업 방법, 브로드캐스트 없이)
                        notificationHelper.cancelBusTrackingNotification(routeId, busNo, stationName, false)
                        Log.i(TAG, "NotificationHelper를 통한 알림 취소 완료 (브로드캐스트 없이)")

                        // 5. Flutter 측에 알림 취소 완료 이벤트 전송
                        val alarmCancelData = mapOf(
                            "busNo" to busNo,
                            "routeId" to routeId,
                            "stationName" to stationName
                        )
                        _methodChannel?.invokeMethod("onAlarmCanceledFromNotification", alarmCancelData)
                        Log.i(TAG, "Flutter 측에 알람 취소 알림 전송 완료 (From cancelAlarmNotification handler)")

                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "알람/추적 중지 처리 오류: ${e.message}", e)

                        // 오류 발생 시에도 Flutter 측에 이벤트는 전송 시도
                        try {
                            val alarmCancelData = mapOf(
                                "busNo" to busNo,
                                "routeId" to routeId,
                                "stationName" to stationName
                            )
                            _methodChannel?.invokeMethod("onAlarmCanceledFromNotification", alarmCancelData)
                        } catch (ex: Exception) {
                            Log.e(TAG, "오류 후 알림 취소 시도 실패: ${ex.message}", ex)
                        }

                        result.error("CANCEL_ERROR", "알람/추적 중지 처리 실패: ${e.message}", null)
                    }
                }
                "forceStopTracking" -> {
                    try {
                        Log.i(TAG, "Flutter에서 강제 전체 추적 중지 요청 받음")
                        // WorkManager의 모든 작업 취소
                        val workManager = androidx.work.WorkManager.getInstance(applicationContext)
                        workManager.cancelAllWork()
                        Log.i(TAG, "WorkManager의 모든 작업 취소 완료")

                        // Call the comprehensive stopTracking method in BusAlertService
                        busAlertService?.stopTracking()
                        Log.i(TAG, "BusAlertService.stopTracking() 호출 완료")
                        
                        // NotificationHelper를 사용하여 모든 알림 취소 (브로드캐스트 없이)
                        notificationHelper.cancelAllNotifications(false)
                        Log.i(TAG, "NotificationHelper를 통한 모든 알림 취소 완료 (브로드캐스트 없이)")
                        
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "강제 전체 추적 중지 처리 오류: ${e.message}", e)
                        result.error("FORCE_STOP_ERROR", "강제 전체 추적 중지 처리 실패: ${e.message}", null)
                    }
                }
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
                                val jsonArray = org.json.JSONArray()
                                stations.forEach { station ->
                                    val jsonObj = org.json.JSONObject().apply {
                                        put("id", station.bsId)
                                        put("name", station.bsNm)
                                        put("isFavorite", false)
                                        put("wincId", station.bsId)
                                        put("ngisXPos", station.longitude)
                                        put("ngisYPos", station.latitude)
                                        put("routeList", org.json.JSONArray())
                                    }
                                    jsonArray.put(jsonObj)
                                }
                                result.success(jsonArray.toString())
                            } else {
                                val stations = busApiService.searchStations(searchText)
                                Log.d(TAG, "웹 정류장 검색 결과: ${stations.size}개")
                                val jsonArray = org.json.JSONArray()
                                stations.forEach { station ->
                                    Log.d(TAG, "Station - ID: ${station.bsId}, Name: ${station.bsNm}")
                                    val jsonObj = org.json.JSONObject().apply {
                                        put("id", station.bsId)
                                        put("name", station.bsNm)
                                        put("isFavorite", false)
                                        put("wincId", station.bsId)
                                        put("ngisXPos", 0.0)
                                        put("ngisYPos", 0.0)
                                        put("routeList", org.json.JSONArray())
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
                    val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
                    if (routeId.isEmpty() || stationId.isEmpty() || busNo.isEmpty() || stationName.isEmpty()) {
                        result.error("INVALID_ARGUMENT", "startTtsTracking requires routeId, stationId, busNo, stationName", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val ttsIntent = Intent(this, TTSService::class.java).apply {
                            action = "START_TTS_TRACKING"
                            putExtra("busNo", busNo)
                            putExtra("stationName", stationName)
                            putExtra("routeId", routeId)
                            putExtra("stationId", stationId)
                            putExtra("remainingMinutes", remainingMinutes)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(ttsIntent)
                        } else {
                            startService(ttsIntent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "startTtsTracking 호출 오류: ${e.message}", e)
                        result.error("TTS_ERROR", "startTtsTracking 실패: ${e.message}", null)
                    }
                }
                "updateBusTrackingNotification" -> {
                    val busNo = call.argument<String>("busNo") ?: ""
                    val stationName = call.argument<String>("stationName") ?: ""
                    val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
                    val currentStation = call.argument<String>("currentStation") ?: ""
                    val routeId = call.argument<String>("routeId") ?: ""
                    try {
                        Log.d(TAG, "Flutter에서 버스 추적 알림 업데이트 요청: $busNo, 남은 시간: $remainingMinutes 분")
                        val intent = Intent(this, BusAlertService::class.java).apply {
                            action = BusAlertService.ACTION_UPDATE_TRACKING
                            putExtra("busNo", busNo)
                            putExtra("stationName", stationName)
                            putExtra("remainingMinutes", remainingMinutes)
                            putExtra("currentStation", currentStation)
                            putExtra("routeId", routeId)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "버스 추적 알림 업데이트 오류: ${e.message}", e)
                        result.error("NOTIFICATION_ERROR", "버스 추적 알림 업데이트 중 오류 발생: ${e.message}", null)
                    }
                }
                "registerBusArrivalReceiver" -> {
                    try {
                        // BusArrivalReceiver registration is not directly available
                        // This functionality may need to be implemented differently
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
                "stopBusTracking" -> {
                    val busNo = call.argument<String>("busNo") ?: ""
                    val routeId = call.argument<String>("routeId") ?: ""
                    val stationId = call.argument<String>("stationId") ?: ""
                    val stationName = call.argument<String>("stationName") ?: ""
                    try {
                        Log.i(TAG, "버스 추적 중지 요청: Bus=$busNo, Route=$routeId, Station=$stationName")

                        // 1. 포그라운드 알림 취소
                        busAlertService?.cancelOngoingTracking()

                        // 2. 추적 중지
                        busAlertService?.stopTrackingForRoute(routeId, stationId, busNo)

                        // 3. Flutter 측에 알림 취소 이벤트 전송
                        try {
                            val alarmCancelData = mapOf(
                                "busNo" to busNo,
                                "routeId" to routeId,
                                "stationName" to stationName
                            )
                            _methodChannel?.invokeMethod("onAlarmCanceledFromNotification", alarmCancelData)
                            Log.i(TAG, "Flutter 측에 알람 취소 알림 전송 완료: $busNo, $routeId")
                        } catch (e: Exception) {
                            Log.e(TAG, "Flutter 측에 알람 취소 알림 전송 오류: ${e.message}")
                        }

                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "버스 추적 중지 오류: ${e.message}", e)
                        result.error("STOP_ERROR", "버스 추적 중지 실패: ${e.message}", null)
                    }
                }
                "startBusMonitoringService" -> {
                    val routeId = call.argument<String>("routeId") ?: ""
                    var stationId = call.argument<String>("stationId") ?: ""
                    val stationName = call.argument<String>("stationName") ?: ""
                    val busNo = call.argument<String>("busNo") ?: ""

                    try {
                        Log.i(TAG, "버스 모니터링 서비스 시작 요청: Bus=$busNo, Route=$routeId, Station=$stationName")

                        if (routeId.isEmpty() || stationName.isEmpty() || busNo.isEmpty()) {
                            result.error("INVALID_ARGUMENT", "필수 인자가 누락되었습니다", null)
                            return@setMethodCallHandler
                        }

                        // stationId 보정 - 빈 값으로 설정하여 BusAlertService에서 자동 해결하도록 함
                        if (stationId.isEmpty() || stationId == routeId) {
                            stationId = ""
                            Log.d(TAG, "stationId 보정: $stationName → BusAlertService에서 자동 해결")
                        }

                        // 1. 모니터링 노선 추가
                        busAlertService?.addMonitoredRoute(routeId, stationId, stationName)

                        // 2. 포그라운드 서비스 시작
                        val intent = Intent(this@MainActivity, BusAlertService::class.java).apply {
                            action = BusAlertService.ACTION_START_TRACKING_FOREGROUND
                            putExtra("routeId", routeId)
                            putExtra("stationId", stationId)
                            putExtra("stationName", stationName)
                            putExtra("busNo", busNo)
                            putExtra("remainingMinutes", 5) // 기본값
                        }

                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                            Log.i(TAG, "버스 모니터링 서비스 시작됨 (startForegroundService)")
                        } else {
                            startService(intent)
                            Log.i(TAG, "버스 모니터링 서비스 시작됨 (startService)")
                        }

                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "버스 모니터링 서비스 시작 오류: ${e.message}", e)
                        result.error("SERVICE_ERROR", "버스 모니터링 서비스 시작 실패: ${e.message}", null)
                    }
                }
                "stopBusMonitoringService" -> {
                    try {
                        Log.i(TAG, "버스 모니터링 서비스 중지 요청")

                        // 1. 추적 중지
                        busAlertService?.stopTracking()

                        // 2. 포그라운드 알림 취소
                        busAlertService?.cancelOngoingTracking()

                        // 3. TTS 추적 중지
                        busAlertService?.stopTtsTracking(forceStop = true)

                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "버스 모니터링 서비스 중지 오류: ${e.message}", e)
                        result.error("STOP_ERROR", "버스 모니터링 서비스 중지 실패: ${e.message}", null)
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

                            // 데이터베이스 초기화 확인
                            val databaseHelper = DatabaseHelper.getInstance(this@MainActivity)

                            // 데이터베이스 재설치 시도 (오류 발생 시)
                            try {
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
                            } catch (e: SQLiteException) {
                                // SQLite 오류 발생 시 데이터베이스 재설치 시도
                                Log.e(TAG, "SQLite 오류 발생: ${e.message}. 데이터베이스 재설치 시도", e)
                                databaseHelper.forceReinstallDatabase()

                                // 재설치 후 다시 시도
                                val nearbyStations = databaseHelper.searchStations(
                                    searchText = "",
                                    latitude = latitude,
                                    longitude = longitude,
                                    radiusInMeters = radiusMeters
                                )
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
                                }
                                result.success(jsonArray.toString())
                            }
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
                            val jsonString = runBlocking { busApiService.getStationInfo(stationId) }
                            Log.d(TAG, "정류장 정보 조회 완료: $stationId")
                            result.success(jsonString)
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
                "cancelAlarmByRoute" -> {
                    val busNo = call.argument<String>("busNo")
                    val stationName = call.argument<String>("stationName")
                    val routeId = call.argument<String>("routeId")

                    if (routeId != null) {
                        Log.i(TAG, "Flutter에서 알람 취소 요청 받음 (Native Handling): Bus=$busNo, Station=$stationName, Route=$routeId")
                        // --- 수정된 부분: Intent를 사용하여 서비스에 중지 명령 전달 ---
                        val stopIntent = Intent(this, BusAlertService::class.java).apply {
                            action = BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING // Use the new action
                            putExtra("routeId", routeId) // Pass the routeId to stop
                        }
                        try {
                             if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                 startForegroundService(stopIntent)
                             } else {
                                 startService(stopIntent)
                             }
                             Log.i(TAG,"BusAlertService로 '$routeId' 추적 중지 Intent 전송 완료")
                             result.success(true) // Acknowledge the call
                        } catch (e: Exception) {
                             Log.e(TAG, "BusAlertService로 추적 중지 Intent 전송 실패: ${e.message}", e)
                             result.error("SERVICE_START_FAILED", "Failed to send stop command to service.", e.message)
                        }
                        // --- 수정 끝 ---
                    } else {
                        Log.e(TAG, "'cancelAlarmByRoute' 호출 오류: routeId가 null입니다.")
                        result.error("INVALID_ARGUMENT", "routeId cannot be null.", null)
                    }
                }
                "showNotification" -> {
                    val id = call.argument<Int>("id") ?: 0
                    val busNo = call.argument<String>("busNo") ?: ""
                    val stationName = call.argument<String>("stationName") ?: ""
                    val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
                    val currentStation = call.argument<String>("currentStation") ?: ""
                    val payload = call.argument<String>("payload")
                    try {
                        val routeId = call.argument<String>("routeId")
                        val allBusesSummary = call.argument<String>("allBusesSummary")

                        // Build notification content
                        val title = if (remainingMinutes <= 0) {
                            "${busNo}번 버스 도착 알람"
                        } else {
                            "${busNo}번 버스 알람"
                        }
                        val contentText = if (remainingMinutes <= 0) {
                            "${busNo}번 버스가 ${stationName} 정류장에 곧 도착합니다."
                        } else {
                            "${busNo}번 버스가 약 ${remainingMinutes}분 후 도착 예정입니다."
                        }
                        val subText = if (currentStation.isNotEmpty()) "현재 위치: $currentStation" else null

                        // Intent to open app
                        val openAppIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
                            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
                        }
                        val pendingIntent = if (openAppIntent != null) PendingIntent.getActivity(
                            this, id, openAppIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        ) else null

                        // Cancel action - 수정: 특정 알람만 해제하도록 변경
                        val cancelIntent = Intent(this, BusAlertService::class.java).apply {
                            if (routeId != null) {
                                action = BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
                                putExtra("routeId", routeId)
                                putExtra("busNo", busNo)
                                putExtra("stationName", stationName)
                            } else {
                                action = BusAlertService.ACTION_STOP_TRACKING
                            }
                            putExtra("notificationId", id)
                        }
                        val cancelPendingIntent = PendingIntent.getService(
                            this, id + 1, cancelIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )

                        val builder = NotificationCompat.Builder(this, ALARM_NOTIFICATION_CHANNEL_ID)
                            .setContentTitle(title)
                            .setContentText(contentText)
                            .setSmallIcon(R.mipmap.ic_launcher)
                            .setPriority(NotificationCompat.PRIORITY_MAX)
                            .setCategory(NotificationCompat.CATEGORY_ALARM)
                            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                            .setColor(ContextCompat.getColor(this, R.color.alert_color))
                            .setAutoCancel(true)
                            .setDefaults(NotificationCompat.DEFAULT_ALL)
                            .addAction(R.drawable.ic_cancel, "종료", cancelPendingIntent)
                        if (pendingIntent != null) builder.setContentIntent(pendingIntent)
                        if (subText != null) builder.setSubText(subText)

                        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        notificationManager.notify(id, builder.build())
                        Log.d(TAG, "✅ showNotification: Notification shown for alarm ID: $id")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "알림 표시 오류: ${e.message}", e)
                        result.error("NOTIFICATION_ERROR", "알림 표시 중 오류 발생: ${e.message}", null)
                    }
                }
                "scheduleNativeAlarm" -> {
                    val alarmId = call.argument<Int>("alarmId") ?: 0
                    val busNo = call.argument<String>("busNo") ?: ""
                    val stationName = call.argument<String>("stationName") ?: ""
                    val routeId = call.argument<String>("routeId") ?: ""
                    val stationId = call.argument<String>("stationId") ?: ""
                    val useTTS = call.argument<Boolean>("useTTS") ?: true
                    val hour = call.argument<Int>("hour") ?: 0
                    val minute = call.argument<Int>("minute") ?: 0
                    val repeatDays = call.argument<ArrayList<Int>>("repeatDays")?.toIntArray() ?: intArrayOf()
                    
                    if (busNo.isBlank() || stationName.isBlank() || routeId.isBlank() || stationId.isBlank() || repeatDays.isEmpty()) {
                        result.error("INVALID_ARGUMENT", "필수 인자가 누락되었습니다", null)
                        return@setMethodCallHandler
                    }
                    
                    try {
                        val workManager = androidx.work.WorkManager.getInstance(applicationContext)
                        val inputData = androidx.work.Data.Builder()
                            .putString("taskName", "scheduleAlarmManager")
                            .putInt("alarmId", alarmId)
                            .putString("busNo", busNo)
                            .putString("stationName", stationName)
                            .putString("routeId", routeId)
                            .putString("stationId", stationId)
                            .putBoolean("useTTS", useTTS)
                            .putInt("hour", hour)
                            .putInt("minute", minute)
                            .putIntArray("repeatDays", repeatDays)
                            .build()
                            
                        val workRequest = androidx.work.OneTimeWorkRequestBuilder<com.example.daegu_bus_app.workers.BackgroundWorker>()
                            .setInputData(inputData)
                            .addTag("autoAlarmScheduling_${alarmId}") // 태그 추가
                            .build()
                        
                        workManager.enqueue(workRequest)
                        Log.d(TAG, "✅ Native AlarmManager 스케줄링 요청 완료 (WorkManager 경유)")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Native AlarmManager 스케줄링 요청 실패: ${e.message}", e)
                        result.error("SCHEDULE_ERROR", "Failed to schedule native alarm", e.message)
                    }
                }
                "stopStationTracking" -> {
                    try {
                        Log.i(TAG, "StationTrackingService 중지 요청 받음")
                        val intent = Intent(this, StationTrackingService::class.java).apply {
                            action = StationTrackingService.ACTION_STOP_TRACKING
                        }
                        startService(intent)
                        Log.i(TAG, "StationTrackingService 중지 명령 전송 완료")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "StationTrackingService 중지 오류: ${e.message}", e)
                        result.error("SERVICE_ERROR", "StationTrackingService 중지 중 오류 발생: ${e.message}", null)
                    }
                }
                "stopAutoAlarm" -> {
                    val busNo = call.argument<String>("busNo") ?: ""
                    val stationName = call.argument<String>("stationName") ?: ""
                    val routeId = call.argument<String>("routeId") ?: ""
                    
                    try {
                        Log.i(TAG, "자동알람 중지 요청 (stopAutoAlarm): Bus=$busNo, Station=$stationName, Route=$routeId")
                        
                        // 1. BusAlertService에 자동알람 중지 인텐트 전송
                        val stopAutoAlarmIntent = Intent(this, BusAlertService::class.java).apply {
                            action = BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
                            putExtra("routeId", routeId)
                            putExtra("busNo", busNo)
                            putExtra("stationName", stationName)
                            putExtra("isAutoAlarm", true)
                        }
                        startService(stopAutoAlarmIntent)
                        Log.i(TAG, "✅ BusAlertService 자동알람 중지 인텐트 전송 완료")
                        
                        // 2. Flutter 측에 자동알람 중지 완료 이벤트 전송
                        try {
                            val autoAlarmCancelData = mapOf(
                                "busNo" to busNo,
                                "stationName" to stationName,
                                "routeId" to routeId,
                                "isAutoAlarm" to true
                            )
                            _methodChannel?.invokeMethod("onAutoAlarmStopped", autoAlarmCancelData)
                            Log.i(TAG, "✅ Flutter 측에 자동알람 중지 이벤트 전송 완료")
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Flutter 측 자동알람 중지 이벤트 전송 오류: ${e.message}")
                        }
                        
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ 자동알람 중지 오류: ${e.message}", e)
                        result.error("STOP_AUTO_ALARM_ERROR", "자동알람 중지 실패: ${e.message}", null)
                    }
                }
                "cancelOngoingTracking" -> {
                    try {
                        Log.i(TAG, "Flutter에서 진행 중 추적 취소 요청 받음")
                        busAlertService?.cancelOngoingTracking()
                        notificationHandler.cancelOngoingTrackingNotification()
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "진행 중 추적 취소 오류: ${e.message}", e)
                        result.error("CANCEL_ERROR", "진행 중 추적 취소 실패: ${e.message}", null)
                    }
                }
                "cancelAllNotifications" -> {
                    try {
                        Log.i(TAG, "Flutter에서 모든 알림 취소 요청 받음")
                        // 1. BusAlertService에서 모든 추적 중지
                        busAlertService?.stopTracking()
                        
                        // 2. NotificationHandler를 통한 모든 알림 취소
                        notificationHandler.cancelAllNotifications()
                        
                        // 3. 포그라운드 알림 취소
                        busAlertService?.cancelOngoingTracking()
                        
                        // 4. Flutter 측에 모든 알람 취소 이벤트 전송
                        try {
                            _methodChannel?.invokeMethod("onAllAlarmsCanceled", null)
                            Log.i(TAG, "Flutter 측에 모든 알람 취소 알림 전송 완료")
                        } catch (e: Exception) {
                            Log.e(TAG, "Flutter 측에 모든 알람 취소 알림 전송 오류: ${e.message}")
                        }
                        
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "모든 알림 취소 오류: ${e.message}", e)
                        result.error("CANCEL_ALL_ERROR", "모든 알림 취소 실패: ${e.message}", null)
                    }
                }
                "stopSpecificTracking" -> {
                    try {
                        val busNo = call.argument<String>("busNo") ?: ""
                        val routeId = call.argument<String>("routeId") ?: ""
                        val stationName = call.argument<String>("stationName") ?: ""
                        
                        Log.i(TAG, "Flutter에서 특정 추적 중지 요청: Bus=$busNo, Route=$routeId, Station=$stationName")
                        
                        // BusAlertService에서 특정 추적 중지
                        if (busAlertService != null) {
                            busAlertService?.stopTrackingForRoute(routeId, busNo, stationName, true)
                            Log.i(TAG, "BusAlertService 특정 추적 중지 완료: $routeId")
                        } else {
                            // 서비스가 null인 경우 인텐트로 중지 요청
                            val stopIntent = Intent(this, BusAlertService::class.java).apply {
                                action = BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
                                putExtra("routeId", routeId)
                                putExtra("busNo", busNo)
                                putExtra("stationName", stationName)
                            }
                            startService(stopIntent)
                            Log.i(TAG, "특정 추적 중지 인텐트 전송 완료")
                        }
                        
                        // NotificationHandler를 통한 특정 알림 취소
                        try {
                            notificationHandler.cancelNotification(routeId.hashCode())
                            Log.i(TAG, "NotificationHandler 특정 알림 취소 완료")
                        } catch (e: Exception) {
                            Log.e(TAG, "NotificationHandler 특정 알림 취소 오류: ${e.message}")
                        }
                        
                        // Flutter 측에 특정 알람 취소 이벤트 전송
                        try {
                            val alarmCancelData = mapOf(
                                "busNo" to busNo,
                                "routeId" to routeId,
                                "stationName" to stationName
                            )
                            _methodChannel?.invokeMethod("onAlarmCanceledFromNotification", alarmCancelData)
                            Log.i(TAG, "Flutter 측에 특정 알람 취소 알림 전송 완료")
                        } catch (e: Exception) {
                            Log.e(TAG, "Flutter 특정 알람 취소 알림 전송 오류: ${e.message}")
                        }
                        
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "특정 추적 중지 오류: ${e.message}", e)
                        result.error("STOP_SPECIFIC_ERROR", "특정 추적 중지 실패: ${e.message}", null)
                    }
                }
                "speakTTS" -> {
                    val message = call.argument<String>("message") ?: ""
                    val isHeadphoneMode = call.argument<Boolean>("isHeadphoneMode") ?: false
                    val forceSpeaker = call.argument<Boolean>("forceSpeaker") ?: false
                    if (message.isEmpty()) {
                         result.error("INVALID_ARGUMENT", "메시지가 비어있습니다", null)
                         return@setMethodCallHandler
                    }
                    try {
                        if (busAlertService != null) {
                            // 강제 스피커 모드인 경우 이어폰 체크 무시
                            if (forceSpeaker) {
                                Log.d(TAG, "🔊 강제 스피커 모드로 TTS 발화: $message")
                                busAlertService?.speakTts(message, earphoneOnly = false, forceSpeaker = true)
                            } else {
                                // BusAlertService의 speakTts 호출 (오디오 포커스 관리 포함)
                                busAlertService?.speakTts(message, earphoneOnly = isHeadphoneMode, forceSpeaker = false)
                            }
                        } else {
                            // BusAlertService가 null인 경우 MainActivity의 TTS 사용
                            if (::tts.isInitialized) {
                                tts.speak(message, TextToSpeech.QUEUE_FLUSH, null, message.hashCode().toString())
                                Log.d(TAG, "TTS 발화 (대안 방법): $message")
                            } else {
                                Log.w(TAG, "TTS가 초기화되지 않아 발화 실패")
                            }
                        }
                        result.success(true) // 비동기 호출이므로 일단 성공으로 응답
                    } catch (e: Exception) {
                        Log.e(TAG, "TTS 발화 오류: ${e.message}", e)
                        result.success(true) // TTS 실패도 성공으로 처리
                    }
                }
                "setAudioOutputMode" -> {
                    val mode = call.argument<Int>("mode") ?: 2
                    try {
                        if (busAlertService != null) {
                            busAlertService?.setAudioOutputMode(mode)
                        } else {
                            Log.d(TAG, "오디오 출력 모드 설정 요청 (대안): $mode")
                        }
                        Log.d(TAG, "오디오 출력 모드 설정 요청: $mode")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "오디오 모드 설정 오류: ${e.message}", e)
                        result.success(true)
                    }
                }
                "setVolume" -> {
                    val volume = call.argument<Double>("volume") ?: 1.0
                    try {
                        if (busAlertService != null) {
                            busAlertService?.setTtsVolume(volume)
                        } else {
                            Log.d(TAG, "TTS 볼륨 설정 (대안): ${volume * 100}%")
                        }
                        Log.d(TAG, "TTS 볼륨 설정: ${volume * 100}%")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "볼륨 설정 오류: ${e.message}")
                        result.success(true)
                    }
                }
                "stopTTS" -> {
                    try {
                        if (busAlertService != null) {
                            // BusAlertService의 stopTtsTracking을 호출하여 TTS 중지
                            busAlertService?.stopTtsTracking(forceStop = true)
                        } else {
                            // MainActivity TTS 중지
                            if (::tts.isInitialized) {
                                tts.stop()
                                Log.d(TAG, "TTS 중지 (대안 방법)")
                            }
                        }
                        Log.d(TAG, "네이티브 TTS 중지 요청")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "TTS 중지 오류: ${e.message}", e)
                        result.success(true)
                    }
                }
                "isHeadphoneConnected" -> {
                    try {
                        val isConnected = if (busAlertService != null) {
                            busAlertService?.isHeadsetConnected() ?: false
                        } else {
                            // 대안: AudioManager를 사용하여 이어폰 연결 상태 확인
                            val audioDevices = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                            audioDevices.any { device ->
                                device.type == AudioDeviceInfo.TYPE_WIRED_HEADPHONES ||
                                device.type == AudioDeviceInfo.TYPE_WIRED_HEADSET ||
                                device.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                                device.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO
                            }
                        }
                        Log.d(TAG, "🎧 이어폰 연결 상태 확인: $isConnected")
                        result.success(isConnected)
                    } catch (e: Exception) {
                        Log.e(TAG, "🎧 이어폰 연결 상태 확인 오류: ${e.message}")
                        result.success(false)
                    }
                }
                "startTtsTracking" -> {
                    // Flutter에서 요청한 TTS 트래킹 시작 처리
                    val routeId = call.argument<String>("routeId") ?: ""
                    val stationId = call.argument<String>("stationId") ?: ""
                    val busNo = call.argument<String>("busNo") ?: ""
                    val stationName = call.argument<String>("stationName") ?: ""
                    val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
                    if (routeId.isEmpty() || stationId.isEmpty() || busNo.isEmpty() || stationName.isEmpty()) {
                        result.error("INVALID_ARGUMENT", "startTtsTracking requires routeId, stationId, busNo, stationName", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val ttsIntent = Intent(this, TTSService::class.java).apply {
                            action = "START_TTS_TRACKING"
                            putExtra("routeId", routeId)
                            putExtra("stationId", stationId)
                            putExtra("busNo", busNo)
                            putExtra("stationName", stationName)
                            putExtra("remainingMinutes", remainingMinutes)
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(ttsIntent)
                        } else {
                            startService(ttsIntent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "startTtsTracking error: ${e.message}", e)
                        result.error("TTS_ERROR", "startTtsTracking failed: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STATION_TRACKING_CHANNEL).setMethodCallHandler { call, result ->
            Log.d(TAG, "STATION_TRACKING_CHANNEL: method=${call.method}, args=${call.arguments}")
            if (call.method == "getBusInfo") {
                val routeId = call.argument<String>("routeId") ?: ""
                var stationId = call.argument<String>("stationId") ?: ""
                // stationId가 10자리 숫자가 아니면 변환 시도 (wincId -> stationId)
                if (stationId.length < 10 || !stationId.startsWith("7")) {
                    // BusApiService의 getStationIdFromBsId를 동기로 호출
                    try {
                        val convertedId = runBlocking { busApiService.getStationIdFromBsId(stationId) }
                        if (!convertedId.isNullOrEmpty()) {
                            Log.d(TAG, "STATION_TRACKING_CHANNEL: 변환된 stationId: $stationId -> $convertedId")
                            stationId = convertedId
                        } else {
                            Log.e(TAG, "STATION_TRACKING_CHANNEL: stationId 변환 실패: $stationId")
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "STATION_TRACKING_CHANNEL: stationId 변환 중 오류: ${e.message}", e)
                    }
                }
                try {
                    val jsonString = runBlocking { busApiService.getStationInfo(stationId) }
                    Log.d(TAG, "STATION_TRACKING rawData: $jsonString")
                    val routesArray = try {
                        JSONArray(jsonString)
                    } catch (e: org.json.JSONException) {
                        JSONObject(jsonString).optJSONObject("body")?.optJSONArray("list") ?: JSONArray()
                    }
                    var remainingMinutes = Int.MAX_VALUE
                    var currentStation = ""
                    var found = false
                    for (i in 0 until routesArray.length()) {
                        val routeObj = routesArray.getJSONObject(i)
                        Log.d(TAG, "STATION_TRACKING routeObj[$i]: $routeObj")
                        val buses = routeObj.optJSONArray("arrList") ?: continue
                        for (j in 0 until buses.length()) {
                            val busObj = buses.getJSONObject(j)
                            Log.d(TAG, "STATION_TRACKING busObj[$j]: $busObj")
                            // routeId가 일치하는 버스 우선, 없으면 첫 번째 버스 정보 사용
                            if (busObj.optString("routeId") == routeId || !found) {
                                val estState = busObj.optString("arrState")
                                currentStation = busObj.optString("bsNm")
                                remainingMinutes = when {
                                    estState == "곧 도착" -> 0
                                    estState == "전전" -> 0  // "전전"은 곧 도착으로 처리
                                    estState == "운행종료" -> -1
                                    estState.contains("분") -> estState.filter { it.isDigit() }.toIntOrNull() ?: Int.MAX_VALUE
                                    estState.all { it.isDigit() } -> estState.toIntOrNull() ?: Int.MAX_VALUE
                                    else -> Int.MAX_VALUE
                                }
                                found = busObj.optString("routeId") == routeId
                                if (found) break
                            }
                        }
                        if (found) break
                    }
                    if (remainingMinutes == Int.MAX_VALUE) remainingMinutes = -1
                    Log.d(TAG, "getBusInfo returning remainingMinutes=$remainingMinutes, currentStation=$currentStation")
                    result.success(mapOf("remainingMinutes" to remainingMinutes, "currentStation" to currentStation))
                } catch (e: Exception) {
                    Log.e(TAG, "getBusInfo error: ${e.message}", e)
                    result.error("BUS_INFO_ERROR", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BUS_TRACKING_CHANNEL).setMethodCallHandler { call, result ->
            Log.d(TAG, "BUS_TRACKING_CHANNEL 호출: ${call.method}")
            when (call.method) {
                "updateBusTrackingNotification" -> {
                    val busNo = call.argument<String>("busNo") ?: ""
                    val stationName = call.argument<String>("stationName") ?: ""
                    val remainingMinutes = call.argument<Int>("remainingMinutes") ?: 0
                    val currentStation = call.argument<String>("currentStation") ?: ""
                    val routeId = call.argument<String>("routeId") ?: ""

                    try {
                        Log.d(TAG, "Flutter에서 버스 추적 알림 업데이트 요청 (BUS_TRACKING_CHANNEL): $busNo, 남은 시간: ${remainingMinutes}분, 현재 위치: $currentStation")

                        // 여러 방법으로 알림 업데이트 시도 (병렬 실행)

                        // 1. BusAlertService를 통해 알림 업데이트 (직접 메서드 호출)
                        if (busAlertService != null) {
                            // 1.1. updateTrackingNotification 메서드 직접 호출 (가장 확실한 방법)
                            busAlertService?.updateTrackingNotification(
                            busNo = busNo,
                            stationName = stationName,
                            remainingMinutes = remainingMinutes,
                            currentStation = currentStation,
                            routeId = routeId
                            )
                        Log.d(TAG, "🚌 업데이트 완료 - 버스 $busNo, 현재 위치: $currentStation")

                            // 1.2. updateTrackingInfoFromFlutter 메서드 직접 호출 (백업)
                            busAlertService?.updateTrackingInfoFromFlutter(
                                routeId = routeId,
                                busNo = busNo,
                                stationName = stationName,
                                remainingMinutes = remainingMinutes,
                                currentStation = currentStation
                            )

                            // 1.3. showOngoingBusTracking 메서드 직접 호출 (추가 백업)
                            busAlertService?.showOngoingBusTracking(
                                busNo = busNo,
                                stationName = stationName,
                                remainingMinutes = remainingMinutes,
                                currentStation = currentStation,
                                isUpdate = true,
                                notificationId = BusAlertService.ONGOING_NOTIFICATION_ID,
                                allBusesSummary = null,
                                routeId = routeId
                            )

                            Log.d(TAG, "✅ 버스 추적 알림 직접 메서드 호출 완료")
                        }

                        // 2. 인텐트를 통한 업데이트 (서비스가 null이거나 직접 호출이 실패한 경우를 대비)
                        // 2.1. ACTION_UPDATE_TRACKING 인텐트 전송
                        val updateIntent = Intent(this, BusAlertService::class.java).apply {
                            action = BusAlertService.ACTION_UPDATE_TRACKING
                            putExtra("busNo", busNo)
                            putExtra("stationName", stationName)
                            putExtra("remainingMinutes", remainingMinutes)
                            putExtra("currentStation", currentStation)
                            putExtra("routeId", routeId)
                        }

                        // Android 버전에 따라 적절한 방법으로 서비스 시작
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(updateIntent)
                        } else {
                            startService(updateIntent)
                        }
                        Log.d(TAG, "✅ 버스 추적 알림 업데이트 인텐트 전송 완료")

                        // 3. BusAlertService가 null인 경우 서비스 시작 및 바인딩 시도
                        if (busAlertService == null) {
                            try {
                                val serviceIntent = Intent(this, BusAlertService::class.java)
                                startService(serviceIntent)
                                bindService(serviceIntent, serviceConnection, Context.BIND_AUTO_CREATE)
                                Log.d(TAG, "✅ BusAlertService 시작 및 바인딩 요청 완료")
                            } catch (e: Exception) {
                                Log.e(TAG, "❌ BusAlertService 초기화 실패: ${e.message}", e)
                            }
                        }

                        // 4. 1초 후 지연 업데이트 시도 (백업)
                        android.os.Handler(mainLooper).postDelayed({
                            try {
                                // 지연 인텐트 전송
                                val delayedIntent = Intent(this, BusAlertService::class.java).apply {
                                    action = BusAlertService.ACTION_UPDATE_TRACKING
                                    putExtra("busNo", busNo)
                                    putExtra("stationName", stationName)
                                    putExtra("remainingMinutes", remainingMinutes)
                                    putExtra("currentStation", currentStation)
                                    putExtra("routeId", routeId)
                                }
                                startService(delayedIntent)
                                Log.d(TAG, "✅ 지연 업데이트 인텐트 전송 완료")

                                // 서비스가 초기화되었으면 직접 메서드 호출도 시도
                                if (busAlertService != null) {
                                    busAlertService?.updateTrackingNotification(
                                        busNo = busNo,
                                        stationName = stationName,
                                        remainingMinutes = remainingMinutes,
                                        currentStation = currentStation,
                                        routeId = routeId
                                    )
                                    Log.d(TAG, "✅ 지연 직접 메서드 호출 완료")
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "❌ 지연 업데이트 오류: ${e.message}", e)
                            }
                        }, 1000)

                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ 버스 추적 알림 업데이트 오류: ${e.message}", e)

                        // 오류 발생 시에도 인텐트 전송 시도 (최후의 수단)
                        try {
                            val fallbackIntent = Intent(this, BusAlertService::class.java).apply {
                                action = BusAlertService.ACTION_UPDATE_TRACKING
                                putExtra("busNo", busNo)
                                putExtra("stationName", stationName)
                                putExtra("remainingMinutes", remainingMinutes)
                                putExtra("currentStation", currentStation)
                                putExtra("routeId", routeId)
                            }
                            startService(fallbackIntent)
                            Log.d(TAG, "✅ 오류 후 인텐트 전송 완료")
                            result.success(true)
                        } catch (ex: Exception) {
                            Log.e(TAG, "❌ 오류 후 인텐트 전송 실패: ${ex.message}", ex)
                            result.error("UPDATE_ERROR", "버스 추적 알림 업데이트 실패: ${e.message}", null)
                        }
                    }
                }
                "stopBusTracking" -> {
                    val busNo = call.argument<String>("busNo") ?: ""
                    val routeId = call.argument<String>("routeId") ?: ""
                    val stationId = call.argument<String>("stationId") ?: ""
                    val stationName = call.argument<String>("stationName") ?: ""
                    try {
                        Log.i(TAG, "버스 추적 중지 요청 (BUS_TRACKING_CHANNEL): Bus=$busNo, Route=$routeId, Station=$stationName")

                        // stopTrackingForRoute만 호출 (내부에서 알림 취소 처리)
                        busAlertService?.stopTrackingForRoute(routeId, stationId, busNo)

                        // Flutter 측에 알림 취소 이벤트 전송
                        try {
                            val alarmCancelData = mapOf(
                                "busNo" to busNo,
                                "routeId" to routeId,
                                "stationName" to stationName
                            )
                            _methodChannel?.invokeMethod("onAlarmCanceledFromNotification", alarmCancelData)
                            Log.i(TAG, "Flutter 측에 알람 취소 알림 전송 완료: $busNo, $routeId")
                        } catch (e: Exception) {
                            Log.e(TAG, "Flutter 측에 알람 취소 알림 전송 오류: ${e.message}")
                        }

                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "버스 추적 중지 오류: ${e.message}", e)
                        result.error("STOP_ERROR", "버스 추적 중지 실패: ${e.message}", null)
                    }
                }
                "startStationTracking" -> {
                    val stationId = call.argument<String>("stationId")
                    val stationName = call.argument<String>("stationName")
                    if (stationId.isNullOrEmpty() || stationName.isNullOrEmpty()) {
                        Log.e(TAG, "startStationTracking 오류: stationId 또는 stationName 누락")
                        result.error("INVALID_ARGUMENT", "Station ID 또는 Station Name이 누락되었습니다.", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val intent = Intent(this, StationTrackingService::class.java).apply {
                            action = StationTrackingService.ACTION_START_TRACKING
                            putExtra(StationTrackingService.EXTRA_STATION_ID, stationId)
                            putExtra(StationTrackingService.EXTRA_STATION_NAME, stationName)
                        }
                        // Foreground 서비스 시작 방식 사용 고려 (Android 8 이상)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        Log.i(TAG, "StationTrackingService 시작 요청: $stationId ($stationName)")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "StationTrackingService 시작 오류: ${e.message}", e)
                        result.error("SERVICE_ERROR", "StationTrackingService 시작 중 오류 발생: ${e.message}", null)
                    }
                }
                "stopStationTracking" -> {
                    try {
                        Log.i(TAG, "StationTrackingService 중지 요청 받음")
                        val intent = Intent(this, StationTrackingService::class.java).apply {
                            action = StationTrackingService.ACTION_STOP_TRACKING
                        }
                        startService(intent)
                        Log.i(TAG, "StationTrackingService 중지 명령 전송 완료")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "StationTrackingService 중지 오류: ${e.message}", e)
                        result.error("SERVICE_ERROR", "StationTrackingService 중지 중 오류 발생: ${e.message}", null)
                    }
                }
                "stopAutoAlarm" -> {
                    val busNo = call.argument<String>("busNo") ?: ""
                    val stationName = call.argument<String>("stationName") ?: ""
                    val routeId = call.argument<String>("routeId") ?: ""
                    
                    try {
                        Log.i(TAG, "자동알람 중지 요청 (stopAutoAlarm): Bus=$busNo, Station=$stationName, Route=$routeId")
                        
                        // 1. BusAlertService에 자동알람 중지 인텐트 전송
                        val stopAutoAlarmIntent = Intent(this, BusAlertService::class.java).apply {
                            action = BusAlertService.ACTION_STOP_SPECIFIC_ROUTE_TRACKING
                            putExtra("routeId", routeId)
                            putExtra("busNo", busNo)
                            putExtra("stationName", stationName)
                            putExtra("isAutoAlarm", true)
                        }
                        startService(stopAutoAlarmIntent)
                        Log.i(TAG, "✅ BusAlertService 자동알람 중지 인텐트 전송 완료")
                        
                        // 2. Flutter 측에 자동알람 중지 완료 이벤트 전송
                        try {
                            val autoAlarmCancelData = mapOf(
                                "busNo" to busNo,
                                "stationName" to stationName,
                                "routeId" to routeId,
                                "isAutoAlarm" to true
                            )
                            _methodChannel?.invokeMethod("onAutoAlarmStopped", autoAlarmCancelData)
                            Log.i(TAG, "✅ Flutter 측에 자동알람 중지 이벤트 전송 완료")
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Flutter 측 자동알람 중지 이벤트 전송 오류: ${e.message}")
                        }
                        
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ 자동알람 중지 오류: ${e.message}", e)
                        result.error("STOP_AUTO_ALARM_ERROR", "자동알람 중지 실패: ${e.message}", null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 초기화 시도
        try {
            // BusAlertService 인스턴스 가져오기 (onCreate에서 이미 생성됨)
            busAlertService = BusAlertService.getInstance()
            busAlertService?.initialize()
        } catch (e: Exception) {
            Log.e(TAG, "알림 서비스 초기화 오류: ${e.message}", e)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        try {
            super.onCreate(savedInstanceState)
            
            // 싱글톤 인스턴스 설정
            instance = this
            
            Log.d("MainActivity", " MainActivity 생성")

            // 승차 완료 액션 처리
            if (intent?.action == "com.example.daegu_bus_app.BOARDING_COMPLETE") {
                handleBoardingComplete()
            }

            busApiService = BusApiService(this)
            audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
            notificationHelper = NotificationHelper(this)
            notificationHandler = NotificationHandler(this)

            // Create Notification Channel for Alarms
            createAlarmNotificationChannel()

            // TTS 초기화
            try {
                tts = TextToSpeech(this, this)
            } catch (e: Exception) {
                Log.e(TAG, "TTS 초기화 오류: ${e.message}", e)
            }

            // 알림 취소 이벤트 수신을 위한 브로드캐스트 리시버 등록
            registerNotificationCancelReceiver()

            try {
                // 서비스 시작 및 바인딩
                val serviceIntent = Intent(this, BusAlertService::class.java)
                startService(serviceIntent)
                bindService(serviceIntent, serviceConnection, Context.BIND_AUTO_CREATE)
                Log.d(TAG, "BusAlertService 시작 및 바인딩 요청 완료")
            } catch (e: Exception) {
                Log.e(TAG, "BusAlertService 초기화 실패: ${e.message}", e)
            }

            // 권한 요청 처리
            checkAndRequestPermissions()

            // 배터리 최적화 예외 요청
            requestBatteryOptimizationExemption()

        } catch (e: Exception) {
            Log.e(TAG, "MainActivity onCreate 오류: ${e.message}", e)
        }
    }

    private fun checkAndRequestPermissions() {
        // 알림 권한 확인 및 요청 (Android 13+)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
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

        // 위치 권한 확인 및 요청
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val fineLocationPermission = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_FINE_LOCATION
            )
            val coarseLocationPermission = ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.ACCESS_COARSE_LOCATION
            )

            if (fineLocationPermission != PackageManager.PERMISSION_GRANTED ||
                coarseLocationPermission != PackageManager.PERMISSION_GRANTED) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(
                        Manifest.permission.ACCESS_FINE_LOCATION,
                        Manifest.permission.ACCESS_COARSE_LOCATION
                    ),
                    LOCATION_PERMISSION_REQUEST_CODE
                )
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        when (requestCode) {
            LOCATION_PERMISSION_REQUEST_CODE -> {
                if (grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    Log.d(TAG, "위치 권한 승인됨")
                    // 권한이 승인되면 Flutter 측에 알림
                    _methodChannel?.invokeMethod("onLocationPermissionGranted", null)
                } else {
                    Log.d(TAG, "위치 권한 거부됨")
                    // 권한이 거부되면 Flutter 측에 알림
                    _methodChannel?.invokeMethod("onLocationPermissionDenied", null)
                }
            }
            NOTIFICATION_PERMISSION_REQUEST_CODE -> {
                if (grantResults.isNotEmpty() &&
                    grantResults[0] == PackageManager.PERMISSION_GRANTED) {
                    Log.d(TAG, "알림 권한 승인됨")
                } else {
                    Log.d(TAG, "알림 권한 거부됨")
                }
            }
        }
    }

    override fun onInit(status: Int) {
        // MainActivity의 TTS 초기화 로직은 유지 (초기 구동 시 필요할 수 있음)
        try {
            if (status == TextToSpeech.SUCCESS) {
                try {
                    tts.setLanguage(Locale.KOREAN)
                    tts.setSpeechRate(1.2f)
                    tts.setPitch(1.1f)
                    tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                        override fun onStart(utteranceId: String?) {
                            Log.d(TAG, "TTS 발화 시작: $utteranceId")
                        }

                        override fun onDone(utteranceId: String?) {
                            Log.d(TAG, "TTS 발화 완료: $utteranceId")
                        }

                        @Deprecated("Deprecated in Java")
                        override fun onError(utteranceId: String?) {
                            Log.e(TAG, "TTS 발화 오류: $utteranceId")
                        }

                        override fun onError(utteranceId: String?, errorCode: Int) {
                            Log.e(TAG, "TTS 발화 오류 ($errorCode): $utteranceId")
                            onError(utteranceId)
                        }
                    })
                    Log.d(TAG, "MainActivity TTS 초기화 성공")
                } catch (e: Exception) {
                    Log.e(TAG, "TTS 설정 오류: ${e.message}", e)
                }
            } else {
                Log.e(TAG, "MainActivity TTS 초기화 실패: $status")
            }
        } catch (e: Exception) {
            Log.e(TAG, "MainActivity TTS onInit 오류: ${e.message}", e)
        }
    }

    override fun onDestroy() {
        try {
            // 싱글톤 인스턴스 정리
            instance = null
            
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

            // 서비스 바인딩 해제
            try {
                unbindService(serviceConnection)
                Log.d(TAG, "BusAlertService 바인딩 해제 완료")
            } catch (e: Exception) {
                Log.e(TAG, "서비스 바인딩 해제 오류: ${e.message}")
            }

            // 브로드캠스트 리시버 해제
            unregisterAlarmCancelReceiver()

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

    private fun unregisterAlarmCancelReceiver() {
        try {
            alarmCancelReceiver?.let {
                unregisterReceiver(it)
                alarmCancelReceiver = null
                Log.d(TAG, "알림 취소 브로드캐스트 리시버 해제 완료")
            }
        } catch (e: Exception) {
            Log.e(TAG, "알림 취소 리시버 해제 오류: ${e.message}", e)
        }
    }

    // Create notification channel for alarms
    private fun createAlarmNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val name = "Bus Alarms"
            val descriptionText = "Notifications for scheduled bus alarms"
            val importance = NotificationManager.IMPORTANCE_HIGH // 높은 우선순위
            val channel = NotificationChannel(ALARM_NOTIFICATION_CHANNEL_ID, name, importance).apply {
                description = descriptionText
                enableLights(true)
                lightColor = Color.RED
                enableVibration(true)
                setShowBadge(true) // 배지 표시
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC // 잠금화면에서 표시
                setBypassDnd(true) // 방해금지 모드에서도 알림 표시
            }
            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
            Log.d(TAG, "Alarm notification channel created with lockscreen support: $ALARM_NOTIFICATION_CHANNEL_ID")
        }
    }

    private fun setupNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                ALARM_NOTIFICATION_CHANNEL_ID,
                "Bus Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Notifications for bus arrivals and alarms"
                enableLights(true)
                lightColor = Color.BLUE
                enableVibration(true)
                setShowBadge(true)
            }

            val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            notificationManager.createNotificationChannel(channel)
        }
    }

    private fun handleNotificationAction(action: String, intent: Intent) {
        when (action) {
            "cancel_alarm" -> {
                val alarmId = intent.getIntExtra("alarm_id", -1)
                if (alarmId != -1) {
                    // 알림 취소
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancel(alarmId)

                    // TTS 서비스 중지
                    var ttsIntent = Intent(this, TTSService::class.java)
                    ttsIntent.action = "STOP_TTS"
                    startService(ttsIntent)

                    // 현재 알람만 취소 상태로 저장
                    val prefs = getSharedPreferences("alarm_preferences", Context.MODE_PRIVATE)
                    val editor = prefs.edit()
                    editor.putBoolean("alarm_cancelled_$alarmId", true).apply()

                    // 토스트 메시지로 알림
                    Toast.makeText(
                        this,
                        "현재 알람이 취소되었습니다",
                        Toast.LENGTH_SHORT
                    ).show()

                    Log.d(TAG, "Alarm notification cancelled: $alarmId (one-time cancel)")
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val action = intent.action
        if (action != null) {
            handleNotificationAction(action, intent)
        }
    }

    // 브로드캐스트 리시버 등록 메소드
    private fun registerNotificationCancelReceiver() {
        try {
            val intentFilter = IntentFilter().apply {
                addAction("com.example.daegu_bus_app.NOTIFICATION_CANCELLED")
                addAction("com.example.daegu_bus_app.ALL_TRACKING_CANCELLED")
                addAction("com.example.daegu_bus_app.STOP_AUTO_ALARM") // 자동알람 중지 액션 추가
                // 필요하다면 다른 액션도 추가
            }
            // Android 버전에 따른 리시버 등록 방식 분기 (Exported/Not Exported)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    registerReceiver(notificationCancelReceiver, intentFilter, Context.RECEIVER_NOT_EXPORTED)
                } else {
                    registerReceiver(notificationCancelReceiver, intentFilter)
                }
                Log.d(TAG, "NotificationCancelReceiver 등록됨")
            } catch (e: Exception) {
                Log.e(TAG, "NotificationCancelReceiver 등록 오류: ${e.message}", e)
            }
        } catch (e: Exception) {
            Log.e(TAG, "알림 취소 이벤트 수신 리시버 등록 오류: ${e.message}", e)
        }
    }

    // 알림 취소 이벤트를 수신하는 브로드캐스트 리시버
    private val notificationCancelReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            try {
                val action = intent.action
                Log.d(TAG, "NotificationCancelReceiver: 액션 수신: $action")

                when (action) {
                    "com.example.daegu_bus_app.NOTIFICATION_CANCELLED" -> {
                        val routeId = intent.getStringExtra("routeId") ?: ""
                        val busNo = intent.getStringExtra("busNo") ?: ""
                        val stationName = intent.getStringExtra("stationName") ?: ""
                        val source = intent.getStringExtra("source") ?: "unknown"

                        Log.i(TAG, "알림 취소 이벤트 수신: Bus=$busNo, Route=$routeId, Station=$stationName, Source=$source")

                        // Flutter 측에 알림 취소 이벤트 전송
                        val alarmCancelData = mapOf(
                            "busNo" to busNo,
                            "routeId" to routeId,
                            "stationName" to stationName,
                            "source" to "notification"
                        )
                        _methodChannel?.invokeMethod("onAlarmCanceledFromNotification", alarmCancelData)
                        Log.i(TAG, "Flutter 측에 알람 취소 알림 전송 완료 (From BroadcastReceiver)")
                    }
                    "com.example.daegu_bus_app.ALL_TRACKING_CANCELLED" -> {
                        Log.i(TAG, "모든 추적 취소 이벤트 수신")

                        // Flutter 측에 모든 알림 취소 이벤트 전송
                        _methodChannel?.invokeMethod("onAllAlarmsCanceled", mapOf("source" to "notification"))
                        Log.i(TAG, "Flutter 측에 모든 알람 취소 알림 전송 완료")
                    }
                    "com.example.daegu_bus_app.STOP_AUTO_ALARM" -> {
                        val routeId = intent.getStringExtra("routeId") ?: ""
                        val busNo = intent.getStringExtra("busNo") ?: ""
                        val stationName = intent.getStringExtra("stationName") ?: ""

                        Log.i(TAG, "자동알람 중지 브로드캐스트 수신: Bus=$busNo, Route=$routeId, Station=$stationName")

                        // Flutter 측에 자동알람 중지 이벤트 전송
                        try {
                            val autoAlarmCancelData = mapOf(
                                "busNo" to busNo,
                                "stationName" to stationName,
                                "routeId" to routeId
                            )
                            _methodChannel?.invokeMethod("stopAutoAlarmFromBroadcast", autoAlarmCancelData)
                            Log.i(TAG, "✅ Flutter 측에 자동알람 중지 이벤트 전송 완료")
                        } catch (e: Exception) {
                            Log.e(TAG, "❌ Flutter 측 자동알람 중지 이벤트 전송 오류: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "알림 취소 이벤트 처리 중 오류: ${e.message}", e)
            }
        }
    }

    private fun unregisterNotificationCancelReceiver() {
        try {
            unregisterReceiver(notificationCancelReceiver)
            Log.d(TAG, "NotificationCancelReceiver 해제됨")
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "NotificationCancelReceiver 해제 시도 중 오류 (이미 해제되었거나 등록되지 않음): ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "NotificationCancelReceiver 해제 중 예외 발생: ${e.message}", e)
        }
    }

    // 노티피케이션 완전 중지
    private fun stopBusTrackingService() {
        Log.d(TAG, "버스 추적 서비스 완전 중지 시작")

        try {
            // 1. 서비스에 중지 명령 전송 (여러 방법으로 시도)
            val stopIntent = Intent(this, BusAlertService::class.java).apply {
                action = BusAlertService.ACTION_STOP_TRACKING
            }
            startService(stopIntent)
            Log.d(TAG, "✅ STOP_TRACKING 액션 전송")

            // 2. 강제 서비스 중지
            val serviceIntent = Intent(this, BusAlertService::class.java)
            stopService(serviceIntent)
            Log.d(TAG, "✅ 서비스 강제 중지 요청")

            // 3. TTS 서비스도 중지
            try {
                val ttsServiceIntent = Intent(this, TTSService::class.java)
                stopService(ttsServiceIntent)
                Log.d(TAG, "✅ TTS 서비스 중지")
            } catch (e: Exception) {
                Log.e(TAG, "TTS 서비스 중지 오류: ${e.message}")
            }

            // 4. 모든 알림 취소 (여러 방법으로 시도)
            try {
                val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                notificationManager.cancelAll()
                notificationManager.cancel(1001) // ONGOING_NOTIFICATION_ID
                notificationManager.cancel(9999) // AUTO_ALARM_NOTIFICATION_ID
                Log.d(TAG, "✅ 모든 알림 취소 완료 (NotificationManager)")
            } catch (e: Exception) {
                Log.e(TAG, "알림 취소 오류: ${e.message}")
            }

            // 5. NotificationManagerCompat으로도 시도 (백업)
            try {
                val notificationManagerCompat = NotificationManagerCompat.from(this)
                notificationManagerCompat.cancelAll()
                Log.d(TAG, "✅ 모든 알림 취소 완료 (NotificationManagerCompat)")
            } catch (e: Exception) {
                Log.e(TAG, "NotificationManagerCompat 알림 취소 오류: ${e.message}")
            }

            // 6. WorkManager 작업 취소
            try {
                val workManager = androidx.work.WorkManager.getInstance(this)
                workManager.cancelAllWork()
                Log.d(TAG, "✅ WorkManager 작업 취소")
            } catch (e: Exception) {
                Log.e(TAG, "WorkManager 작업 취소 오류: ${e.message}")
            }

            // 7. 지연된 추가 정리 작업
            Handler(Looper.getMainLooper()).postDelayed({
                try {
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    notificationManager.cancelAll()
                    Log.d(TAG, "✅ 지연된 알림 취소 완료")
                } catch (e: Exception) {
                    Log.e(TAG, "지연된 알림 취소 오류: ${e.message}")
                }
            }, 1000)

            Log.d(TAG, "✅ 버스 추적 서비스 완전 중지 완료")

        } catch (e: Exception) {
            Log.e(TAG, "서비스 중지 중 오류 발생", e)
        }
    }

    // 특정 버스 추적 중지
    private fun stopSpecificTracking(busNo: String, routeId: String, stationName: String) {
        Log.d(TAG, "특정 버스 추적 중지: $busNo, $routeId, $stationName")

        try {
            val intent = Intent(this, BusAlertService::class.java).apply {
                action = "com.example.daegu_bus_app.action.STOP_BUS_ALERT_TRACKING"
                putExtra("busNo", busNo)
                putExtra("routeId", routeId)
                putExtra("stationName", stationName)
                putExtra("stationId", "")
            }
            startService(intent)

            Log.d(TAG, "특정 버스 추적 중지 명령 전송 완료")

        } catch (e: Exception) {
            Log.e(TAG, "특정 추적 중지 중 오류 발생", e)

        }
    }

    override fun onResume() {
        super.onResume()
        registerNotificationCancelReceiver() // 리시버 등록
    }

    override fun onPause() {
        super.onPause()
        unregisterNotificationCancelReceiver() // 리시버 해제
    }



    // 배터리 최적화 예외 요청
    private fun requestBatteryOptimizationExemption() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val packageName = packageName
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                try {
                    val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                    startActivity(intent)
                    Log.d(TAG, "배터리 최적화 예외 요청 대화상자 표시")
                } catch (e: Exception) {
                    Log.e(TAG, "배터리 최적화 예외 요청 실패: ${e.message}")
                }
            } else {
                Log.d(TAG, "이미 배터리 최적화 예외 설정됨")
            }
        } else {
            Log.d(TAG, "Android M 미만 버전, 배터리 최적화 예외 요청 불필요")
        }
    }

}

// --- WorkManager Callback ---
// Using object structure as provided by user
object WorkManagerCallback {
    @JvmStatic
    fun callbackDispatcher() {
        Log.d("WorkManagerCallback", "WorkManager callback dispatcher invoked.")
        // WorkManager initialization is best handled in the Application class.
    }
}