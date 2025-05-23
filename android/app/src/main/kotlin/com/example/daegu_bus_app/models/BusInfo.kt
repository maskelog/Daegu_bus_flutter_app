package com.example.daegu_bus_app.models

data class BusInfo(
    val currentStation: String,
    val estimatedTime: String,
    val remainingStops: String = "0",
    val busNumber: String = "",
    val isLowFloor: Boolean = false,
    val isOutOfService: Boolean = false
) {
    companion object {
        const val ARRIVAL_THRESHOLD_MINUTES = 3
        private val ARRIVING_KEYWORDS = setOf("곧 도착", "전", "도착", "곧", "전전", "전전전")
        private val OUT_OF_SERVICE_KEYWORDS = setOf("운행종료", "-", "종료")
        private val SCHEDULED_KEYWORDS = setOf("출발예정", "기점출발", "출발")
        private val INVALID_KEYWORDS = setOf("정보 없음", "null", "")

        // 안전한 BusInfo 생성 팩토리
        fun createSafe(
            currentStation: String?,
            estimatedTime: String?,
            remainingStops: String? = "0",
            busNumber: String? = "",
            isLowFloor: Boolean = false,
            isOutOfService: Boolean = false
        ): BusInfo {
            return BusInfo(
                currentStation = currentStation?.takeIf { it.isNotEmpty() && it != "null" } ?: "정보 없음",
                estimatedTime = estimatedTime?.takeIf { it.isNotEmpty() && it != "null" } ?: "정보 없음",
                remainingStops = remainingStops?.takeIf { it.isNotEmpty() && it != "null" } ?: "0",
                busNumber = busNumber?.takeIf { it.isNotEmpty() && it != "null" } ?: "",
                isLowFloor = isLowFloor,
                isOutOfService = isOutOfService
            )
        }
    }

    // 안전한 시간 파싱 메서드
    fun getRemainingMinutes(): Int {
        return try {
            val timeStr = estimatedTime.trim()
            
            // 빈 문자열이나 null 체크
            if (timeStr.isEmpty() || timeStr == "null") {
                return -1
            }
            
            // 곧 도착 관련
            if (timeStr == "곧 도착" || timeStr == "전" || timeStr == "도착" || timeStr == "곧") {
                return 0
            }
            
            // 운행 종료 관련
            if (timeStr == "운행종료" || timeStr == "-" || timeStr.contains("종료")) {
                return -1
            }
            
            // 출발 예정 관련
            if (timeStr.contains("출발예정") || timeStr.contains("기점출발") || timeStr.contains("출발")) {
                return -1
            }
            
            // "분" 제거 후 숫자 추출
            val cleanTimeStr = timeStr.replace("분", "").replace("약", "").trim()
            
            // 숫자만 추출
            val numericValue = cleanTimeStr.replace("[^0-9]".toRegex(), "")
            
            if (numericValue.isNotEmpty()) {
                val minutes = numericValue.toIntOrNull()
                if (minutes != null && minutes >= 0 && minutes <= 180) { // 3시간 이내만 유효
                    return minutes
                }
            }
            
            // 파싱할 수 없는 경우
            android.util.Log.w("BusInfo", "⚠️ 파싱할 수 없는 시간 형식: '$timeStr'")
            return -1
            
        } catch (e: Exception) {
            android.util.Log.e("BusInfo", "❌ getRemainingMinutes 오류: ${e.message}")
            return -1
        }
    }

    // 안전한 포맷된 시간 표시 메서드
    fun getFormattedTime(): String {
        return try {
            val minutes = getRemainingMinutes()
            when {
                minutes < 0 -> {
                    // 원본 텍스트 그대로 반환 (운행종료, 출발예정 등)
                    if (estimatedTime.isNotEmpty() && estimatedTime != "null") {
                        estimatedTime
                    } else {
                        "정보 없음"
                    }
                }
                minutes == 0 -> "곧 도착"
                minutes == 1 -> "1분"
                minutes < 60 -> "${minutes}분"
                else -> {
                    // 1시간 이상인 경우 시간:분 형태로 표시
                    val hours = minutes / 60
                    val remainingMins = minutes % 60
                    "${hours}시간 ${remainingMins}분"
                }
            }
        } catch (e: Exception) {
            android.util.Log.e("BusInfo", "❌ getFormattedTime 오류: ${e.message}")
            "정보 없음"
        }
    }

    // 도착 임박 여부 확인 메서드
    fun isArriving(): Boolean {
        return try {
            val minutes = getRemainingMinutes()
            minutes >= 0 && minutes <= ARRIVAL_THRESHOLD_MINUTES
        } catch (e: Exception) {
            false
        }
    }

    // 유효한 버스 정보인지 확인 메서드
    fun isValid(): Boolean {
        return try {
            !estimatedTime.isNullOrEmpty() && 
            estimatedTime != "null" && 
            !currentStation.isNullOrEmpty() && 
            currentStation != "null" &&
            !isOutOfService
        } catch (e: Exception) {
            false
        }
    }

    // 디버깅용 문자열 표현
    override fun toString(): String {
        return try {
            "BusInfo(bus=$busNumber, time=$estimatedTime(${getRemainingMinutes()}분), station=$currentStation, stops=$remainingStops, lowFloor=$isLowFloor, outOfService=$isOutOfService)"
        } catch (e: Exception) {
            "BusInfo(parsing_error: ${e.message})"
        }
    }
} 