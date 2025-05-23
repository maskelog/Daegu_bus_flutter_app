package com.example.daegu_bus_app.models

data class LocalStationSearchResult(
    val bsId: String,
    val bsNm: String,
    val latitude: Double = 0.0,
    val longitude: Double = 0.0,
    val stationId: String? = null,
    val distance: Double = 0.0
)

data class WebStationSearchResult(
    val bsId: String,
    val bsNm: String
)