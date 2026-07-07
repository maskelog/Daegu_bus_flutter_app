package com.devground.daegubus.channels

import android.content.Intent
import android.util.Log
import com.devground.daegubus.MainActivity
import com.devground.daegubus.services.StationTrackingService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject

/**
 * com.devground.daegubus/station_tracking 채널 핸들러.
 * 정류장 단위 버스 도착 정보 조회(getBusInfo)와 StationTrackingService 중지를 담당한다.
 */
class StationTrackingChannelHandler(private val activity: MainActivity) : MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "StationTrackingChannel"
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        Log.d(TAG, "STATION_TRACKING_CHANNEL: method=${call.method}, args=${call.arguments}")
        when (call.method) {
            "getBusInfo" -> getBusInfo(call, result)
            "stopStationTracking" -> stopStationTracking(result)
            else -> result.notImplemented()
        }
    }

    private fun getBusInfo(call: MethodCall, result: MethodChannel.Result) {
        val routeId = call.argument<String>("routeId") ?: ""
        var stationId = call.argument<String>("stationId") ?: ""
        // stationId가 10자리 숫자가 아니면 변환 시도 (wincId -> stationId)
        if (stationId.length < 10 || !stationId.startsWith("7")) {
            // BusApiService의 getStationIdFromBsId를 동기로 호출
            try {
                val convertedId = runBlocking { activity.busApiService.getStationIdFromBsId(stationId) }
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
            val jsonString = runBlocking { activity.busApiService.getStationInfo(stationId) }
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
    }

    private fun stopStationTracking(result: MethodChannel.Result) {
        try {
            Log.i(TAG, "Flutter에서 StationTrackingService 중지 요청 받음")
            val intent = Intent(activity, StationTrackingService::class.java).apply {
                action = StationTrackingService.ACTION_STOP_TRACKING
            }
            activity.startService(intent)
            Log.i(TAG, "StationTrackingService 중지 명령 전송 완료")
            result.success(true)
        } catch (e: Exception) {
            Log.e(TAG, "StationTrackingService 중지 오류: ${e.message}", e)
            result.error("SERVICE_ERROR", "StationTrackingService 중지 중 오류 발생: ${e.message}", null)
        }
    }
}
