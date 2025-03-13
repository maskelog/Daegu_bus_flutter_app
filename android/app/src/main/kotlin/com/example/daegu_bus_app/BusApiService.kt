package com.example.daegu_bus_app

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.google.gson.JsonParser
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

// 모델: 정류장 검색 결과 (기존)
data class StationSearchResult(
    val bsId: String,
    val bsNm: String
)

// 모델: 버스 도착 정보 응답 (기존)
data class BusArrivalResponse(
    val header: Header,
    val body: Body
) {
    data class Header(
        val success: String,
        val resultCode: String,
        val resultMsg: String
    )
    data class Body(
        val blockMsg: String?,
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

// 모델: 클라이언트 응답용 도착 정보 (기존)
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

// 모델: 노선 정보 (BusRoute) – Flutter 모델과 일치
data class BusRoute(
    val id: String,
    val routeNo: String,
    val startPoint: String,
    val endPoint: String,
    val routeDescription: String
)

// 모델: 노선의 정류장 (RouteStation) – Flutter 모델과 일치
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
    val remainingStations: String,
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
    
    // 정류장 검색 함수 (기존 방식 그대로)
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
            return@withContext results
        } catch (e: Exception) {
            Log.e(TAG, "정류장 검색 오류: ${e.message}", e)
            return@withContext emptyList()
        }
    }
    
    // 버스 도착 정보 조회 함수
    suspend fun getBusArrivalInfo(stationId: String): List<StationArrivalOutput> = withContext(Dispatchers.IO) {
        try {
            val response = busInfoApi.getBusArrivalInfo(stationId)
            if (response.header.success != "true") {
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
            return@withContext groups.values.toList()
        } catch (e: Exception) {
            Log.e(TAG, "버스 도착 정보 조회 오류: ${e.message}", e)
            return@withContext emptyList()
        }
    }
    
    // Flutter에서 사용할 수 있는 BusArrivalInfo 변환 메서드 추가
    suspend fun getStationInfo(stationId: String): List<BusArrivalInfo> = withContext(Dispatchers.IO) {
        try {
            val arrivalOutputs = getBusArrivalInfo(stationId)
            return@withContext arrivalOutputs.map { output ->
                val buses = output.bus.map { busInfo ->
                    val isLowFloor = busInfo.busNumber.contains("저상")
                    val isOutOfService = busInfo.estimatedTime == "운행종료"
                    
                    BusInfo(
                        busNumber = busInfo.busNumber.replace("(저상)", "").replace("(일반)", ""),
                        currentStation = busInfo.currentStation,
                        remainingStations = busInfo.remainingStations,
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
            return@withContext emptyList()
        }
    }
    
    // BusArrivalInfo를 Flutter의 BusArrival로 변환하는 메서드
    fun convertToBusArrival(info: BusArrivalInfo): JSONObject {
        val busesJson = JSONArray()
        
        info.buses.forEach { bus ->
            val busJson = JSONObject().apply {
                put("버스번호", bus.busNumber)
                put("현재정류소", bus.currentStation)
                put("남은정류소", bus.remainingStations)
                put("도착예정소요시간", bus.estimatedTime)
            }
            busesJson.put(busJson)
        }
        
        val json = JSONObject().apply {
            put("id", info.routeId)
            put("name", info.routeNo)
            put("forward", info.destination)
            put("sub", "default")
            put("bus", busesJson)
        }
        
        return json
    }
    
    // 노선 검색 함수 - 개선된 버전
    suspend fun searchBusRoutes(query: String): List<BusRoute> = withContext(Dispatchers.IO) {
        try {
            val encodedQuery = URLEncoder.encode(query, "EUC-KR")
            val response = busInfoApi.searchBusRoutes(encodedQuery)
            val responseStr = String(response.bytes(), Charset.forName("EUC-KR"))
            Log.d(TAG, "Bus Route Search 응답: $responseStr")
            
            // 응답이 JSON인지 XML인지 확인
            return@withContext if (responseStr.trim().startsWith("{")) {
                parseJsonBusRoutes(responseStr)
            } else if (responseStr.trim().startsWith("<")) {
                parseXmlBusRoutes(responseStr)
            } else {
                Log.e(TAG, "알 수 없는 응답 형식: ${responseStr.substring(0, minOf(responseStr.length, 50))}")
                emptyList()
            }
        } catch (e: Exception) {
            Log.e(TAG, "노선 검색 오류: ${e.message}", e)
            return@withContext emptyList()
        }
    }
    
    // JSON 응답 파싱
    private fun parseJsonBusRoutes(jsonStr: String): List<BusRoute> {
        try {
            val jsonObj = JSONObject(jsonStr)
            val header = jsonObj.getJSONObject("header")
            val success = header.optBoolean("success", false)
            
            if (!success) {
                val resultMsg = header.optString("resultMsg", "Unknown error")
                Log.e(TAG, "노선 검색 실패: $resultMsg")
                return emptyList()
            }
            
            val routes = mutableListOf<BusRoute>()
            
            if (jsonObj.has("body")) {
                val body = jsonObj.get("body")
                
                if (body is JSONArray) {
                    // body가 배열인 경우
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
                    // body가 단일 객체인 경우
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
            }
            
            return routes
        } catch (e: Exception) {
            Log.e(TAG, "JSON 파싱 오류: ${e.message}", e)
            return emptyList()
        }
    }
    
    // XML 응답 파싱
    private fun parseXmlBusRoutes(xmlStr: String): List<BusRoute> {
        try {
            val document = Jsoup.parse(xmlStr, "", Parser.xmlParser())
            val headerElement = document.select("Result > header").firstOrNull() 
                ?: document.select("header").firstOrNull()
            
            val success = headerElement?.select("success")?.text() == "true"
            if (!success) {
                val resultMsg = headerElement?.select("resultMsg")?.text() ?: "Unknown error"
                Log.e(TAG, "노선 검색 실패: $resultMsg")
                return emptyList()
            }
            
            val routes = mutableListOf<BusRoute>()
            val bodyElements = document.select("Result > body")
                .ifEmpty { document.select("body") }
            
            for (bodyElement in bodyElements) {
                val routeId = bodyElement.select("routeId").text()
                val routeNo = bodyElement.select("routeNo").text()
                val routeNm = bodyElement.select("routeNm").text()
                
                if (routeId.isNotEmpty() && routeNo.isNotEmpty()) {
                    Log.d(TAG, "노선 ID 찾음: $routeId, 노선번호: $routeNo")
                    routes.add(
                        BusRoute(
                            id = routeId,
                            routeNo = routeNo,
                            startPoint = "",
                            endPoint = "",
                            routeDescription = routeNm.ifEmpty { routeNo }
                        )
                    )
                }
            }
            
            return routes
        } catch (e: Exception) {
            Log.e(TAG, "XML 파싱 오류: ${e.message}", e)
            return emptyList()
        }
    }
    
    // 노선 정보 조회 함수 – 개선된 버전
    suspend fun getBusRouteInfo(routeId: String): BusRoute? = withContext(Dispatchers.IO) {
        try {
            val response = busInfoApi.getBusRouteInfo(routeId)
            
            // 다양한 인코딩 시도 (getBusRouteMap과 동일한 방식 적용)
            var responseStr = String(response.bytes(), Charset.forName("UTF-8"))
            if (containsBrokenKorean(responseStr)) {
                responseStr = String(response.bytes(), Charset.forName("EUC-KR"))
            }
            
            Log.d(TAG, "Bus Route Info 응답: $responseStr")
            
            // 응답이 JSON인지 XML인지 확인
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
                val resultMsg = header.optString("resultMsg", "Unknown error")
                Log.e(TAG, "노선 정보 조회 실패: $resultMsg")
                return null
            }
            
            val body = resultObj.getJSONObject("body")
            
            // 한글 값 처리 - 깨진 경우 대체 텍스트 제공
            var stNm = body.optString("stNm", "")
            var edNm = body.optString("edNm", "")
            var avgTm = body.optString("avgTm", "")
            var comNm = body.optString("comNm", "")
            
            // 깨진 한글 대체
            if (stNm.contains("�")) stNm = "출발지 정보 없음"
            if (edNm.contains("�")) edNm = "도착지 정보 없음"
            if (avgTm.contains("�")) avgTm = "배차 정보 없음"
            if (comNm.contains("�")) comNm = "운수사 정보 없음"
            
            return BusRoute(
                id = body.optString("routeId", routeId),
                routeNo = body.optString("routeNo", ""),
                startPoint = stNm,
                endPoint = edNm,
                routeDescription = "배차간격: $avgTm, 업체: $comNm"
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
            val headerElement = document.select("Result > header").firstOrNull() 
                ?: document.select("header").firstOrNull()
            
            val success = headerElement?.select("success")?.text() == "true"
            if (!success) {
                val resultMsg = headerElement?.select("resultMsg")?.text() ?: "Unknown error"
                Log.e(TAG, "노선 정보 조회 실패: $resultMsg")
                return null
            }
            
            val bodyElement = document.select("Result > body").firstOrNull()
                ?: document.select("body").firstOrNull()
                
            if (bodyElement != null) {
                val routeIdVal = bodyElement.select("routeId").text().ifEmpty { routeId }
                val routeNo = bodyElement.select("routeNo").text()
                val stNm = bodyElement.select("stNm").text()
                val edNm = bodyElement.select("edNm").text()
                val avgTm = bodyElement.select("avgTm").text()
                val comNm = bodyElement.select("comNm").text()

                return BusRoute(
                    id = routeIdVal,
                    routeNo = routeNo,
                    startPoint = stNm,
                    endPoint = edNm,
                    routeDescription = "배차간격: $avgTm, 업체: $comNm"
                )
            }
            
            return null
        } catch (e: Exception) {
            Log.e(TAG, "XML 노선 정보 파싱 오류: ${e.message}", e)
            return null
        }
    }
    
    // 실시간 버스 위치 정보 조회 함수 (기존 그대로)
    suspend fun getBusPositionInfo(routeId: String): String = withContext(Dispatchers.IO) {
        try {
            val response = busInfoApi.getBusPositionInfo(routeId)
            return@withContext String(response.bytes())
        } catch (e: Exception) {
            Log.e(TAG, "실시간 버스 위치 정보 조회 오류: ${e.message}", e)
            return@withContext "{\"error\": \"${e.message}\"}"
        }
    }
    
    // 버스 노선도 조회 함수 - 수정된 인코딩 처리
    suspend fun getBusRouteMap(routeId: String): List<RouteStation> = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "노선도 조회 요청: routeId=$routeId, URL=${BASE_URL}bs/route?routeId=$routeId")
            
            if (routeId.isEmpty()) {
                Log.e(TAG, "빈 routeId, 노선도 조회 불가")
                return@withContext emptyList<RouteStation>()
            }
            
            val response = busInfoApi.getBusRouteMap(routeId)
            
            // 다양한 인코딩 시도
            var responseStr = String(response.bytes(), Charset.forName("UTF-8"))
            if (containsBrokenKorean(responseStr)) {
                responseStr = String(response.bytes(), Charset.forName("EUC-KR"))
            }
            
            Log.d(TAG, "버스 노선도 응답 수신 (길이: ${responseStr.length})")
            
            // 응답 샘플 로깅
            if (responseStr.length > 200) {
                Log.d(TAG, "응답 샘플: ${responseStr.substring(0, 200)}...")
            } else {
                Log.d(TAG, "응답 샘플: $responseStr")
            }
            
            // 응답이 JSON 형식인지 확인
            if (responseStr.trim().startsWith("{")) {
                return@withContext parseJsonRouteStations(responseStr)
            } 
            // XML 형식인 경우
            else if (responseStr.trim().startsWith("<")) {
                return@withContext parseXmlRouteStations(responseStr)
            } 
            // 알 수 없는 형식
            else {
                Log.e(TAG, "알 수 없는 응답 형식")
                return@withContext emptyList<RouteStation>()
            }
        } catch (e: Exception) {
            Log.e(TAG, "노선도 조회 오류: ${e.message}")
            e.printStackTrace()
            return@withContext emptyList<RouteStation>()
        }
    }

    // 한글 깨짐 여부 확인 함수
    private fun containsBrokenKorean(text: String): Boolean {
        // 한글 유니코드 범위: AC00-D7A3 (가-힣)
        val koreanPattern = Regex("[\\uAC00-\\uD7A3]+")
        val matches = koreanPattern.findAll(text)
        return matches.count() == 0 && text.contains("�")
    }

    // JSON 노선도 파싱 메서드 - 인코딩 처리 개선
    private fun parseJsonRouteStations(jsonStr: String): List<RouteStation> {
        try {
            val jsonObj = JSONObject(jsonStr)
            val header = jsonObj.getJSONObject("header")
            val success = header.optString("success") == "true" || header.optBoolean("success", false)
            
            if (!success) {
                val resultMsg = header.optString("resultMsg", "Unknown error")
                Log.e(TAG, "노선도 조회 실패 (JSON): $resultMsg")
                return emptyList()
            }
            
            val stations = mutableListOf<RouteStation>()
            val bodyArray = jsonObj.getJSONArray("body")
            
            Log.d(TAG, "찾은 정류장 수 (JSON): ${bodyArray.length()}")
            
            for (i in 0 until bodyArray.length()) {
                val station = bodyArray.getJSONObject(i)
                val bsId = station.optString("bsId", "")
                var bsNm = station.optString("bsNm", "")
                val seqStr = station.optString("seq", "0")
                val moveDir = station.optString("moveDir", "")
                
                // 한글 이름이 깨져있는 경우 기본 이름으로 대체
                if (bsNm.contains("�")) {
                    bsNm = "정류장 $i"
                }
                
                // 시퀀스 값을 안전하게 파싱
                val seq = try {
                    seqStr.toDoubleOrNull()?.toInt() ?: 0
                } catch (e: Exception) {
                    Log.w(TAG, "시퀀스 값 파싱 오류: $seqStr")
                    0
                }
                
                if (bsId.isNotEmpty()) {
                    stations.add(
                        RouteStation(
                            stationId = bsId,
                            stationName = bsNm,
                            sequenceNo = seq,
                            direction = moveDir
                        )
                    )
                    
                    // 처음 몇 개와 마지막 몇 개의 정류장 정보만 로깅
                    if (stations.size <= 3 || stations.size >= bodyArray.length() - 2) {
                        Log.d(TAG, "정류장 정보: ID=$bsId, 이름=$bsNm, 순서=$seq, 방향=$moveDir")
                    }
                }
            }
            
            // 시퀀스 번호로 정렬
            val sortedList = stations.sortedBy { it.sequenceNo }
            
            if (sortedList.isNotEmpty()) {
                val first = sortedList.first()
                val last = sortedList.last()
                Log.d(TAG, "첫 번째 정류장: ${first.stationName} (ID: ${first.stationId}, 순서: ${first.sequenceNo})")
                Log.d(TAG, "마지막 정류장: ${last.stationName} (ID: ${last.stationId}, 순서: ${last.sequenceNo})")
            }
            
            Log.d(TAG, "최종 정류장 목록 개수: ${sortedList.size}")
            
            return sortedList
        } catch (e: Exception) {
            Log.e(TAG, "JSON 노선도 파싱 오류: ${e.message}", e)
            e.printStackTrace()
            return emptyList()
        }
    }

    // XML 노선도 파싱 메서드 (기존 로직 분리)
    private fun parseXmlRouteStations(xmlStr: String): List<RouteStation> {
        try {
            val document = Jsoup.parse(xmlStr, "", Parser.xmlParser())
            val headerElement = document.select("Result > header").firstOrNull() 
                ?: document.select("header").firstOrNull()
            
            val success = headerElement?.select("success")?.text() == "true"
            if (!success) {
                val resultMsg = headerElement?.select("resultMsg")?.text() ?: "Unknown error"
                Log.e(TAG, "노선도 조회 실패 (XML): $resultMsg")
                return emptyList()
            }
            
            val stationList = mutableListOf<RouteStation>()
            val bodyElements = document.select("Result > body")
                .ifEmpty { document.select("body") }
                
            Log.d(TAG, "찾은 정류장 수 (XML): ${bodyElements.size}")
                
            for (element in bodyElements) {
                val bsId = element.select("bsId").text()
                val bsNm = element.select("bsNm").text()
                val seqStr = element.select("seq").text()
                val moveDir = element.select("moveDir").text()
                
                // 시퀀스 값을 안전하게 파싱
                val seq = try {
                    seqStr.toDoubleOrNull()?.toInt() ?: 0
                } catch (e: Exception) {
                    Log.w(TAG, "시퀀스 값 파싱 오류: $seqStr")
                    0
                }
                
                if (bsId.isNotEmpty() && bsNm.isNotEmpty()) {
                    stationList.add(
                        RouteStation(
                            stationId = bsId,
                            stationName = bsNm,
                            sequenceNo = seq,
                            direction = moveDir
                        )
                    )
                }
            }
            
            // 시퀀스 번호로 정렬
            return stationList.sortedBy { it.sequenceNo }
        } catch (e: Exception) {
            Log.e(TAG, "XML 노선도 파싱 오류: ${e.message}", e)
            return emptyList()
        }
    }
    
    // 버스 도착 정보 조회 by 노선 ID
    suspend fun getBusArrivalInfoByRouteId(stationId: String, routeId: String): StationArrivalOutput? = withContext(Dispatchers.IO) {
        try {
            val allArrivals = getBusArrivalInfo(stationId)
            val result = allArrivals.find { it.id == routeId }
            
            if (result != null && result.forward == null) {
                // forward가 null인 경우 기본값 "알 수 없음" 설정
                return@withContext result.copy(forward = "알 수 없음")
            }
            
            return@withContext result
        } catch (e: Exception) {
            Log.e(TAG, "노선별 버스 도착 정보 조회 오류: ${e.message}", e)
            return@withContext null
        }
    }

    // API 호출 결과를 Flutter에 반환할 수 있는 형태로 변환 (JSON 문자열)
    fun convertToJson(data: Any): String {
        return gson.toJson(data)
    }
    
    // RouteStation 객체를 Flutter에서 사용할 JSON 문자열로 변환
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
}