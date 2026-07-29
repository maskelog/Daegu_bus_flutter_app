package com.devground.daegubus.utils

object StationIdPolicy {
    private val daeguStationId = Regex("^7\\d{9}$")

    fun isValid(stationId: String?): Boolean =
        stationId != null && daeguStationId.matches(stationId)
}
