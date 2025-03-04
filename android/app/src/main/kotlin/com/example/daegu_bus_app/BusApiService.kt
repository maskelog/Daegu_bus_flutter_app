package com.example.daegu_bus_app

import android.content.Context
import android.util.Log
import com.google.gson.Gson
import com.google.gson.GsonBuilder
import com.google.gson.JsonSyntaxException
import com.google.gson.annotations.SerializedName
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.ResponseBody
import org.json.JSONObject
import org.jsoup.Jsoup
import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query
import retrofit2.http.Url
import java.net.URLEncoder
import java.nio.charset.Charset
import java.util.concurrent.TimeUnit

// API 인터페이스 정의
interface BusInfoApi {
    @GET
    suspend fun getStationSearchResult(@Url url: String): ResponseBody
    
    @GET("realtime/arr2/{stationId}")
    suspend fun getBusArrivalInfo(@Path("stationId") stationId: String): BusArrivalResponse
    
    @GET("bs/route")
    suspend fun getBusRouteInfo(@Query("routeId") routeId: String): ResponseBody
    
    @GET("realtime/pos/{routeId}")
    suspend fun getBusPositionInfo(@Path("routeId") routeId: String): ResponseBody
}

// 정류장 검색 결과 데이터 클래스
data class StationSearchResult(
    val bsId: String,
    val bsNm: String
)

// 버스 도착 정보 응답 모델
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
                val moveDir: String,
                val bsGap: Int,
                val bsNm: String,
                val vhcNo2: String,
                val busTCd2: String,
                val busTCd3: String,
                val busAreaCd: String,
                val arrState: String,
                val prevBsGap: Int
            )
        }
    }
}

// 클라이언트 응답용 도착 정보 모델
data class StationArrivalOutput(
    val name: String,
    val sub: String,
    val id: String,
    val forward: String,
    val bus: List<BusInfo>
) {
    data class BusInfo(
        @SerializedName("버스번호")
        val busNumber: String,
        @SerializedName("현재정류소")
        val currentStation: String,
        @SerializedName("남은정류소")
        val remainingStations: String,
        @SerializedName("도착예정소요시간")
        val estimatedTime: String
    )
}

// BusApiService 클래스
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
                    val key = "${routeNo}_${arrival.moveDir}"
                    
                    if (!groups.containsKey(key)) {
                        groups[key] = StationArrivalOutput(
                            name = routeNo,
                            sub = "default",
                            id = arrival.routeId,
                            forward = arrival.moveDir,
                            bus = mutableListOf()
                        )
                    }
                    
                    val busType = if (arrival.busTCd2 == "N") "저상" else "일반"
                    val arrivalTime = if (arrival.arrState == "운행종료") "-" else arrival.arrState
                    
                    (groups[key]!!.bus as MutableList).add(
                        StationArrivalOutput.BusInfo(
                            busNumber = "${arrival.vhcNo2}(${busType})",
                            currentStation = arrival.bsNm,
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
    
    // 버스 도착 정보 조회 by 노선 ID
    suspend fun getBusArrivalInfoByRouteId(stationId: String, routeId: String): StationArrivalOutput? = withContext(Dispatchers.IO) {
        try {
            val allArrivals = getBusArrivalInfo(stationId)
            return@withContext allArrivals.find { it.id == routeId }
        } catch (e: Exception) {
            Log.e(TAG, "노선별 버스 도착 정보 조회 오류: ${e.message}", e)
            return@withContext null
        }
    }
    
    // 버스 노선 정보 조회
    suspend fun getBusRouteInfo(routeId: String): String = withContext(Dispatchers.IO) {
        try {
            val response = busInfoApi.getBusRouteInfo(routeId)
            return@withContext String(response.bytes())
        } catch (e: Exception) {
            Log.e(TAG, "버스 노선 정보 조회 오류: ${e.message}", e)
            return@withContext "{\"error\": \"${e.message}\"}"
        }
    }
    
    // 실시간 버스 위치 정보 조회
    suspend fun getBusPositionInfo(routeId: String): String = withContext(Dispatchers.IO) {
        try {
            val response = busInfoApi.getBusPositionInfo(routeId)
            return@withContext String(response.bytes())
        } catch (e: Exception) {
            Log.e(TAG, "실시간 버스 위치 정보 조회 오류: ${e.message}", e)
            return@withContext "{\"error\": \"${e.message}\"}"
        }
    }
    
    // API 호출 결과를 Flutter에 반환할 수 있는 형태로 변환
    fun convertToJson(data: Any): String {
        return gson.toJson(data)
    }
}