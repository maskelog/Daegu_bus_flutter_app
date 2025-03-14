package com.example.daegu_bus_app

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.ResponseBody
import org.json.JSONArray
import org.json.JSONObject
import org.jsoup.Jsoup
import org.jsoup.parser.Parser
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.Url
import java.net.URLEncoder
import java.nio.charset.Charset
import java.util.concurrent.TimeUnit

// Retrofit API 인터페이스
interface BusInfoApi {
    @GET
    suspend fun getStationSearchResult(@Url url: String): ResponseBody

    @GET("realtime/arr2/{stationId}")
    suspend fun getBusArrivalInfo(@Path("stationId") stationId: String): BusArrivalResponse

    @GET("route/search")
    suspend fun searchBusRoutes(@Query("searchText") searchText: String): ResponseBody

    @GET("route/info")
    suspend fun getBusRouteInfo(@Query("routeId") routeId: String): ResponseBody

    @GET("bs/route")
    suspend fun getBusRouteMap(@Query("routeId") routeId: String): ResponseBody

    @GET("realtime/pos/{routeId}")
    suspend fun getBusPositionInfo(@Path("routeId") routeId: String): ResponseBody
}

// 모델: 정류장 검색 결과
data class StationSearchResult(
    val bsId: String,
    val bsNm: String
)

// 모델: 버스 도착 정보 응답
data class BusArrivalResponse(
    val header: Header,
    val body: Body
) {
    data class Header(
        val success: Boolean,      // JSON의 true/false 값에 맞게 수정
        val resultCode: String,
        val resultMsg: String
    )
    data class Body(
        val block: Boolean,
        val list: List<RouteInfo>?
    ) {
        data class RouteInfo(
            val routeNo: String,
            val arrList: List<ArrivalInfo>?
        ) {
            data class ArrivalInfo(
                val routeId: String,
                val routeNo: String,
                val moveDir: String?,
                val bsGap: Int,
                val bsNm: String?,
                val vhcNo2: String,
                val busTCd2: String,
                val busTCd3: String,
                val busAreaCd: String,
                val arrState: String?,
                val prevBsGap: Int
            )
        }
    }
}

// 모델: 클라이언트 응답용 도착 정보
data class StationArrivalOutput(
    val name: String,
    val sub: String,
    val id: String,
    val forward: String?,
    val bus: List<BusInfo>
) {
    data class BusInfo(
        val busNumber: String,
        val currentStation: String,
        val remainingStations: String,
        val estimatedTime: String
    )
}

// 모델: 노선 정보 – Flutter 모델과 일치
data class BusRoute(
    val id: String,
    val routeNo: String,
    val startPoint: String,
    val endPoint: String,
    val routeDescription: String
)

// 모델: 노선의 정류장 – Flutter 모델과 일치
data class RouteStation(
    val stationId: String,
    val stationName: String,
    val sequenceNo: Int,
    val direction: String
)

// 모델: BusInfo - Flutter 컨버팅을 위한 확장
data class BusInfo(
    val busNumber: String,
    val currentStation: String,
    val remainingStops: String,
    val estimatedTime: String,
    val isLowFloor: Boolean = false,
    val isOutOfService: Boolean = false
)

// 모델: BusArrivalInfo - Flutter 컨버팅을 위한 확장
data class BusArrivalInfo(
    val routeId: String,
    val routeNo: String,
    val destination: String,
    val buses: List<BusInfo>
)

// 최종 BusArrival 모델 (Flutter와 연동)
data class BusArrival(
    val routeNo: String,
    val routeId: String,
    val buses: List<BusInfo>
)

class BusApiService(private val context: Context) {
    companion object {
        private const val TAG = "BusApiService"
        private const val BASE_URL = "https://businfo.daegu.go.kr:8095/dbms_web_api/"
        private const val SEARCH_URL = "https://businfo.daegu.go.kr/ba/route/rtbsarr.do"
    }
    
    private val gson: Gson = GsonBuilder().setLenient().create()
    
    private val okHttpClient = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()
    
