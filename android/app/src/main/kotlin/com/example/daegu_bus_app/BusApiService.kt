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
        .followRedirects(true)
        .followSslRedirects(true)
        .retryOnConnectionFailure(true)
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
            Log.d(TAG, "정류장 검색 요청 URL: $url")
            
            val response = busInfoApi.getStationSearchResult(url)
            // 명시적 Charset 객체 사용
            val eucKrCharset = Charset.forName("EUC-KR") 
            val responseBytes = response.bytes()
            Log.d(TAG, "응답 바이트 길이: ${responseBytes.size}")
            
            val html = String(responseBytes, eucKrCharset)
            Log.d(TAG, "정류장 검색 응답 (길이: ${html.length}): ${html.take(200)}...")
            
            if (html.isEmpty() || !html.contains("arrResultBsPanel")) {
                Log.w(TAG, "유효한 응답이 아닙니다. 직접 HTTP 요청을 시도합니다.")
                return@withContext searchStationsFallback(searchText)
            }
            
            val document = Jsoup.parse(html)
            val elements = document.select("#arrResultBsPanel td.body_col1")
            Log.d(TAG, "파싱된 요소 수: ${elements.size}")
            
            val results = mutableListOf<WebStationSearchResult>()
            elements.forEach { element ->
                val onclick = element.attr("onclick") ?: ""
                Log.v(TAG, "onclick 속성: $onclick")
                val firstcom = onclick.indexOf("'")
                val lastcom = onclick.indexOf("'", firstcom + 1)
                if (firstcom >= 0 && lastcom > firstcom) {
                    val bsId = onclick.substring(firstcom + 1, lastcom)
                    var bsNm = element.text().trim()
                    if (bsNm.length > 7) {
                        bsNm = bsNm.substring(0, bsNm.length - 7).trim()
                    }
                    results.add(WebStationSearchResult(bsId = bsId, bsNm = bsNm))
                    Log.d(TAG, "추가된 정류장: bsId=$bsId, bsNm=$bsNm")
                } else {
                    Log.w(TAG, "onclick 파싱 실패: $onclick")
                }
            }
            Log.d(TAG, "정류장 검색 결과: ${results.size}개")
            results
        } catch (e: Exception) {
            Log.e(TAG, "정류장 검색 오류: ${e.message}", e)
            searchStationsFallback(searchText)
        }
    }

    // 대체 검색 방법 구현
    private suspend fun searchStationsFallback(searchText: String): List<WebStationSearchResult> = withContext(Dispatchers.IO) {
        try {
            Log.i(TAG, "대체 정류장 검색 시작: $searchText")
            val encodedText = URLEncoder.encode(searchText, "EUC-KR")
            val url = "$SEARCH_URL?act=findByBS2&bsNm=$encodedText"
            
            val request = Request.Builder().url(url).build()
            val response = okHttpClient.newCall(request).execute()
            
            if (!response.isSuccessful) {
                Log.e(TAG, "대체 검색 실패: ${response.code}")
                return@withContext emptyList()
            }
            
            val responseBytes = response.body?.bytes() ?: return@withContext emptyList()
            Log.i(TAG, "대체 검색 응답 바이트 길이: ${responseBytes.size}")
            
            val eucKrCharset = Charset.forName("EUC-KR")
            val html = String(responseBytes, eucKrCharset)
            
            if (html.isEmpty()) {
                Log.e(TAG, "대체 검색 응답이 비어있습니다")
                return@withContext emptyList()
            }
            
            // 정규식으로 파싱 (HTML 파싱 라이브러리가 난독화로 인해 문제가 있을 경우)
            val results = mutableListOf<WebStationSearchResult>()
            
            val regex = "onclick=\"showStationInfo\\('([^']+)'\\)\"[^>]*>([^<]+)".toRegex()
            val matches = regex.findAll(html)
            
            matches.forEach { match ->
                val bsId = match.groupValues[1]
                var bsNm = match.groupValues[2].trim()
                if (bsNm.length > 7) {
                    bsNm = bsNm.substring(0, bsNm.length - 7).trim()
                }
                results.add(WebStationSearchResult(bsId = bsId, bsNm = bsNm))
                Log.i(TAG, "대체 검색으로 추가된 정류장: $bsId, $bsNm")
            }
            
            Log.i(TAG, "대체 검색 결과: ${results.size}개")
            return@withContext results
        } catch (e: Exception) {
            Log.e(TAG, "대체 정류장 검색 오류: ${e.message}", e)
            return@withContext emptyList()
        }
    }

    // 노선 검색 함수
    suspend fun searchBusRoutes(query: String): List<BusRoute> = withContext(Dispatchers.IO) {
        try {
            val response = busInfoApi.searchBusRoutes(URLEncoder.encode(query, "UTF-8"))
            val responseStr = String(response.bytes(), Charset.forName("UTF-8"))
            Log.d(TAG, "노선 검색 응답: $responseStr")

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
            loadCachedBusRoutes(query) ?: emptyList()
        }
    }

    // JSON 파싱 메서드
    private fun parseJsonBusRoutes(jsonStr: String): List<BusRoute> {
        val routes = mutableListOf<BusRoute>()
        try {
            val json = JSONObject(jsonStr)
            val header = json.optJSONObject("header")
            if (header != null && !header.optBoolean("success", false)) {
                Log.e(TAG, "JSON 응답 실패: ${header.optString("resultMsg", "알 수 없는 오류")}")
                return routes
            }
            val body = json.optJSONArray("body")
            if (body != null) {
                for (i in 0 until body.length()) {
                    val routeObj = body.getJSONObject(i)
                    val routeId = routeObj.optString("routeId", "")
                    val routeNo = routeObj.optString("routeNo", "")
                    val routeTp = routeObj.optString("routeTCd", "")
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
            val responseStr = String(response.bytes(), Charset.forName("UTF-8"))
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
            null
        }
    }

    // JSON 노선 정보 파싱
    private fun parseJsonRouteInfo(jsonStr: String, routeId: String): BusRoute? {
        try {
            val jsonObj = JSONObject(jsonStr)
            val header = jsonObj.getJSONObject("header")
            if (!header.optBoolean("success", false)) {
                Log.e(TAG, "노선 정보 조회 실패: ${header.optString("resultMsg")}")
                return null
            }
            val body = jsonObj.getJSONObject("body")
            return BusRoute(
                id = body.optString("routeId", routeId),
                routeNo = body.optString("routeNo", ""),
                routeTp = body.optString("routeTp", ""),
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
                    routeTp = bodyElement.select("routeTp").text(),
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

    // bsId(wincId)를 이용해 stationId를 조회하는 함수
    suspend fun getStationIdFromBsId(wincId: String): String? = withContext(Dispatchers.IO) {
        try {
            if (wincId.startsWith("7") && wincId.length == 10) {
                Log.d(TAG, "wincId '$wincId'는 이미 stationId 형식입니다")
                return@withContext wincId
            }
            
            // BASE_URL 끝의 슬래시 제거
            val url = "${BASE_URL.trimEnd('/')}/bs/search?searchText=&wincId=$wincId"
            Log.d(TAG, "정류장 검색 API 호출: $url")
            val request = Request.Builder().url(url).build()
            val response = okHttpClient.newCall(request).execute()
            
            if (!response.isSuccessful) {
                val errorBody = response.body?.string() ?: ""
                Log.e(TAG, "검색 API 호출 실패: ${response.code}, 응답: $errorBody")
                return@withContext null
            }
            
            // response.body?.string()는 한 번만 호출하여 값을 저장
            val responseBody = response.body?.string() ?: ""
            Log.d(TAG, "검색 API 응답: $responseBody")
            
            // JSON 응답으로 stationId 추출
            val jsonResponse = JSONObject(responseBody)
            val header = jsonResponse.optJSONObject("header")
            if (header == null || !header.optBoolean("success", false)) {
                Log.e(TAG, "검색 API 응답 실패: ${header?.optString("resultMsg", "알 수 없는 오류")}")
                return@withContext null
            }
            
            val bodyArray = jsonResponse.optJSONArray("body")
            if (bodyArray != null && bodyArray.length() > 0) {
                val firstItem = bodyArray.getJSONObject(0)
                val realStationId = firstItem.optString("bsId", "")
                if (realStationId.isNotEmpty()) {
                    Log.d(TAG, "검색 API로 wincId '$wincId'에 대한 stationId '$realStationId' 조회 성공")
                    return@withContext realStationId
                }
            }
            
            Log.w(TAG, "검색 API 응답에서 stationId를 찾지 못함: $responseBody")
            return@withContext null
            
        } catch (e: Exception) {
            Log.e(TAG, "stationId 변환 오류: ${e.message}", e)
            Log.w(TAG, "예외 발생, stationId 조회 실패: '$wincId'")
            return@withContext null
        }
    }

    // 정류장 도착 정보 조회 함수
    suspend fun getStationInfo(stationId: String): String = withContext(Dispatchers.IO) {
        try {
            Log.d(TAG, "정류장($stationId) 도착 정보 조회 시작")
            
            val effectiveStationId = if (stationId.length < 10 || !stationId.startsWith("7")) {
                val convertedId = getStationIdFromBsId(stationId)
                if (convertedId == null) {
                    Log.e(TAG, "유효한 stationId로 변환 실패: $stationId")
                    return@withContext "[]"
                } else {
                    convertedId
                }
            } else {
                stationId
            }
            
            // BASE_URL의 끝에 있는 슬래시를 제거하여 이중 슬래시 문제 해결
            val baseUrlFixed = BASE_URL.trimEnd('/')
            val url = "$baseUrlFixed/realtime/arr2/$effectiveStationId"
            Log.d(TAG, "API 호출 URL: $url")
            
            val request = Request.Builder().url(url).build()
            val response = okHttpClient.newCall(request).execute()
            
            if (!response.isSuccessful) {
                Log.e(TAG, "API 호출 실패: ${response.code}, 응답: ${response.body?.string()}")
                return@withContext "[]"
            }
            
            val responseBody = response.body?.string() ?: return@withContext "[]"
            return@withContext processResponse(responseBody, effectiveStationId)
            
        } catch (e: Exception) {
            Log.e(TAG, "정류장 도착 정보 조회 오류: ${e.message}", e)
            return@withContext "[]"
        }
    }

    // 응답 처리 함수
    private fun processResponse(responseBody: String, stationId: String): String {
        try {
            if (responseBody.isEmpty()) {
                Log.w(TAG, "빈 응답 수신됨")
                return "[]"
            }
            
            Log.d(TAG, "원본 응답 (일부): ${responseBody.take(200)}...")
            
            val jsonObj = JSONObject(responseBody)
            val header = jsonObj.optJSONObject("header")
            
            if (header == null || !header.optBoolean("success", false)) {
                Log.e(TAG, "API 응답 실패: ${header?.optString("resultMsg", "알 수 없는 오류")}")
                return "[]"
            }
            
            val body = jsonObj.optJSONObject("body") ?: return "[]"
            val list = body.optJSONArray("list") ?: return "[]"
            
            val resultArray = JSONArray()
            
            for (i in 0 until list.length()) {
                val routeInfo = list.getJSONObject(i)
                val routeNo = routeInfo.optString("routeNo", "")
                val arrList = routeInfo.optJSONArray("arrList") ?: JSONArray()
                
                val resultRouteObj = JSONObject().apply {
                    put("routeNo", routeNo)
                    put("arrList", JSONArray())
                }
                
                val resultArrList = resultRouteObj.getJSONArray("arrList")
                
                for (j in 0 until arrList.length()) {
                    val arrival = arrList.getJSONObject(j)
                    
                    val arrivalObj = JSONObject().apply {
                        put("routeId", arrival.optString("routeId", ""))
                        put("routeNo", arrival.optString("routeNo", routeNo))
                        put("moveDir", arrival.optString("moveDir", ""))
                        put("bsGap", arrival.optInt("bsGap", -1))
                        put("bsNm", arrival.optString("bsNm", ""))
                        put("vhcNo2", arrival.optString("vhcNo2", ""))
                        put("busTCd2", arrival.optString("busTCd2", ""))
                        put("busTCd3", arrival.optString("busTCd3", ""))
                        put("busAreaCd", arrival.optString("busAreaCd", ""))
                        put("arrState", arrival.optString("arrState", ""))
                        put("prevBsGap", arrival.optInt("prevBsGap", -1))
                    }
                    
                    resultArrList.put(arrivalObj)
                }
                
                if (resultArrList.length() > 0) {
                    resultArray.put(resultRouteObj)
                }
            }
            
            Log.d(TAG, "정류장 도착 정보 파싱 완료: ${resultArray.length()}개 노선")
            return resultArray.toString()
            
        } catch (e: Exception) {
            Log.e(TAG, "응답 처리 오류: ${e.message}", e)
            return "[]"
        }
    }

    // API 호출 결과를 Flutter에 반환할 수 있는 형태(JSON 문자열)로 변환
    fun convertToJson(data: Any?): String {
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
                put("direction", station.direction ?: "")
            }
            jsonArray.put(jsonObj)
        }
        return jsonArray.toString()
    }

    // 한글 깨짐 여부 확인 함수
    private fun containsBrokenKorean(text: String): Boolean {
        val koreanPattern = Regex("[\\uAC00-\\uD7A3]+")
        val matches = koreanPattern.findAll(text)
        return matches.count() == 0 && text.contains("�")
    }

    suspend fun getCurrentBusInfo(stationId: String, routeId: String): BusInfo? = withContext(Dispatchers.IO) {
        try {
            val response = busInfoApi.getBusArrivalInfo(stationId)
            if (response.header.success && response.body.list != null) {
                val routeInfo = response.body.list.find { it.routeNo == routeId }
                if (routeInfo != null && routeInfo.arrList != null && routeInfo.arrList.isNotEmpty()) {
                    val arrivalInfo = routeInfo.arrList[0]
                    BusInfo(
                        busNumber = arrivalInfo.vhcNo2,
                        currentStation = arrivalInfo.bsNm ?: "정보 없음",
                        remainingStops = arrivalInfo.bsGap.toString(),
                        estimatedTime = arrivalInfo.arrState ?: arrivalInfo.bsGap.toString(),
                        isLowFloor = arrivalInfo.busTCd2 == "1",
                        isOutOfService = arrivalInfo.busTCd3 == "1"
                    )
                } else null
            } else null
        } catch (e: Exception) {
            Log.e(TAG, "버스 정보 조회 중 오류: ${e.message}", e)
            null
        }
    }

    suspend fun getBusArrivals(stationId: String, routeId: String): List<BusInfo> = withContext(Dispatchers.IO) {
        try {
            val response = busInfoApi.getBusArrivalInfo(stationId)
            if (response.header.success && response.body.list != null) {
                val routeInfo = response.body.list.find { it.routeNo == routeId }
                if (routeInfo != null && routeInfo.arrList != null) {
                    routeInfo.arrList.map { arrivalInfo ->
                        BusInfo(
                            busNumber = arrivalInfo.vhcNo2,
                            currentStation = arrivalInfo.bsNm ?: "정보 없음",
                            remainingStops = arrivalInfo.bsGap.toString(),
                            estimatedTime = arrivalInfo.arrState ?: arrivalInfo.bsGap.toString(),
                            isLowFloor = arrivalInfo.busTCd2 == "1",
                            isOutOfService = arrivalInfo.busTCd3 == "1"
                        )
                    }
                } else emptyList()
            } else emptyList()
        } catch (e: Exception) {
            Log.e(TAG, "버스 도착 정보 조회 중 오류: ${e.message}", e)
            emptyList()
        }
    }
}
