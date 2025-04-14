package com.example.daegu_bus_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject
import java.util.Timer
import java.util.TimerTask
import kotlin.math.min
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * 특정 정류장에 도착하는 모든 버스의 실시간 도착 정보를 추적하고 알림으로 표시하는 서비스입니다.
 */
class StationTrackingService : Service() {

    companion object {
        private const val TAG = "StationTrackingService"
        private const val CHANNEL_STATION_TRACKING = "station_tracking" // 새로운 알림 채널 ID
        private const val STATION_TRACKING_NOTIFICATION_ID = 10001 // 다른 서비스의 알림 ID와 충돌하지 않도록 함
        const val ACTION_START_TRACKING = "com.example.daegu_bus_app.action.START_STATION_TRACKING"
        const val ACTION_STOP_TRACKING = "com.example.daegu_bus_app.action.STOP_STATION_TRACKING"
        const val EXTRA_STATION_ID = "com.example.daegu_bus_app.extra.STATION_ID"
        const val EXTRA_STATION_NAME = "com.example.daegu_bus_app.extra.STATION_NAME"
    }

    // 서비스의 작업을 위한 코루틴 스코프 (메인 스레드 + SupervisorJob)
    private val serviceScope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var trackingTimer: Timer? = null // 주기적인 업데이트를 위한 타이머
    private lateinit var busApiService: BusApiService // 버스 API 호출을 위한 서비스
    private var currentStationId: String? = null // 현재 추적 중인 정류장 ID
    private var currentStationName: String? = null // 현재 추적 중인 정류장 이름

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "서비스 생성됨")
        busApiService = BusApiService(this) // BusApiService 초기화
        createNotificationChannel() // 알림 채널 생성
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand 호출됨, Action: ${intent?.action}")
        when (intent?.action) {
            ACTION_START_TRACKING -> { // 추적 시작 액션 처리
                val stationId = intent.getStringExtra(EXTRA_STATION_ID)
                val stationName = intent.getStringExtra(EXTRA_STATION_NAME)
                if (!stationId.isNullOrEmpty() && !stationName.isNullOrEmpty()) {
                    // 이미 다른 정류장을 추적 중이었다면, 이전 추적을 중지
                    if (currentStationId != null && currentStationId != stationId) {
                        stopTrackingInternal()
                    }
                    // 새로운 정류장 추적 시작
                    startTrackingInternal(stationId, stationName)
                } else {
                    Log.e(TAG, "Station ID 또는 Name이 없습니다. 추적 시작 불가.")
                    stopSelf() // 필수 정보가 없으면 서비스 스스로 종료
                }
            }
            ACTION_STOP_TRACKING -> { // 추적 중지 액션 처리
                stopTrackingInternal()
                stopSelf() // 서비스 종료 요청
            }
        }
        // START_NOT_STICKY: 시스템에 의해 서비스가 강제 종료될 경우, 자동으로 재시작하지 않음
        return START_NOT_STICKY
    }

    // 내부적으로 추적을 시작하는 로직
    private fun startTrackingInternal(stationId: String, stationName: String) {
        // 이미 타이머가 실행 중이면 취소하고 새로 시작
        if (trackingTimer != null) {
            Log.w(TAG, "이미 타이머가 실행 중입니다. 기존 타이머를 취소하고 새로 시작합니다.")
            trackingTimer?.cancel()
        }
        Log.i(TAG, "정류장 추적 시작: ID=$stationId, 이름=$stationName")
        currentStationId = stationId
        currentStationName = stationName

        // 추적 시작 즉시 첫 번째 데이터 업데이트 및 알림 표시 실행
        fetchAndNotify()

        // 타이머 설정 (예: 15초마다 도착 정보 업데이트)
        trackingTimer = Timer()
        trackingTimer?.scheduleAtFixedRate(object : TimerTask() {
            override fun run() {
                fetchAndNotify() // 주기적으로 fetchAndNotify 호출
            }
        }, 15000, 15000) // 15초 후에 첫 실행, 이후 15초 간격으로 반복
    }

    // 내부적으로 추적을 중지하는 로직
    private fun stopTrackingInternal() {
        Log.i(TAG, "정류장 추적 중지: ID=$currentStationId")
        trackingTimer?.cancel() // 타이머 취소
        trackingTimer = null
        currentStationId = null // 추적 정보 초기화
        currentStationName = null
        // 진행 중이던 알림 취소
        NotificationManagerCompat.from(this).cancel(STATION_TRACKING_NOTIFICATION_ID)
    }

    // 서버에서 도착 정보를 가져와서 알림을 업데이트하는 함수
    private fun fetchAndNotify() {
        val stationId = currentStationId
        val stationName = currentStationName
        // 추적 중인 정류장 정보가 없으면 중단
        if (stationId == null || stationName == null) {
            Log.w(TAG, "추적 중인 정류장 정보가 없어 fetchAndNotify 중단")
            return
        }

        // 코루틴을 사용하여 백그라운드에서 API 호출
        serviceScope.launch {
            try {
                Log.d(TAG, "[$stationId] 도착 정보 업데이트 시작...")
                // API 서비스를 통해 해당 정류장의 도착 정보(JSON 문자열)를 가져옴
                val arrivalJsonString = busApiService.getStationInfo(stationId)
                // 가져온 JSON 문자열을 파싱하여 도착 정보 리스트로 변환
                val arrivals = parseStationArrivals(arrivalJsonString)
                Log.d(TAG, "[$stationId] 파싱된 도착 정보: ${arrivals.size}개 버스")
                // 파싱된 도착 정보를 사용하여 알림을 표시하거나 업데이트
                showStationTrackingNotification(stationName, arrivals)
            } catch (e: Exception) {
                Log.e(TAG, "[$stationId] 도착 정보 업데이트 중 오류: ${e.message}", e)
                // 오류 발생 시, 알림에 오류 상태를 표시 (선택적)
                 showStationTrackingNotification(stationName, emptyList(), isError = true)
            }
        }
    }

    // 파싱된 도착 정보를 담는 데이터 클래스
    private data class ParsedArrivalInfo(
        val routeNo: String,        // 버스 번호
        val estimatedMinutes: Int?, // 예상 도착 시간(분), null 가능
        val remainingStops: Int?,   // 남은 정류장 수, null 가능
        val isLowFloor: Boolean,    // 저상 버스 여부
        val moveDir: String?        // 버스 진행 방향 (ex: "종점")
    )

    // JSON 문자열을 파싱하여 ParsedArrivalInfo 리스트로 변환하는 함수
    private fun parseStationArrivals(jsonString: String): List<ParsedArrivalInfo> {
        val results = mutableListOf<ParsedArrivalInfo>()
        // 입력된 JSON 문자열이 비어있거나 유효한 JSON 배열 형식이 아니면 빈 리스트 반환
        if (jsonString.isBlank() || !jsonString.startsWith("[")) {
             Log.w(TAG, "파싱할 유효한 JSON 데이터가 아님: ${jsonString.take(50)}")
             return results
        }
        try {
            val jsonArray = JSONArray(jsonString) // JSON 문자열을 JSONArray로 변환
            // 배열의 각 노선 정보(JSONObject)를 순회
            for (i in 0 until jsonArray.length()) {
                val routeObj = jsonArray.getJSONObject(i)
                // 해당 노선의 도착 버스 목록(arrList)을 가져옴
                val arrList = routeObj.optJSONArray("arrList") ?: continue // arrList가 없으면 다음 노선으로
                // 도착 버스 목록의 각 버스 정보(JSONObject)를 순회
                for (j in 0 until arrList.length()) {
                    val busObj = arrList.getJSONObject(j)
                    val arrState = busObj.optString("arrState", "") // 도착 상태 문자열 ("곧 도착", "5분", "운행종료" 등)
                    // 도착 상태 문자열에서 숫자만 추출하여 분으로 변환, "곧 도착"은 0분으로 처리
                    val minutes = if (arrState == "곧 도착") 0 else arrState.filter { it.isDigit() }.toIntOrNull()
                    // 남은 정류장 수 추출
                    val stops = busObj.optString("bsGap", "").filter { it.isDigit() }.toIntOrNull()
                    // 저상 버스 여부 확인 ("1": 저상, "N": 일반)
                    val isLow = busObj.optString("busTCd2", "") == "1"
                    // 버스 진행 방향 추출
                    val direction = busObj.optString("moveDir", null)

                    // "운행종료" 상태가 아닌 버스만 결과 리스트에 추가
                    if (arrState != "운행종료") {
                        results.add(
                            ParsedArrivalInfo(
                                routeNo = busObj.optString("routeNo", routeObj.optString("routeNo")), // routeNo 추출
                                estimatedMinutes = minutes,
                                remainingStops = stops,
                                isLowFloor = isLow,
                                moveDir = direction
                            )
                        )
                    }
                }
            }
             // 파싱된 결과를 예상 도착 시간 순서로 정렬 (null 값은 가장 뒤로)
             results.sortBy { it.estimatedMinutes ?: Int.MAX_VALUE }
             Log.d(TAG, "정류장 도착 정보 파싱 완료: ${results.size}개 항목")
        } catch (e: Exception) {
            Log.e(TAG, "정류장 도착 정보 JSON 파싱 오류: ${e.message}")
        }
        return results // 파싱된 도착 정보 리스트 반환
    }


    // 진행 중인 정류장 추적 알림을 표시하거나 업데이트하는 함수
    private fun showStationTrackingNotification(stationName: String, arrivals: List<ParsedArrivalInfo>, isError: Boolean = false) {
        try {
            val currentTime = SimpleDateFormat("HH:mm", Locale.getDefault()).format(Date())
            val title = "$stationName 도착 정보 ($currentTime)"
            val bodyText: String
            val inboxStyle = NotificationCompat.InboxStyle().setBigContentTitle(title)

            if (isError) {
                bodyText = "정보 불러오기 실패"
                inboxStyle.addLine("도착 정보를 가져오는 중 오류가 발생했습니다.")
            } else if (arrivals.isEmpty()) {
                bodyText = "도착 예정 버스 없음"
                inboxStyle.addLine("현재 도착 예정인 버스가 없습니다.")
            } else {
                bodyText = arrivals.take(1).joinToString("") { formatArrival(it, compact = true).toString() }
                arrivals.take(5).forEach { inboxStyle.addLine(formatArrival(it, compact = false)) }
            }

            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
            }
            val pendingIntent = PendingIntent.getActivity(
                this,
                STATION_TRACKING_NOTIFICATION_ID,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val stopTrackingIntent = Intent(this, StationTrackingService::class.java).apply {
                action = ACTION_STOP_TRACKING
            }
            val stopTrackingPendingIntent = PendingIntent.getService(
                this,
                STATION_TRACKING_NOTIFICATION_ID + 1,
                stopTrackingIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val builder = NotificationCompat.Builder(this, CHANNEL_STATION_TRACKING)
                .setSmallIcon(R.drawable.ic_bus_notification)
                .setContentTitle(title)
                .setContentText(bodyText)
                .setStyle(inboxStyle)
                .setPriority(NotificationCompat.PRIORITY_HIGH) // 우선순위를 HIGH로 설정하여 더 높은 가시성 제공
                .setCategory(NotificationCompat.CATEGORY_SERVICE)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
                .setColor(ContextCompat.getColor(this, R.color.tracking_color))
                .setColorized(true)
                .setOngoing(true)
                .setAutoCancel(false)
                .setOnlyAlertOnce(false)
                .setContentIntent(pendingIntent)
                .addAction(R.drawable.ic_stop_tracking, "추적 중지", stopTrackingPendingIntent)
                .setWhen(System.currentTimeMillis())
                .setShowWhen(true)

            startForeground(STATION_TRACKING_NOTIFICATION_ID, builder.build())
            Log.d(TAG, "정류장 추적 알림 표시/업데이트 완료 (Foreground): $stationName")
        } catch (e: Exception) {
            Log.e(TAG, "정류장 추적 알림 표시 중 오류: ${e.message}", e)
        }
    }

    // 도착 정보를 포맷팅하여 문자열로 반환하는 함수
    private fun formatArrival(arrival: ParsedArrivalInfo, compact: Boolean): String {
         // 예상 도착 시간을 문자열로 변환 ("정보없음", "곧 도착", "5분" 등)
         val timeStr = when (arrival.estimatedMinutes) {
            null -> "정보없음"
            0 -> "곧 도착"
            else -> "${arrival.estimatedMinutes}분"
        }
         // 저상 버스인 경우 표시 추가
         val lowFloorStr = if (arrival.isLowFloor) "(저)" else ""
         // 남은 정류장 수 표시 (선택 사항, 현재 주석 처리)
         // val stopsStr = arrival.remainingStops?.let { "($it 정류장)" } ?: ""
         val routeNoStr = arrival.routeNo // 버스 번호
         
         // moveDir 값은 표시하지 않음 (인덱스 숫자 제거)
         // val directionStr = arrival.moveDir?.let { " [$it]" } ?: ""

         // compact 플래그에 따라 다른 포맷으로 반환
         return if (compact) { // 축소 상태 포맷
             "$routeNoStr$lowFloorStr: $timeStr"
         } else { // 확장 상태 포맷
             "$routeNoStr$lowFloorStr - $timeStr" // + stopsStr
         }
    }


    // 알림 채널 생성 (API 레벨 26 이상에서 필요)
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            // 채널 설정 (높은 중요도: 소리/진동 있음, 상단 고정됨)
            val channel = NotificationChannel(
                CHANNEL_STATION_TRACKING, // 채널 ID
                "Station Tracking", // 사용자에게 보여질 채널 이름
                NotificationManager.IMPORTANCE_HIGH // 높은 중요도로 변경
            ).apply {
                description = "특정 정류장의 모든 버스 도착 정보 실시간 추적" // 채널 설명
                // 소리 및 진동 활성화 (중요도가 높은 채널에 맞게 설정)
                enableVibration(true) // 진동 활성화
                vibrationPattern = longArrayOf(0, 250, 250, 250) // 짧은 진동 패턴
                enableLights(true) // 불빛 활성화
                lightColor = ContextCompat.getColor(this@StationTrackingService, R.color.tracking_color) // 알림 LED 색상
            }
            // 시스템 서비스인 NotificationManager 가져오기
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            // NotificationManager에 채널 등록
            manager.createNotificationChannel(channel)
            Log.d(TAG, "알림 채널 생성됨: $CHANNEL_STATION_TRACKING (높은 우선순위)")
        }
    }

    override fun onBind(intent: Intent?): IBinder? {
        // 이 서비스는 외부 앱/컴포넌트와 바인딩되지 않으므로 null 반환
        return null
    }

    override fun onDestroy() {
        Log.i(TAG, "서비스 소멸됨")
        stopTrackingInternal() // 서비스 종료 시 추적 중지 및 리소스 정리
        serviceScope.cancel() // 코루틴 스코프 취소 (진행 중이던 작업 중단)
        super.onDestroy()
    }
}
