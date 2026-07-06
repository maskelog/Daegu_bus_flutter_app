package com.devground.daegubus.utils

import android.content.Context
import android.util.Log
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale

/**
 * 자동알람 발화 시점의 공휴일 게이트.
 *
 * 다음 알람 시각은 스케줄 등록 시점에 계산되므로, 등록 이후에 지정된
 * 임시공휴일은 스케줄에 반영되지 못한다. 발화 직전/직후에 한 번 더
 * 확인해서 공휴일이면 추적을 시작하지 않는다.
 */
object HolidayGate {
    private const val TAG = "HolidayGate"
    private const val CDN_BASE =
        "https://cdn.jsdelivr.net/gh/hyunbinseo/open-data@main/data/holidays"

    // Flutter HolidayService와 동일한 비공휴일 이름 필터 (제헌절·노동절 계열)
    private val NON_PUBLIC_NAMES = listOf("제헌절", "노동절", "근로자의 날")

    private fun todayString(): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).format(Date())

    /**
     * 1단계: 앱이 내려둔 excluded_dates 기준 (동기, prefs 읽기만 — Receiver에서 사용 가능).
     * 커스텀 예외 날짜도 이 목록에 포함되어 있다.
     */
    fun isTodayInStoredExcludedDates(context: Context): Boolean =
        AutoAlarmScheduleCalculator.loadExcludedDates(context).contains(todayString())

    /**
     * 2단계: CDN 신선 조회로 오늘이 공휴일인지 확인 (3초 타임아웃, 반드시 백그라운드 스레드).
     * 앱이 오래 실행되지 않아 저장 목록이 낡았어도 새 임시공휴일을 잡는다.
     *
     * @return true=공휴일, false=아님, null=조회 실패(판단 불가 — 알람을 막지 않는다)
     */
    fun isTodayHolidayFresh(): Boolean? {
        return try {
            val year = Calendar.getInstance().get(Calendar.YEAR)
            val conn = URL("$CDN_BASE/$year.json").openConnection() as HttpURLConnection
            conn.connectTimeout = 3000
            conn.readTimeout = 3000
            val body = try {
                conn.inputStream.bufferedReader().use { it.readText() }
            } finally {
                conn.disconnect()
            }
            val holidays = JSONObject(body)
            val today = todayString()
            if (!holidays.has(today)) return false

            val names = holidays.optJSONArray(today) ?: return true
            // 유효한 공휴일 이름이 하나라도 있으면 공휴일로 판정
            (0 until names.length()).any { i ->
                NON_PUBLIC_NAMES.none { blocked -> names.getString(i).contains(blocked) }
            }
        } catch (e: Exception) {
            Log.w(TAG, "공휴일 신선 조회 실패(알람 진행): ${e.message}")
            null
        }
    }
}
