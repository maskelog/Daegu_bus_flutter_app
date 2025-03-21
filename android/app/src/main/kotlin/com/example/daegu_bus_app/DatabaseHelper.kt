package com.example.daegu_bus_app

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import java.io.FileOutputStream

class DatabaseHelper(private val context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {
    companion object {
        private const val DATABASE_NAME = "bus_stops.db"
        private const val DATABASE_VERSION = 3
        private const val TAG = "DatabaseHelper"
    }

    init {
        copyDatabaseIfNeeded()
    }

    // assets에 있는 pre-populated DB 파일을 기기의 DB 경로로 복사하는 메서드
    private fun copyDatabaseIfNeeded() {
        val dbPath = context.getDatabasePath(DATABASE_NAME)
        if (!dbPath.exists()) {
            dbPath.parentFile?.mkdirs()
            try {
                context.assets.open(DATABASE_NAME).use { inputStream ->
                    FileOutputStream(dbPath).use { outputStream ->
                        val buffer = ByteArray(1024)
                        var length: Int
                        while (inputStream.read(buffer).also { length = it } > 0) {
                            outputStream.write(buffer, 0, length)
                        }
                        outputStream.flush()
                    }
                }
                Log.d(TAG, "DB 파일 복사 완료")
            } catch (e: Exception) {
                Log.e(TAG, "DB 파일 복사 오류: ${e.message}", e)
            }
        } else {
            Log.d(TAG, "DB 파일이 이미 존재함")
        }
    }

    override fun onCreate(db: SQLiteDatabase) {
        // assets에서 복사한 DB 파일을 사용하는 경우 onCreate()에서 테이블 생성이나 초기 데이터 삽입이 필요 없습니다.
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        // DB 버전 업그레이드 로직 구현 (필요 시)
    }

    // 정류장 검색 메서드: 검색어가 비어있거나 "*" 또는 "all"이면 전체 데이터를 반환
    suspend fun searchStations(searchText: String): List<LocalStationSearchResult> {
        val db = readableDatabase
        val stations = mutableListOf<LocalStationSearchResult>()
        val query: String
        val args: Array<String>?

        // BusApiService 인스턴스 생성
        val busApiService = BusApiService(context)

        if (searchText.isEmpty() || searchText == "*" || searchText.equals("all", ignoreCase = true)) {
            query = "SELECT bsId, stop_name, latitude, longitude FROM bus_stops"
            args = null
        } else {
            query = "SELECT bsId, stop_name, latitude, longitude FROM bus_stops WHERE stop_name LIKE ?"
            args = arrayOf("%$searchText%")
        }

        val cursor = db.rawQuery(query, args)
        try {
            if (cursor.moveToFirst()) {
                do {
                    val bsId = cursor.getString(cursor.getColumnIndexOrThrow("bsId"))
                    val stopName = cursor.getString(cursor.getColumnIndexOrThrow("stop_name"))
                    val latitude = cursor.getDouble(cursor.getColumnIndexOrThrow("latitude"))
                    val longitude = cursor.getDouble(cursor.getColumnIndexOrThrow("longitude"))

                    // bsId를 통해 stationId와 routeList 조회
                    val stationInfo = busApiService.getStationInfoFromBsId(bsId) ?: continue
                    val stationId = stationInfo["bsId"]?.toString() ?: continue
                    val routeList = stationInfo["routeList"]?.toString()

                    // 결과 객체 생성 및 리스트에 추가
                    val result = LocalStationSearchResult(
                        bsId = bsId,
                        bsNm = stopName,
                        latitude = latitude,
                        longitude = longitude,
                        stationId = stationId,
                        routeList = routeList // routeList 추가
                    )
                    stations.add(result)

                    Log.d(TAG, "정류장: $stopName, bsId: $bsId, stationId: $stationId, routeList: $routeList")
                } while (cursor.moveToNext())
            }
            Log.d(TAG, "정류장 검색 결과: ${stations.size}개")
        } catch (e: Exception) {
            Log.e(TAG, "정류장 검색 오류: ${e.message}", e)
        } finally {
            cursor.close()
            db.close()
        }
        return stations
    }
}