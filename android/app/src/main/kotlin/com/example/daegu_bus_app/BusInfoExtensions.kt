package com.example.daegu_bus_app

/**
 * BusInfo 클래스의 확장 함수를 정의하는 파일
 */

/**
 * 버스 도착 예정 시간을 분 단위로 계산하는 확장 함수
 */
fun BusInfo.getRemainingMinutes(): Int {
    return when {
        estimatedTime == "곧 도착" -> 0
        estimatedTime == "운행종료" -> -1
        estimatedTime.contains("분") -> estimatedTime.filter { it.isDigit() }.toIntOrNull() ?: Int.MAX_VALUE
        else -> Int.MAX_VALUE
    }
}

/**
 * 버스가 운행 종료 상태인지 확인하는 확장 속성
 */
val BusInfo.isOutOfService: Boolean
    get() = estimatedTime == "운행종료"
