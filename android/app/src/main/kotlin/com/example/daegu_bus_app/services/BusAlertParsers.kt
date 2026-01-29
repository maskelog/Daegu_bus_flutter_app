package com.example.daegu_bus_app.services

import android.util.Log
import com.example.daegu_bus_app.models.BusInfo
import org.json.JSONArray

fun parseJsonBusArrivals(jsonString: String, inputRouteId: String): List<BusInfo> {
    return try {
        val jsonArray = JSONArray(jsonString)
        val busInfoList = mutableListOf<BusInfo>()
        for (i in 0 until jsonArray.length()) {
            val routeObj = jsonArray.getJSONObject(i)
            val arrList = routeObj.optJSONArray("arrList") ?: continue
            for (j in 0 until arrList.length()) {
                val busObj = arrList.getJSONObject(j)
                if (busObj.optString("routeId", "") != inputRouteId) continue

                val arrState = busObj.optString("arrState", "")
                val currentStation = busObj.optString("bsNm", null) ?: "정보 없음"

                // 운행종료 판단 로직 개선
                val isOutOfService = arrState.contains("운행종료") || arrState == "-"

                Log.d(
                    "BusAlertService",
                    "🔍 [BusAlertService] 버스 정보 파싱: routeId=$inputRouteId, arrState='$arrState', currentStation='$currentStation', isOutOfService=$isOutOfService"
                )

                busInfoList.add(
                    BusInfo(
                        currentStation = currentStation,
                        estimatedTime = arrState,
                        remainingStops = busObj.optString("bsGap", null) ?: "0",
                        busNumber = busObj.optString("routeNo", null) ?: "",
                        isLowFloor = busObj.optString("busTCd2", "N") == "1",
                        isOutOfService = isOutOfService
                    )
                )
            }
        }
        busInfoList
    } catch (e: Exception) {
        Log.e("BusAlertService", "❌ 버스 도착 정보 파싱 오류: ${e.message}", e)
        emptyList()
    }
}
