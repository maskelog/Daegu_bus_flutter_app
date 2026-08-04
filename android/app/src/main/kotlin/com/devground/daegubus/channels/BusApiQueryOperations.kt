package com.devground.daegubus.channels

import android.database.sqlite.SQLiteException
import android.util.Log
import com.devground.daegubus.MainActivity
import com.devground.daegubus.utils.DatabaseHelper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject

/** bus_api 채널의 정류장·노선 DB 및 웹 API 조회 작업. */
internal class BusApiQueryOperations(private val activity: MainActivity) {

    companion object {
        private const val TAG = "BusApiChannel"
    }

    fun searchStations(call: MethodCall, result: MethodChannel.Result) {
        val searchText = call.argument<String>("searchText") ?: ""
        if (searchText.isEmpty()) {
            result.error("INVALID_ARGUMENT", "검색어가 비어있습니다", null)
            return
        }
        val searchType = call.argument<String>("searchType") ?: "web"
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val databaseHelper = DatabaseHelper.getInstance(activity)
                if (searchType == "local") {
                    val stations = databaseHelper.searchStations(searchText)
                    Log.d(TAG, "로컬 정류장 검색 결과: ${stations.size}개")
                    val jsonArray = JSONArray()
                    stations.forEach { station ->
                        val wincId = station.stationId?.takeIf { it.isNotBlank() } ?: station.bsId
                        val jsonObj = JSONObject().apply {
                            put("id", station.bsId)
                            put("name", station.bsNm)
                            put("isFavorite", false)
                            put("wincId", wincId)
                            put("stationId", wincId)
                            put("ngisXPos", station.longitude)
                            put("ngisYPos", station.latitude)
                            put("routeList", JSONArray())
                        }
                        jsonArray.put(jsonObj)
                    }
                    result.success(jsonArray.toString())
                } else {
                    val stations = activity.busApiService.searchStations(searchText)
                    Log.d(TAG, "웹 정류장 검색 결과: ${stations.size}개")
                    val jsonArray = JSONArray()
                    stations.forEach { station ->
                        Log.d(TAG, "Station - ID: ${station.bsId}, Name: ${station.bsNm}")
                        val wincId = databaseHelper.getStationIdByBsId(station.bsId) ?: station.bsId
                        val jsonObj = JSONObject().apply {
                            put("id", station.bsId)
                            put("name", station.bsNm)
                            put("isFavorite", false)
                            put("wincId", wincId)
                            put("stationId", wincId)
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

    fun findNearbyStations(call: MethodCall, result: MethodChannel.Result) {
        val requestTraceId = call.argument<String>("traceId")?.let { input ->
            val trimmed = input.trim()
            if (trimmed.isNotEmpty()) trimmed else null
        } ?: "findNearby_${System.currentTimeMillis()}"

        fun readCoordinate(argumentKey: String): Double? {
            val arg = call.argument<Any>(argumentKey)
            val normalizedString = if (arg is String) arg.trim().replace(",", ".") else null
            return when (arg) {
                is Double -> arg.takeIf { it.isFinite() }
                is Float -> arg.toDouble().takeIf { it.isFinite() }
                is Long -> arg.toDouble()
                is Int -> arg.toDouble()
                is String -> normalizedString?.toDoubleOrNull()?.takeIf { it.isFinite() }
                else -> {
                    Log.w(
                        TAG,
                        "[$requestTraceId] findNearbyStations coord parse failed key=$argumentKey value=$arg type=${arg?.javaClass?.name}",
                    )
                    null
                }
            }
        }

        val traceId = requestTraceId
        val latitude = readCoordinate("latitude")
        val longitude = readCoordinate("longitude")
        val radiusMeters = readCoordinate("radiusMeters")?.takeIf { it > 0 } ?: 500.0

        if (latitude == null || longitude == null) {
            Log.w(TAG, "[$traceId] findNearbyStations invalid coordinates: lat=$latitude, lon=$longitude")
            result.error("INVALID_ARGUMENT", "위도 또는 경도가 유효하지 않습니다", null)
            return
        }

        CoroutineScope(Dispatchers.Main).launch {
            try {
                Log.d(TAG, "[$traceId] 주변 정류장 검색 요청: lat=$latitude, lon=$longitude, radius=${radiusMeters}m")

                val databaseHelper = DatabaseHelper.getInstance(activity)

                fun buildStationJsonArray(stations: List<com.devground.daegubus.models.LocalStationSearchResult>): JSONArray {
                    val jsonArray = JSONArray()
                    stations.forEach { station ->
                        val jsonObj = JSONObject().apply {
                            val wincId = station.stationId ?: station.bsId
                            put("id", wincId)
                            put("name", station.bsNm)
                            put("isFavorite", false)
                            put("wincId", wincId)
                            put("stationId", wincId)
                            put("distance", station.distance)
                            put("ngisXPos", station.longitude)
                            put("ngisYPos", station.latitude)
                            put("routeList", JSONArray())
                        }
                        jsonArray.put(jsonObj)
                    }
                    return jsonArray
                }

                try {
                    val nearbyStations = databaseHelper.searchStations(
                        searchText = "",
                        latitude = latitude,
                        longitude = longitude,
                        radiusInMeters = radiusMeters
                    )

                    Log.d(TAG, "[$traceId] 주변 정류장 검색 완료: ${nearbyStations.size}개 발견 (반경: ${radiusMeters}m)")

                    val jsonArray = buildStationJsonArray(nearbyStations)
                    result.success(jsonArray.toString())
                } catch (e: SQLiteException) {
                    Log.e(TAG, "[$traceId] SQLite 오류 발생, DB 재설치 시도", e)
                    databaseHelper.forceReinstallDatabase()

                    val nearbyStations = databaseHelper.searchStations(
                        searchText = "",
                        latitude = latitude,
                        longitude = longitude,
                        radiusInMeters = radiusMeters
                    )
                    result.success(buildStationJsonArray(nearbyStations).toString())
                }
            } catch (e: Exception) {
                Log.e(TAG, "[$traceId] 주변 정류장 검색 오류: ${e.message}", e)
                result.error("DB_ERROR", "주변 정류장 검색 중 오류 발생: ${e.message}", null)
            }
        }
    }

    fun getBusRouteDetails(call: MethodCall, result: MethodChannel.Result) {
        val routeId = call.argument<String>("routeId") ?: ""
        if (routeId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "노선 ID가 비어있습니다", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val searchRoutes = activity.busApiService.searchBusRoutes(routeId)
                val routeInfo = activity.busApiService.getBusRouteInfo(routeId)
                val mergedRoute = routeInfo ?: searchRoutes.firstOrNull()
                result.success(activity.busApiService.convertToJson(mergedRoute ?: "{}"))
            } catch (e: Exception) {
                Log.e(TAG, "버스 노선 상세 정보 조회 오류: ${e.message}", e)
                result.error("API_ERROR", "버스 노선 상세 정보 조회 중 오류 발생: ${e.message}", null)
            }
        }
    }

    fun searchBusRoutes(call: MethodCall, result: MethodChannel.Result) {
        val searchText = call.argument<String>("searchText") ?: ""
        if (searchText.isEmpty()) {
            result.error("INVALID_ARGUMENT", "검색어가 비어있습니다", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val routes = activity.busApiService.searchBusRoutes(searchText)
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

    fun getStationIdFromBsId(call: MethodCall, result: MethodChannel.Result) {
        val bsId = call.argument<String>("bsId") ?: ""
        if (bsId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "bsId가 비어있습니다", null)
            return
        }
        if (bsId.startsWith("7") && bsId.length == 10) {
            Log.d(TAG, "bsId '$bsId'는 이미 stationId 형식입니다")
            result.success(bsId)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val stationId = activity.busApiService.getStationIdFromBsId(bsId)
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

    fun getStationInfo(call: MethodCall, result: MethodChannel.Result) {
        val stationId = call.argument<String>("stationId") ?: ""
        if (stationId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "정류장 ID가 비어있습니다", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val jsonString = runBlocking { activity.busApiService.getStationInfo(stationId) }
                Log.d(TAG, "정류장 정보 조회 완료: $stationId")
                result.success(jsonString)
            } catch (e: Exception) {
                Log.e(TAG, "정류장 정보 조회 오류: ${e.message}", e)
                result.error("API_ERROR", "정류장 정보 조회 중 오류 발생: ${e.message}", null)
            }
        }
    }

    fun getBusArrivalByRouteId(call: MethodCall, result: MethodChannel.Result) {
        val stationId = call.argument<String>("stationId") ?: ""
        val routeId = call.argument<String>("routeId") ?: ""
        if (stationId.isEmpty() || routeId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "정류장 ID 또는 노선 ID가 비어있습니다", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val arrivalInfo = activity.busApiService.getBusArrivalInfoByRouteId(stationId, routeId)
                result.success(activity.busApiService.convertToJson(arrivalInfo ?: "{}"))
            } catch (e: Exception) {
                Log.e(TAG, "노선별 버스 도착 정보 조회 오류: ${e.message}", e)
                result.error("API_ERROR", "노선별 버스 도착 정보 조회 중 오류 발생: ${e.message}", null)
            }
        }
    }

    fun getBusRouteInfo(call: MethodCall, result: MethodChannel.Result) {
        val routeId = call.argument<String>("routeId") ?: ""
        if (routeId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "노선 ID가 비어있습니다", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val routeInfo = activity.busApiService.getBusRouteInfo(routeId)
                result.success(activity.busApiService.convertToJson(routeInfo ?: "{}"))
            } catch (e: Exception) {
                Log.e(TAG, "버스 노선 정보 조회 오류: ${e.message}", e)
                result.error("API_ERROR", "버스 노선 정보 조회 중 오류 발생: ${e.message}", null)
            }
        }
    }

    fun getBusPositionInfo(call: MethodCall, result: MethodChannel.Result) {
        val routeId = call.argument<String>("routeId") ?: ""
        if (routeId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "노선 ID가 비어있습니다", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val positionInfo = activity.busApiService.getBusPositionInfo(routeId)
                result.success(positionInfo)
            } catch (e: Exception) {
                Log.e(TAG, "실시간 버스 위치 정보 조회 오류: ${e.message}", e)
                result.error("API_ERROR", "실시간 버스 위치 정보 조회 중 오류 발생: ${e.message}", null)
            }
        }
    }

    fun getRouteStations(call: MethodCall, result: MethodChannel.Result) {
        val routeId = call.argument<String>("routeId") ?: ""
        if (routeId.isEmpty()) {
            result.error("INVALID_ARGUMENT", "routeId가 비어있습니다", null)
            return
        }
        CoroutineScope(Dispatchers.Main).launch {
            try {
                val stations = activity.busApiService.getBusRouteMap(routeId)
                Log.d(TAG, "노선도 조회 결과: ${stations.size}개 정류장")
                result.success(activity.busApiService.convertRouteStationsToJson(stations))
            } catch (e: Exception) {
                Log.e(TAG, "노선도 조회 오류: ${e.message}", e)
                result.error("API_ERROR", "노선도 조회 중 오류 발생: ${e.message}", null)
            }
        }
    }
}