    private val retrofit = Retrofit.Builder()
        .baseUrl(BASE_URL)
        .client(okHttpClient)
        .addConverterFactory(GsonConverterFactory.create(gson))
        .build()
    
    private val busInfoApi = retrofit.create(BusInfoApi::class.java)
    
    // 정류장 검색 함수
    suspend fun searchStations(searchText: String): List<StationSearchResult> = withContext(Dispatchers.IO) {
        try {
            val encodedText = URLEncoder.encode(searchText, "EUC-KR")
            val url = "$SEARCH_URL?act=findByBS2&bsNm=$encodedText"
            val response = busInfoApi.getStationSearchResult(url)
            val html = String(response.bytes(), Charset.forName("EUC-KR"))
            val document = Jsoup.parse(html)
            val results = mutableListOf<StationSearchResult>()
            document.select("#arrResultBsPanel td.body_col1").forEach { element ->
                val onclick = element.attr("onclick") ?: ""
                val firstcom = onclick.indexOf("'")
                val lastcom = onclick.indexOf("'", firstcom + 1)
                if (firstcom >= 0 && lastcom > firstcom) {
                    val bsId = onclick.substring(firstcom + 1, lastcom)
                    var bsNm = element.text().trim()
                    if (bsNm.length > 7) {
                        bsNm = bsNm.substring(0, bsNm.length - 7).trim()
                    }
                    results.add(StationSearchResult(bsId = bsId, bsNm = bsNm))
                }
            }
            results
        } catch (e: Exception) {
            Log.e(TAG, "정류장 검색 오류: ${e.message}", e)
            emptyList()
        }
    }
    
    // 노선 검색 함수
    suspend fun searchBusRoutes(query: String): List<BusRoute> = withContext(Dispatchers.IO) {
        try {
            val encodedQuery = URLEncoder.encode(query, "EUC-KR")
            val response = busInfoApi.searchBusRoutes(encodedQuery)
            val responseStr = String(response.bytes(), Charset.forName("EUC-KR"))
            Log.d(TAG, "노선 검색 응답: $responseStr")
            if (responseStr.trim().startsWith("{")) {
                parseJsonBusRoutes(responseStr)
            } else if (responseStr.trim().startsWith("<")) {
                parseXmlBusRoutes(responseStr)
            } else {
                Log.e(TAG, "알 수 없는 응답 형식: ${responseStr.substring(0, minOf(responseStr.length, 50))}")
                emptyList()
            }
        } catch (e: Exception) {
            Log.e(TAG, "노선 검색 오류: ${e.message}", e)
            emptyList()
        }
    }
    
