package com.example.daegu_bus_app.services

import com.example.daegu_bus_app.models.BusInfo

data class TrackingInfo(
    val routeId: String,
    var stationName: String,
    var busNo: String,
    var lastBusInfo: BusInfo? = null,
    var consecutiveErrors: Int = 0,
    var lastUpdateTime: Long = System.currentTimeMillis(),
    var lastNotifiedMinutes: Int = Int.MAX_VALUE,
    var stationId: String = "",
    // [추가] TTS 중복 방지용
    var lastTtsAnnouncedMinutes: Int? = null,
    var lastTtsAnnouncedStation: String? = null,
    // [추가] 자동알람 플래그 - 자동알람인 경우 버스가 지나가도 계속 추적
    var isAutoAlarm: Boolean = false,
    var alarmId: Int? = null,
    // [추가] 버스 타입 정보 (1: 급행, 2: 좌석, 3: 일반, 4: 지선/마을)
    var routeTCd: String? = null
)
