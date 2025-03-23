package com.example.daegu_bus_app

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.FileOutputStream

class DatabaseHelper(private val context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {
    companion object {
        private const val DATABASE_NAME = "bus_stops.db"
        private const val DATABASE_VERSION = 4
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
        // DB 버전 업그레이드 로직 구현
        Log.d(TAG, "데이터베이스 업그레이드: $oldVersion -> $newVersion")
        
        // 기존 DB 삭제 후 재복사
        context.getDatabasePath(DATABASE_NAME).delete()
        copyDatabaseIfNeeded()
    }

    // 데이터베이스 테이블 정보 확인 - 디버깅용
    fun checkDatabaseInfo() {
        val db = readableDatabase
        try {
            // 테이블 목록 확인
            val tablesCursor = db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'", null)
            Log.d(TAG, "데이터베이스 내 테이블 목록:")
            if (tablesCursor.moveToFirst()) {
                do {
                    val tableName = tablesCursor.getString(0)
                    Log.d(TAG, "- $tableName")
                    
                    // bus_stops 테이블의 경우 구조 확인
                    if (tableName == "bus_stops") {
                        val structureCursor = db.rawQuery("PRAGMA table_info(bus_stops)", null)
                        Log.d(TAG, "  bus_stops 테이블 구조:")
                        if (structureCursor.moveToFirst()) {
                            do {
                                val columnName = structureCursor.getString(1)
                                val columnType = structureCursor.getString(2)
                                Log.d(TAG, "  - $columnName ($columnType)")
                            } while (structureCursor.moveToNext())
                        }
                        structureCursor.close()
                        
                        // 행 수 확인
                        val countCursor = db.rawQuery("SELECT COUNT(*) FROM bus_stops", null)
                        if (countCursor.moveToFirst()) {
                            Log.d(TAG, "  총 정류장 수: ${countCursor.getInt(0)}개")
                        }
                        countCursor.close()
                        
                        // 샘플 데이터 확인
                        val sampleCursor = db.rawQuery("SELECT * FROM bus_stops LIMIT 3", null)
                        if (sampleCursor.moveToFirst()) {
                            Log.d(TAG, "  샘플 데이터:")
                            val columnCount = sampleCursor.columnCount
                            do {
                                val bsId = sampleCursor.getString(sampleCursor.getColumnIndex("bsId"))
                                val stopName = sampleCursor.getString(sampleCursor.getColumnIndex("stop_name"))
                                val lat = if (sampleCursor.getColumnIndex("latitude") >= 0) 
                                    sampleCursor.getDouble(sampleCursor.getColumnIndex("latitude")) else 0.0
                                val lon = if (sampleCursor.getColumnIndex("longitude") >= 0) 
                                    sampleCursor.getDouble(sampleCursor.getColumnIndex("longitude")) else 0.0
                                Log.d(TAG, "  - $bsId: $stopName, 좌표: ($lon, $lat)")
                            } while (sampleCursor.moveToNext())
                        }
                        sampleCursor.close()
                    }
                } while (tablesCursor.moveToNext())
            }
            tablesCursor.close()
        } catch (e: Exception) {
            Log.e(TAG, "데이터베이스 정보 확인 오류: ${e.message}", e)
        } finally {
            db.close()
        }
    }

    // 정류장 검색 메서드: 검색어가 비어있거나 "*" 또는 "all"이면 전체 데이터를 반환
    suspend fun searchStations(searchText: String, latitude: Double = 0.0, longitude: Double = 0.0, radiusInMeters: Double = 0.0): List<LocalStationSearchResult> {
        // 디버깅을 위해 데이터베이스 정보 출력
        if (latitude != 0.0 && longitude != 0.0 && radiusInMeters > 0) {
            Log.d(TAG, "데이터베이스 정보 확인 시작...")
            checkDatabaseInfo()
            Log.d(TAG, "데이터베이스 정보 확인 완료")
        }
        
        val db = readableDatabase
        val stations = mutableListOf<LocalStationSearchResult>()
        val query: String
        val args: Array<String>?

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
                Log.d(TAG, "쿼리 결과 행 수: ${cursor.count}개")
                
                if (cursor.moveToFirst()) {
                    // 결과 처리를 위한 컬럼 인덱스 확인
                    val bsIdIndex = cursor.getColumnIndex("bsId")
                    val stopNameIndex = cursor.getColumnIndex("stop_name")
                    val latitudeIndex = cursor.getColumnIndex("latitude")
                    val longitudeIndex = cursor.getColumnIndex("longitude")
                    
                    // 컬럼 인덱스 로깅
                    Log.d(TAG, "컬럼 인덱스: bsId=${bsIdIndex}, stop_name=${stopNameIndex}, " +
                                "latitude=${latitudeIndex}, longitude=${longitudeIndex}")
                    
                    if (bsIdIndex < 0 || stopNameIndex < 0 || latitudeIndex < 0 || longitudeIndex < 0) {
                        Log.e(TAG, "필요한 컬럼이 데이터베이스에 없습니다.")
                        // 컬럼 이름 확인하여 로깅
                        for (i in 0 until cursor.columnCount) {
                            Log.d(TAG, "컬럼 ${i}: ${cursor.getColumnName(i)}")
                        }
                    }
                    
                    // 데이터베이스에서 결과 처리
                    do {
                        try {
                            val bsId = cursor.getString(bsIdIndex)
                            val stopName = cursor.getString(stopNameIndex)
                            val lat = cursor.getDouble(latitudeIndex)
                            val lon = cursor.getDouble(longitudeIndex)
                            
                            // 좌표 로깅
                            Log.d(TAG, "정류장: $stopName (${bsId}), 좌표: ($lon, $lat)")
                            
                            // 좌표가 0이 아닌 경우만 거리 계산
                            if (lat != 0.0 && lon != 0.0) {
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
                                    
                                    Log.d(TAG, "정류장 추가: $stopName, bsId: $bsId, 거리: ${distance}m")
                                }
                            } else {
                                Log.d(TAG, "정류장 좌표가 0입니다: $stopName (${bsId})")
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "행 처리 중 오류 발생: ${e.message}", e)
                        }
                    } while (cursor.moveToNext())
                } else {
                    Log.d(TAG, "쿼리 결과가 없습니다: $query")
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

    // DB 강제 재설치 메서드
    fun forceReinstallDatabase() {
        val dbPath = context.getDatabasePath(DATABASE_NAME)
        if (dbPath.exists()) {
            dbPath.delete()
            Log.d(TAG, "기존 DB 파일 삭제됨")
        }
        copyDatabaseIfNeeded()
        Log.d(TAG, "DB 파일 재설치 완료")
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