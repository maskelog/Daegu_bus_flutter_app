data class BusInfo(
    val currentStation: String,
    val estimatedTime: String,
    val remainingStops: String = "0",
    val busNumber: String = "",
    val isLowFloor: Boolean = false,
    val isOutOfService: Boolean = false
) {
    fun getRemainingMinutes(): Int {
        return try {
            val timeStr = estimatedTime.replace("분", "").trim()
            if (timeStr == "곧" || timeStr == "도착") return 0
            timeStr.toIntOrNull() ?: Int.MAX_VALUE
        } catch (e: Exception) {
            Int.MAX_VALUE
        }
    }

    fun getFormattedTime(): String {
        val minutes = getRemainingMinutes()
        return when {
            minutes <= 0 -> "곧 도착"
            minutes == Int.MAX_VALUE -> "정보 없음"
            else -> "${minutes}분"
        }
    }

    companion object {
        const val ARRIVAL_THRESHOLD_MINUTES = 3
    }
} 