package com.example.daegu_bus_app

import android.content.Context
import android.content.SharedPreferences
import android.util.Log
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.google.gson.reflect.TypeToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
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
import java.io.IOException
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
    suspend fun searchBusRoutes(@Query("searchText", encoded = true) searchText: String): ResponseBody

    @GET("route/info")
    suspend fun getBusRouteInfo(@Query("routeId") routeId: String): ResponseBody

    @GET("bs/route")
    suspend fun getBusRouteMap(@Query("routeId") routeId: String): ResponseBody

    @GET("realtime/pos/{routeId}")
    suspend fun getBusPositionInfo(@Path("routeId") routeId: String): ResponseBody
}

// 모델: 버스 도착 정보 응답
data class BusArrivalResponse(
    val header: Header,
    val body: Body
) {
    data class Header(
        val success: Boolean,
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

data class BusRoute(
    val id: String,
    val routeNo: String,
    val routeTp: String,
    val startPoint: String,
    val endPoint: String,
    val routeDescription: String?
)

data class RouteStation(
    val stationId: String,
    val stationName: String,
    val sequenceNo: Int,
    val direction: String
)

data class BusInfo(
    val busNumber: String,
    val currentStation: String,
    val remainingStops: String,
    val estimatedTime: String,
    val isLowFloor: Boolean = false,
    val isOutOfService: Boolean = false
)

data class BusArrivalInfo(
    val routeId: String,
    val routeNo: String,
    val destination: String,
    val buses: List<BusInfo>
)

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
    suspend fun searchStations(searchText: String): List<WebStationSearchResult> = withContext(Dispatchers.IO) {
        try {
            val encodedText = URLEncoder.encode(searchText, "EUC-KR")
            val url = "$SEARCH_URL?act=findByBS2&bsNm=$encodedText"
            val response = busInfoApi.getStationSearchResult(url)
            val html = String(response.bytes(), Charset.forName("EUC-KR"))
            val document = Jsoup.parse(html)
            val results = mutableListOf<WebStationSearchResult>()
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
                    results.add(WebStationSearchResult(bsId = bsId, bsNm = bsNm))
                }
            }
            results
        } catch (e: Exception) {
            Log.e(TAG, "정류장 검색 오류: ${e.message}", e)
            emptyList()
        }
    }

    // 수정된 노선 검색 함수 - 캐싱 추가
    suspend fun searchBusRoutes(query: String): List<BusRoute> = withContext(Dispatchers.IO) {
        try {
            val fullUrl = "https://businfo.daegu.go.kr:8095/dbms_web_api/route/search?searchText=${URLEncoder.encode(query, "UTF-8")}"
            Log.d(TAG, "요청 URL: $fullUrl")
            
            val response = busInfoApi.searchBusRoutes(query) // 원본 쿼리 전달
            val responseStr = String(response.bytes(), Charset.forName("UTF-8"))
            Log.d(TAG, "API 응답全文: $responseStr")

            val routes = if (responseStr.trim().startsWith("{")) {
                parseJsonBusRoutes(responseStr)
            } else {
                emptyList()
            }

            if (routes.isNotEmpty()) {
                saveCachedBusRoutes(query, routes)
            }
            routes
        } catch (e: Exception) {
            Log.e(TAG, "노선 검색 오류: ${e.message}", e)
            emptyList()
        }
    }

    // JSON 파싱 메서드
    private fun parseJsonBusRoutes(jsonStr: String): List<BusRoute> {
        val routes = mutableListOf<BusRoute>()
        try {
            val json = JSONObject(jsonStr)
            val header = json.optJSONObject("header")
            if (header != null) {
                val success = header.optBoolean("success", false)
                if (!success) {
                    Log.e(TAG, "JSON 응답 실패: ${header.optString("resultMsg", "알 수 없는 오류")}")
                    return routes
                }
            }
            val body = json.optJSONArray("body")
            if (body != null) {
                for (i in 0 until body.length()) {
                    val routeObj = body.getJSONObject(i)
                    val routeId = routeObj.optString("routeId", "")
                    val routeNo = routeObj.optString("routeNo", "")
                    val routeTp = routeObj.optString("routeTCd", "") // "routeTCd" 사용
                    val routeNm = routeObj.optString("routeNm", "")
                    if (routeId.isNotEmpty() && routeNo.isNotEmpty()) {
                        routes.add(
                            BusRoute(
                                id = routeId,
                                routeNo = routeNo,
                                routeTp = routeTp,
                                startPoint = "",
                                endPoint = "",
                                routeDescription = routeNm.ifEmpty { routeNo }
                            )
                        )
                    }
                }
            }
            Log.d(TAG, "JSON 파싱 완료: ${routes.size}개 노선")
        } catch (e: Exception) {
            Log.e(TAG, "JSON 노선 파싱 오류: ${e.message}", e)
        }
        return routes
    }

    // 캐싱된 데이터 로드
    private fun loadCachedBusRoutes(searchText: String): List<BusRoute>? {
        val sharedPreferences: SharedPreferences = context.getSharedPreferences("BusRouteCache", Context.MODE_PRIVATE)
        val cachedJson = sharedPreferences.getString("busRoutes_$searchText", null) ?: return null

        val type = object : TypeToken<List<BusRoute>>() {}.type
        return gson.fromJson(cachedJson, type)
    }

    // 캐싱 데이터 저장
    private fun saveCachedBusRoutes(searchText: String, routes: List<BusRoute>) {
        val sharedPreferences: SharedPreferences = context.getSharedPreferences("BusRouteCache", Context.MODE_PRIVATE)
        val editor = sharedPreferences.edit()
        val json = gson.toJson(routes)
        editor.putString("busRoutes_$searchText", json)
        editor.apply()
    }
        
    // XML 파싱 메서드
    private fun parseXmlBusRoutes(xmlStr: String): List<BusRoute> {
        val routes = mutableListOf<BusRoute>()
        try {
            val document = Jsoup.parse(xmlStr, "", Parser.xmlParser())
            val header = document.select("header").first()
            val success = header?.select("success")?.text() == "true"
            
            if (!success) {
                Log.e(TAG, "XML 응답 실패: ${header?.select("resultMsg")?.text()}")
                return routes
            }
            
            val bodyElements = document.select("body")
            Log.d(TAG, "body 요소 수: ${bodyElements.size}")
            
            bodyElements.forEach { element ->
                val routeId = element.select("routeId").text()
                val routeNo = element.select("routeNo").text()
                val routeTp = element.select("routeTp").text() // 추가
                val routeNm = element.select("routeNm").text()
                
                if (routeId.isNotEmpty() && routeNo.isNotEmpty()) {
                    routes.add(
                        BusRoute(
                            id = routeId,
                            routeNo = routeNo,
                            routeTp = routeTp, // 추가
                            startPoint = "", // 필요 시 API에서 추가 정보 요청
                            endPoint = "",
                            routeDescription = routeNm.ifEmpty { routeNo }
                        )
                    )
                    Log.d(TAG, "노선 추가: $routeNo ($routeId)")
                }
            }
            
            Log.d(TAG, "XML 파싱 완료: ${routes.size}개 노선")
        } catch (e: Exception) {
            Log.e(TAG, "XML 파싱 오류: ${e.message}", e)
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
            throw e
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
    
    // 노선 정보 조회 함수 – 개선된 버전
    suspend fun getBusRouteInfo(routeId: String): BusRoute? = withContext(Dispatchers.IO) {
        try {
            val response = busInfoApi.getBusRouteInfo(routeId)
            var responseStr = String(response.bytes(), Charset.forName("UTF-8"))
            if (containsBrokenKorean(responseStr)) {
                responseStr = String(response.bytes(), Charset.forName("EUC-KR"))
            }

            Log.d(TAG, "Bus Route Info 응답: $responseStr")

            return@withContext if (responseStr.trim().startsWith("{")) {
                parseJsonRouteInfo(responseStr, routeId)
            } else if (responseStr.trim().startsWith("<")) {
                parseXmlRouteInfo(responseStr, routeId)
            } else {
                Log.e(TAG, "알 수 없는 응답 형식: ${responseStr.substring(0, minOf(responseStr.length, 50))}")
                null
            }
        } catch (e: Exception) {
            Log.e(TAG, "버스 노선 정보 조회 오류: ${e.message}", e)
            return@withContext null
        }
    }
    
    // JSON 노선 정보 파싱 - 한글 깨짐 처리 추가
    private fun parseJsonRouteInfo(jsonStr: String, routeId: String): BusRoute? {
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
                routeTp = body.optString("routeTp", ""), // 추가
                startPoint = body.optString("stNm", "출발지 정보 없음"),
                endPoint = body.optString("edNm", "도착지 정보 없음"),
                routeDescription = "배차간격: ${body.optString("avgTm", "정보 없음")}, 업체: ${body.optString("comNm", "정보 없음")}"
            )
        } catch (e: Exception) {
            Log.e(TAG, "JSON 노선 정보 파싱 오류: ${e.message}", e)
            return null
        }
    }
    
    // XML 노선 정보 파싱
    private fun parseXmlRouteInfo(xmlStr: String, routeId: String): BusRoute? {
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
                    routeTp = bodyElement.select("routeTp").text(), // 추가
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
                return@withContext emptyList()
            }
            
            val response = busInfoApi.getBusRouteMap(routeId)
            val responseStr = String(response.bytes(), Charset.forName("UTF-8"))
            
            val jsonObj = JSONObject(responseStr)
            val header = jsonObj.getJSONObject("header")
            
            if (!header.getBoolean("success")) {
                Log.e(TAG, "노선도 조회 실패: ${header.getString("resultMsg")}")
                return@withContext emptyList()
            }
            
            val bodyArray = jsonObj.getJSONArray("body")
            val stationList = mutableListOf<RouteStation>()
            
            for (i in 0 until bodyArray.length()) {
                val stationObj = bodyArray.getJSONObject(i)
                stationList.add(
                    RouteStation(
                        stationId = stationObj.getString("bsId"),
                        stationName = stationObj.getString("bsNm"),
                        sequenceNo = stationObj.getDouble("seq").toInt(),
                        direction = stationObj.getString("moveDir")
                    )
                )
            }
            
            stationList.sortedBy { it.sequenceNo }
        } catch (e: Exception) {
            Log.e(TAG, "노선도 조회 오류: ${e.message}", e)
            emptyList()
        }
    }
        
    private fun parseJsonRouteStations(jsonStr: String): List<RouteStation> {
        return emptyList()
    }
    
    private fun parseXmlRouteStations(xmlStr: String): List<RouteStation> {
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
                put("lat", 0.0) 
                put("lng", 0.0) 
                // 기존 direction 필드도 유지
                put("direction", station.direction ?: "")
            }
            jsonArray.put(jsonObj)
        }
        return jsonArray.toString()
    }

    // 정류장 도착 정보 조회 함수 - JSONObject/JSONArray 직접 사용으로 변경
    suspend fun getStationInfo(stationId: String): String {
        return withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "정류장($stationId) 도착 정보 조회 시작")
                
                // API 호출
                val url = "https://businfo.daegu.go.kr:8095/dbms_web_api/realtime/arr2/$stationId"
                val request = Request.Builder().url(url).build()
                val response = okHttpClient.newCall(request).execute()
                
                if (!response.isSuccessful) {
                    Log.e(TAG, "API 호출 실패: ${response.code}")
                    throw IOException("API 호출 실패: ${response.code}")
                }
                
                val responseBody = response.body?.string() ?: throw IOException("응답 본문이 비어있습니다")
                
                // JSONObject로 직접 파싱
                val jsonObj = JSONObject(responseBody)
                val header = jsonObj.getJSONObject("header")
                
                if (!header.getBoolean("success")) {
                    val resultMsg = header.getString("resultMsg")
                    Log.e(TAG, "API 오류: $resultMsg")
                    throw IOException("API 오류: $resultMsg")
                }
                
                val body = jsonObj.getJSONObject("body")
                val resultArray = JSONArray()
                
                // 노선 목록 확인
                if (body.has("list") && !body.isNull("list")) {
                    val list = body.getJSONArray("list")
                    
                    for (i in 0 until list.length()) {
                        val routeInfo = list.getJSONObject(i)
                        val resultRouteObj = JSONObject()
                        
                        // 기본 노선 정보 복사
                        val keys = routeInfo.keys()
                        while (keys.hasNext()) {
                            val key = keys.next()
                            resultRouteObj.put(key, routeInfo.get(key))
                        }
                        
                        // arrList 처리
                        if (routeInfo.has("arrList") && !routeInfo.isNull("arrList")) {
                            val arrList = routeInfo.getJSONArray("arrList")
                            val resultArrArray = JSONArray()
                            
                            for (j in 0 until arrList.length()) {
                                resultArrArray.put(arrList.getJSONObject(j))
                            }
                            
                            resultRouteObj.put("arrList", resultArrArray)
                        }
                        
                        resultArray.put(resultRouteObj)
                    }
                }
                
                Log.d(TAG, "정류장 도착 정보 조회 결과: ${resultArray.length()}개 노선")
                return@withContext resultArray.toString()
            } catch (e: Exception) {
                Log.e(TAG, "정류장 도착 정보 조회 오류: ${e.message}", e)
                throw e
            }
        }
    }

    // bsId(wincId)를 stationId(bsId)로 변환하는 메서드
    suspend fun getStationIdFromBsId(wincId: String): String? = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "wincId($wincId)에 대한 stationId 조회 시작")
            val url = "${BASE_URL}bs/search?searchText=&wincId=$wincId"
            
            val response = busInfoApi.getStationSearchResult(url)
            var responseStr = String(response.bytes(), Charset.forName("UTF-8"))
            
            if (containsBrokenKorean(responseStr)) {
                responseStr = String(response.bytes(), Charset.forName("EUC-KR"))
            }
            
            Log.d(TAG, "응답 데이터 미리보기: ${responseStr.take(200)}")
            
            // XML 또는 JSON 응답 처리
            if (responseStr.trim().startsWith("<")) {
                // XML 파싱
                val document = Jsoup.parse(responseStr, "", Parser.xmlParser())
                val header = document.select("header").first()
                val success = header?.select("success")?.text() == "true"
                
                if (!success) {
                    Log.e(TAG, "API 요청 실패: ${header?.select("resultMsg")?.text()}")
                    return@withContext null
                }
                
                val bodyElement = document.select("body").first()
                if (bodyElement != null) {
                    val stationId = bodyElement.select("bsId").text()
                    if (stationId.isNotEmpty()) {
                        Log.d(TAG, "wincId($wincId)에 대한 stationId($stationId) 찾음")
                        return@withContext stationId
                    }
                }
            } else if (responseStr.startsWith("{")) {
                // JSON 파싱
                val jsonObj = JSONObject(responseStr)
                val header = jsonObj.getJSONObject("header")
                val success = header.getBoolean("success")
                
                if (!success) {
                    Log.e(TAG, "API 요청 실패: ${header.getString("resultMsg")}")
                    return@withContext null
                }
                
                val body = jsonObj.optJSONArray("body")
                if (body != null && body.length() > 0) {
                    val stationInfo = body.getJSONObject(0)
                    val stationId = stationInfo.optString("bsId", "")
                    
                    if (stationId.isNotEmpty()) {
                        Log.d(TAG, "wincId($wincId)에 대한 stationId($stationId) 찾음")
                        return@withContext stationId
                    }
                }
            }
            
            Log.w(TAG, "wincId($wincId)에 대한 stationId를 찾을 수 없음")
            null
        } catch (e: Exception) {
            Log.e(TAG, "wincId($wincId)에 대한 stationId 조회 오류: ${e.message}", e)
            null
        }
    }
}