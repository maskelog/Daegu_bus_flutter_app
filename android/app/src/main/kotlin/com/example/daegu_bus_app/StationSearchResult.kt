package com.example.daegu_bus_app

data class WebStationSearchResult(
    val bsId: String,
    val bsNm: String
)

data class LocalStationSearchResult(
    val bsId: String,         // 정류장 고유 ID
    val bsNm: String,         // 정류장 이름
    val latitude: Double,     // 위도
    val longitude: Double,    // 경도
    var stationId: String? = null, // API 호출에 사용되는 정류장 ID
    val routeList: String? = null // 정류장에 관한 경로 정보
)
