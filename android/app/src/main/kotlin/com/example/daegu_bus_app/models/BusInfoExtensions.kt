package com.example.daegu_bus_app.models

/**
 * 버스 정보에서 남은 분을 추출하는 확장 함수
 */
fun BusInfo.getRemainingMinutes(): Int {
    return when {
        estimatedTime == "곧 도착" -> 0
        estimatedTime == "운행종료" -> -1
        estimatedTime.contains("분") -> {
            val numericPart = estimatedTime.filter { it.isDigit() }
            if (numericPart.isNotEmpty()) numericPart.toInt() else Int.MAX_VALUE
        }
        else -> Int.MAX_VALUE
    }
}

/**
 * 버스가 운행 종료 상태인지 확인하는 확장 속성
 */
val BusInfo.isOutOfService: Boolean
    get() = estimatedTime == "운행종료"
    
/**
 * 버스 정보를 로깅하기 위한 확장 함수
 */
fun BusInfo.toLogString(): String {
    return "BusInfo(busNumber='$busNumber', currentStation='$currentStation', estimatedTime='$estimatedTime', remainingMinutes=${getRemainingMinutes()}, isLowFloor=$isLowFloor, isOutOfService=$isOutOfService)"
}
