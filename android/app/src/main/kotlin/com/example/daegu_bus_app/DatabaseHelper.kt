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
    suspend fun searchStations(searchText: String, latitude: Double = 0.0, longitude: Double = 0.0, radiusInMeters: Double = 0.0): List<LocalStationSearchResult> {
        val db = readableDatabase
        val stations = mutableListOf<LocalStationSearchResult>()
        val query: String
        val args: Array<String>?

        // BusApiService 인스턴스 생성
        val busApiService = BusApiService(context)

        try {
            // 좌표 및 반경이 제공된 경우 모든 정류장 가져와서 메모리에서 필터링
            if (latitude != 0.0 && longitude != 0.0 && radiusInMeters > 0) {
                // 간단한 쿼리로 먼저 정류장 데이터를 가져옴
                if (searchText.isEmpty() || searchText == "*" || searchText.equals("all", ignoreCase = true)) {
                    query = "SELECT bsId, stop_name, latitude, longitude FROM bus_stops"
                    args = null
                } else {
                    query = "SELECT bsId, stop_name, latitude, longitude FROM bus_stops WHERE stop_name LIKE ? OR bsId LIKE ?"
                    args = arrayOf("%$searchText%", "%$searchText%")
                }
                
                Log.d(TAG, "실행 쿼리: $query")
                Log.d(TAG, "좌표 검색 파라미터: lat=$latitude, lon=$longitude, radius=$radiusInMeters")
                
                val cursor = db.rawQuery(query, args)
                if (cursor.moveToFirst()) {
                    do {
                        val bsId = cursor.getString(cursor.getColumnIndexOrThrow("bsId"))
                        val stopName = cursor.getString(cursor.getColumnIndexOrThrow("stop_name"))
                        val lat = cursor.getDouble(cursor.getColumnIndexOrThrow("latitude"))
                        val lon = cursor.getDouble(cursor.getColumnIndexOrThrow("longitude"))
                        
                        // 코드에서 직접 거리 계산
                        val distance = calculateHaversineDistance(latitude, longitude, lat, lon)
                        
                        // 지정된 반경 내에 있는지 확인
                        if (distance <= radiusInMeters) {
                            // 결과 객체 생성 및 리스트에 추가
                            val result = LocalStationSearchResult(
                                bsId = bsId,
                                bsNm = stopName,
                                latitude = lat,
                                longitude = lon,
                                stationId = bsId, // 임시로 bsId를 stationId로 사용
                                distance = distance
                            )
                            stations.add(result)
                            
                            Log.d(TAG, "정류장: $stopName, bsId: $bsId, 거리: ${distance}m")
                        }
                    } while (cursor.moveToNext())
                }
                cursor.close()
                
                // 거리에 따라 정렬하고 상위 30개만 유지
                val sortedStations = stations.sortedBy { it.distance }.take(30)
                stations.clear()
                stations.addAll(sortedStations)
            } else {
                // 기존 검색 로직 (좌표가 없는 경우)
                if (searchText.isEmpty() || searchText == "*" || searchText.equals("all", ignoreCase = true)) {
                    query = "SELECT bsId, stop_name, latitude, longitude FROM bus_stops LIMIT 100"
                    args = null
                } else {
                    query = "SELECT bsId, stop_name, latitude, longitude FROM bus_stops WHERE stop_name LIKE ? OR bsId LIKE ?"
                    args = arrayOf("%$searchText%", "%$searchText%")
                }
                
                Log.d(TAG, "실행 쿼리: $query")
                
                val cursor = db.rawQuery(query, args)
                if (cursor.moveToFirst()) {
                    do {
                        val bsId = cursor.getString(cursor.getColumnIndexOrThrow("bsId"))
                        val stopName = cursor.getString(cursor.getColumnIndexOrThrow("stop_name"))
                        val lat = cursor.getDouble(cursor.getColumnIndexOrThrow("latitude"))
                        val lon = cursor.getDouble(cursor.getColumnIndexOrThrow("longitude"))
                        
                        // 결과 객체 생성 및 리스트에 추가
                        val result = LocalStationSearchResult(
                            bsId = bsId,
                            bsNm = stopName,
                            latitude = lat,
                            longitude = lon,
                            stationId = bsId // 임시로 bsId를 stationId로 사용
                        )
                        stations.add(result)
                        
                        Log.d(TAG, "정류장: $stopName, bsId: $bsId")
                    } while (cursor.moveToNext())
                }
                cursor.close()
            }
            
            Log.d(TAG, "정류장 검색 결과: ${stations.size}개")
        } catch (e: Exception) {
            Log.e(TAG, "정류장 검색 오류: ${e.message}", e)
        } finally {
            db.close()
        }
        
        return stations
    }

    // Haversine 공식을 사용한 두 지점 간의 거리 계산 (미터 단위)
    private fun calculateHaversineDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val R = 6371000.0 // 지구 반지름(미터)
        val dLat = Math.toRadians(lat2 - lat1)
        val dLon = Math.toRadians(lon2 - lon1)
        val a = Math.sin(dLat / 2) * Math.sin(dLat / 2) +
                Math.cos(Math.toRadians(lat1)) * Math.cos(Math.toRadians(lat2)) *
                Math.sin(dLon / 2) * Math.sin(dLon / 2)
        val c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
        return R * c
    }
}