    private fun parseJsonBusRoutes(jsonStr: String): List<BusRoute> {
        // JSON 파싱 로직 구현 (예시)
        val routes = mutableListOf<BusRoute>()
        try {
            val jsonObj = JSONObject(jsonStr)
            val header = jsonObj.getJSONObject("header")
            val success = header.optBoolean("success", false)
            if (!success) {
                Log.e(TAG, "노선 검색 실패: ${header.optString("resultMsg")}")
                return emptyList()
            }
            val body = jsonObj.opt("body")
            if (body is JSONArray) {
                for (i in 0 until body.length()) {
                    val routeObj = body.getJSONObject(i)
                    routes.add(
                        BusRoute(
                            id = routeObj.optString("routeId", ""),
                            routeNo = routeObj.optString("routeNo", ""),
                            startPoint = "",
                            endPoint = "",
                            routeDescription = routeObj.optString("routeNm", "")
                        )
                    )
                }
            } else if (body is JSONObject) {
                routes.add(
                    BusRoute(
                        id = body.optString("routeId", ""),
                        routeNo = body.optString("routeNo", ""),
                        startPoint = "",
                        endPoint = "",
                        routeDescription = body.optString("routeNm", "")
                    )
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "JSON 노선 검색 파싱 오류: ${e.message}", e)
        }
        return routes
    }
    
    private fun parseXmlBusRoutes(xmlStr: String): List<BusRoute> {
        // XML 파싱 로직 구현 (예시)
        val routes = mutableListOf<BusRoute>()
        try {
            val document = Jsoup.parse(xmlStr, "", Parser.xmlParser())
            val headerElement = document.select("header").first()
            val success = headerElement?.select("success")?.text() == "true"
            if (!success) {
                val resultMsg = headerElement?.select("resultMsg")?.text() ?: "Unknown error"
                Log.e(TAG, "노선 검색 실패: $resultMsg")
                return emptyList()
            }
            val bodyElements = document.select("body")
            bodyElements.forEach { element ->
                val routeId = element.select("routeId").text()
                val routeNo = element.select("routeNo").text()
                val routeNm = element.select("routeNm").text()
                if (routeId.isNotEmpty() && routeNo.isNotEmpty()) {
                    routes.add(
                        BusRoute(
                            id = routeId,
                            routeNo = routeNo,
                            startPoint = "",
                            endPoint = "",
                            routeDescription = if (routeNm.isEmpty()) routeNo else routeNm
                        )
                    )
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "XML 노선 검색 파싱 오류: ${e.message}", e)
        }
        return routes
    }
    
    // 버스 도착 정보 조회 함수
    suspend fun getBusArrivalInfo(stationId: String): List<StationArrivalOutput> = withContext(Dispatchers.IO) {
        try {
            val response = busInfoApi.getBusArrivalInfo(stationId)
            if (!response.header.success) {
                Log.e(TAG, "API 응답 오류: ${response.header.resultMsg}")
                return@withContext emptyList()
            }
            val groups = mutableMapOf<String, StationArrivalOutput>()
            response.body.list?.forEach { route ->
                val routeNo = route.routeNo
                route.arrList?.forEach { arrival ->
                    val moveDir = arrival.moveDir ?: "알 수 없음"
                    val key = "${routeNo}_$moveDir"
                    if (!groups.containsKey(key)) {
                        groups[key] = StationArrivalOutput(
                            name = routeNo,
                            sub = "default",
                            id = arrival.routeId,
                            forward = moveDir,
                            bus = mutableListOf()
                        )
                    }
                    val busType = if (arrival.busTCd2 == "N") "저상" else "일반"
                    val arrivalTime = when {
                        arrival.arrState == null -> "-"
                        arrival.arrState == "운행종료" -> "운행종료"
                        else -> arrival.arrState
                    }
                    (groups[key]!!.bus as MutableList).add(
                        StationArrivalOutput.BusInfo(
                            busNumber = "${arrival.vhcNo2}($busType)",
                            currentStation = arrival.bsNm ?: "정보 없음",
                            remainingStations = "${arrival.bsGap} 개소",
                            estimatedTime = arrivalTime
                        )
                    )
                }
            }
            groups.values.toList()
        } catch (e: Exception) {
            Log.e(TAG, "버스 도착 정보 조회 오류: ${e.message}", e)
            emptyList()
        }
    }
    
    // 노선별 버스 도착 정보 조회
    suspend fun getBusArrivalInfoByRouteId(stationId: String, routeId: String): StationArrivalOutput? = withContext(Dispatchers.IO) {
        try {
            val allArrivals = getBusArrivalInfo(stationId)
            val result = allArrivals.find { it.id == routeId }
            if (result != null && result.forward == null) {
                return@withContext result.copy(forward = "알 수 없음")
            }
            result
        } catch (e: Exception) {
            Log.e(TAG, "노선별 버스 도착 정보 조회 오류: ${e.message}", e)
            null
        }
    }
    
    // 노선 정보 조회 함수
    suspend fun getBusRouteInfo(routeId: String): BusRoute? = withContext(Dispatchers.IO) {
        try {
            val response = busInfoApi.getBusRouteInfo(routeId)
            var responseStr = String(response.bytes(), Charset.forName("UTF-8"))
            if (containsBrokenKorean(responseStr)) {
                responseStr = String(response.bytes(), Charset.forName("EUC-KR"))
            }
            Log.d(TAG, "노선 정보 응답: $responseStr")
            if (responseStr.trim().startsWith("{")) {
                parseJsonRouteInfo(responseStr, routeId)
            } else if (responseStr.trim().startsWith("<")) {
                parseXmlRouteInfo(responseStr, routeId)
            } else {
                Log.e(TAG, "알 수 없는 응답 형식: ${responseStr.substring(0, minOf(responseStr.length, 50))}")
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "노선 정보 조회 오류: ${e.message}", e)
            null
        }
    }
    
    private fun parseJsonRouteInfo(jsonStr: String, routeId: String): BusRoute? {
        // JSON 파싱 로직 구현 (예시)
        try {
            val jsonObj = JSONObject(jsonStr)
            val resultObj = if (jsonObj.has("Result")) jsonObj.getJSONObject("Result") else jsonObj
            val header = resultObj.getJSONObject("header")
            val success = header.optString("success") == "true" || header.optBoolean("success", false)
            if (!success) {
                Log.e(TAG, "노선 정보 조회 실패: ${header.optString("resultMsg")}")
                return null
            }
            val body = resultObj.getJSONObject("body")
            return BusRoute(
                id = body.optString("routeId", routeId),
                routeNo = body.optString("routeNo", ""),
                startPoint = body.optString("stNm", "출발지 정보 없음"),
                endPoint = body.optString("edNm", "도착지 정보 없음"),
                routeDescription = "배차간격: ${body.optString("avgTm", "정보 없음")}, 업체: ${body.optString("comNm", "정보 없음")}"
            )
        } catch (e: Exception) {
            Log.e(TAG, "JSON 노선 정보 파싱 오류: ${e.message}", e)
            return null
        }
    }
    
    private fun parseXmlRouteInfo(xmlStr: String, routeId: String): BusRoute? {
        // XML 파싱 로직 구현 (예시)
        try {
            val document = Jsoup.parse(xmlStr, "", Parser.xmlParser())
            val headerElement = document.select("header").first()
            val success = headerElement?.select("success")?.text() == "true"
            if (!success) {
                val resultMsg = headerElement?.select("resultMsg")?.text() ?: "Unknown error"
                Log.e(TAG, "노선 정보 조회 실패: $resultMsg")
                return null
            }
            val bodyElement = document.select("body").first()
            return if (bodyElement != null) {
                BusRoute(
                    id = bodyElement.select("routeId").text().ifEmpty { routeId },
                    routeNo = bodyElement.select("routeNo").text(),
                    startPoint = bodyElement.select("stNm").text(),
                    endPoint = bodyElement.select("edNm").text(),
                    routeDescription = "배차간격: ${bodyElement.select("avgTm").text()}, 업체: ${bodyElement.select("comNm").text()}"
                )
            } else {
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "XML 노선 정보 파싱 오류: ${e.message}", e)
            return null
        }
    }
    
    // 실시간 버스 위치 정보 조회 함수
    suspend fun getBusPositionInfo(routeId: String): String = withContext(Dispatchers.IO) {
        try {
            val response = busInfoApi.getBusPositionInfo(routeId)
            String(response.bytes())
        } catch (e: Exception) {
            Log.e(TAG, "실시간 버스 위치 정보 조회 오류: ${e.message}", e)
            "{\"error\": \"${e.message}\"}"
        }
    }
    
    // 노선도 조회 함수
    suspend fun getBusRouteMap(routeId: String): List<RouteStation> = withContext(Dispatchers.IO) {
        try {
            if (routeId.isEmpty()) {
                Log.e(TAG, "빈 routeId, 노선도 조회 불가")
                return@withContext emptyList<RouteStation>()
            }
            val response = busInfoApi.getBusRouteMap(routeId)
            var responseStr = String(response.bytes(), Charset.forName("UTF-8"))
            if (containsBrokenKorean(responseStr)) {
                responseStr = String(response.bytes(), Charset.forName("EUC-KR"))
            }
            Log.d(TAG, "노선도 응답 길이: ${responseStr.length}")
            if (responseStr.trim().startsWith("{")) {
                parseJsonRouteStations(responseStr)
            } else if (responseStr.trim().startsWith("<")) {
                parseXmlRouteStations(responseStr)
            } else {
                Log.e(TAG, "알 수 없는 응답 형식")
                emptyList()
            }
        } catch (e: Exception) {
            Log.e(TAG, "노선도 조회 오류: ${e.message}", e)
            emptyList()
        }
    }
    
    private fun parseJsonRouteStations(jsonStr: String): List<RouteStation> {
        // JSON 파싱 로직 구현 (예시)
        return emptyList()
    }
    
    private fun parseXmlRouteStations(xmlStr: String): List<RouteStation> {
        // XML 파싱 로직 구현 (예시)
        val document = Jsoup.parse(xmlStr, "", Parser.xmlParser())
        val stationList = mutableListOf<RouteStation>()
        val elements = document.select("body")
        elements.forEach { element ->
            val bsId = element.select("bsId").text()
            val bsNm = element.select("bsNm").text()
            val seqStr = element.select("seq").text()
            val moveDir = element.select("moveDir").text()
            val seq = seqStr.toIntOrNull() ?: 0
            if (bsId.isNotEmpty() && bsNm.isNotEmpty()) {
                stationList.add(RouteStation(
                    stationId = bsId,
                    stationName = bsNm,
                    sequenceNo = seq,
                    direction = moveDir
                ))
            }
        }
        return stationList.sortedBy { it.sequenceNo }
    }
    
    // 한글 깨짐 여부 확인 함수
    private fun containsBrokenKorean(text: String): Boolean {
        val koreanPattern = Regex("[\\uAC00-\\uD7A3]+")
        val matches = koreanPattern.findAll(text)
        return matches.count() == 0 && text.contains("�")
    }
    
    // Flutter에서 사용할 수 있도록 BusArrivalInfo를 BusArrival 모델(JSON)으로 변환하는 메서드
    fun convertToBusArrival(info: BusArrivalInfo): JSONObject {
        val busesJson = JSONArray()
        info.buses.forEach { bus ->
            val busJson = JSONObject().apply {
                put("버스번호", bus.busNumber)
                put("현재정류소", bus.currentStation)
                put("남은정류소", bus.remainingStops)
                put("도착예정소요시간", bus.estimatedTime)
            }
            busesJson.put(busJson)
        }
        return JSONObject().apply {
            put("id", info.routeId)
            put("name", info.routeNo)
            put("forward", info.destination)
            put("sub", "default")
            put("bus", busesJson)
        }
    }
    
    // API 호출 결과를 Flutter에 반환할 수 있는 형태(JSON 문자열)로 변환
    fun convertToJson(data: Any): String {
        return gson.toJson(data)
    }
    
    // RouteStation 목록을 JSON 문자열로 변환
    fun convertRouteStationsToJson(stations: List<RouteStation>): String {
        val jsonArray = JSONArray()
        for (station in stations) {
            val jsonObj = JSONObject().apply {
                put("stationId", station.stationId)
                put("stationName", station.stationName)
                put("sequenceNo", station.sequenceNo)
                put("direction", station.direction)
            }
            jsonArray.put(jsonObj)
        }
        return jsonArray.toString()
    }

    suspend fun getStationInfo(stationId: String): List<BusArrivalInfo> = withContext(Dispatchers.IO) {
        try {
            // First, get the raw arrival info using getBusArrivalInfo (which returns a list of StationArrivalOutput)
            val arrivalOutputs = getBusArrivalInfo(stationId)
            // Convert each output to BusArrivalInfo (as expected by Flutter)
            arrivalOutputs.map { output ->
                val buses = output.bus.map { busInfo ->
                    val isLowFloor = busInfo.busNumber.contains("저상")
                    val isOutOfService = busInfo.estimatedTime == "운행종료"
                    BusInfo(
                        busNumber = busInfo.busNumber.replace("(저상)", "").replace("(일반)", ""),
                        currentStation = busInfo.currentStation,
                        remainingStops = busInfo.remainingStations,
                        estimatedTime = busInfo.estimatedTime,
                        isLowFloor = isLowFloor,
                        isOutOfService = isOutOfService
                    )
                }
                BusArrivalInfo(
                    routeId = output.id,
                    routeNo = output.name,
                    destination = output.forward ?: "알 수 없음",
                    buses = buses
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "버스 도착 정보 변환 오류: ${e.message}", e)
            emptyList()
        }
    }
}
