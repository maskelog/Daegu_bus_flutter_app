package com.example.daegu_bus_app

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteException
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

class DatabaseHelper private constructor(private val context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {
    companion object {
        private const val TAG = "DatabaseHelper"
        private const val DATABASE_NAME = "bus_stops.db"
        private const val DATABASE_VERSION = 4 // 현재 버전을 4로 설정 (기존 버전과 맞춤)

        private var instance: DatabaseHelper? = null

        @Synchronized
        fun getInstance(context: Context): DatabaseHelper {
            return instance ?: DatabaseHelper(context.applicationContext).also { instance = it }
        }
    }

    init {
        initializeDatabase(context)
    }

    // 데이터베이스 초기화 및 무결성 확인
    private fun initializeDatabase(context: Context) {
        val dbPath = context.getDatabasePath(DATABASE_NAME)
        Log.d(TAG, "데이터베이스 경로: ${dbPath.absolutePath}")
    
        // 상위 디렉토리 생성 확인
        if (!dbPath.parentFile?.exists()!!) {
            dbPath.parentFile?.mkdirs()
        }
    
        if (!dbPath.exists()) {
            copyDatabaseFromAssets(context, dbPath)
        } else if (!isDatabaseValid(dbPath)) {
            // 기존 DB가 유효하지 않은 경우, 삭제 후 재복사
            Log.w(TAG, "기존 데이터베이스가 유효하지 않아 재생성합니다")
            dbPath.delete()
            copyDatabaseFromAssets(context, dbPath)
        }
    
        // 데이터베이스 확인
        try {
            val db = SQLiteDatabase.openDatabase(dbPath.absolutePath, null, SQLiteDatabase.OPEN_READONLY)
            val count = db.rawQuery("SELECT COUNT(*) FROM bus_stops", null).use { cursor ->
                cursor.moveToFirst()
                cursor.getInt(0)
            }
            Log.d(TAG, "데이터베이스 초기화 성공: ${count}개의 정류장 정보 확인")
            db.close()
        } catch (e: Exception) {
            Log.e(TAG, "데이터베이스 확인 실패: ${e.message}", e)
            // 실패시 복구 시도
            dbPath.delete()
            copyDatabaseFromAssets(context, dbPath)
        }
    }

    // assets에서 데이터베이스 파일 복사
    private fun copyDatabaseFromAssets(context: Context, dbPath: File) {
        Log.d(TAG, "데이터베이스 복사 시작")
        dbPath.parentFile?.mkdirs()
        try {
            context.assets.open(DATABASE_NAME).use { inputStream ->
                FileOutputStream(dbPath).use { outputStream ->
                    val buffer = ByteArray(1024)
                    var length: Int
                    var totalBytes = 0
                    while (inputStream.read(buffer).also { length = it } > 0) {
                        outputStream.write(buffer, 0, length)
                        totalBytes += length
                    }
                    outputStream.flush()
                    Log.d(TAG, "데이터베이스 복사 완료. 크기: $totalBytes bytes")
                }
            }
            if (!dbPath.exists() || dbPath.length() == 0L) {
                Log.e(TAG, "데이터베이스 복사 실패: 파일이 생성되지 않음")
                throw IOException("Failed to copy database from assets")
            }
        } catch (e: IOException) {
            Log.e(TAG, "데이터베이스 복사 오류: ${e.message}", e)
            throw RuntimeException("Failed to copy database: $DATABASE_NAME", e)
        }
    }

    // 데이터베이스 무결성 확인
    private fun isDatabaseValid(dbPath: File): Boolean {
        return try {
            SQLiteDatabase.openDatabase(dbPath.path, null, SQLiteDatabase.OPEN_READONLY).use { db ->
                db.isOpen
            }
        } catch (e: Exception) {
            Log.w(TAG, "데이터베이스 유효성 검사 실패: ${e.message}")
            false
        }
    }

    override fun onCreate(db: SQLiteDatabase) {
        // pre-populated 데이터베이스를 사용하므로 테이블 생성 불필요
        Log.d(TAG, "onCreate 호출됨 - pre-populated DB 사용")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        Log.d(TAG, "데이터베이스 업그레이드: $oldVersion -> $newVersion")
        val dbPath = context.getDatabasePath(DATABASE_NAME)
        if (dbPath.exists()) {
            dbPath.delete()
            Log.d(TAG, "기존 데이터베이스 삭제됨")
        }
        copyDatabaseFromAssets(context, dbPath)
    }

    override fun onDowngrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        Log.w(TAG, "데이터베이스 다운그레이드 요청: $oldVersion -> $newVersion")
        // 다운그레이드 대신 데이터베이스 재설치
        val dbPath = context.getDatabasePath(DATABASE_NAME)
        if (dbPath.exists()) {
            dbPath.delete()
            Log.d(TAG, "기존 데이터베이스 삭제됨 (다운그레이드 처리)")
        }
        copyDatabaseFromAssets(context, dbPath)
    }

    // 데이터베이스 정보 확인 (디버깅용)
    fun checkDatabaseInfo() {
        val db = readableDatabase
        try {
            val tablesCursor = db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'", null)
            Log.d(TAG, "데이터베이스 내 테이블 목록:")
            tablesCursor.use {
                if (it.moveToFirst()) {
                    do {
                        val tableName = it.getString(0)
                        Log.d(TAG, "- $tableName")
                        if (tableName == "bus_stops") {
                            val structureCursor = db.rawQuery("PRAGMA table_info(bus_stops)", null)
                            Log.d(TAG, "  bus_stops 테이블 구조:")
                            structureCursor.use { cursor ->
                                if (cursor.moveToFirst()) {
                                    do {
                                        val columnName = cursor.getString(1)
                                        val columnType = cursor.getString(2)
                                        Log.d(TAG, "  - $columnName ($columnType)")
                                    } while (cursor.moveToNext())
                                }
                            }
                            val countCursor = db.rawQuery("SELECT COUNT(*) FROM bus_stops", null)
                            countCursor.use { cursor ->
                                if (cursor.moveToFirst()) {
                                    Log.d(TAG, "  총 정류장 수: ${cursor.getInt(0)}개")
                                }
                            }
                            val sampleCursor = db.rawQuery("SELECT * FROM bus_stops LIMIT 3", null)
                            Log.d(TAG, "  샘플 데이터:")
                            sampleCursor.use { cursor ->
                                if (cursor.moveToFirst()) {
                                    do {
                                        val bsId = cursor.getString(cursor.getColumnIndexOrThrow("bsId"))
                                        val stopName = cursor.getString(cursor.getColumnIndexOrThrow("stop_name"))
                                        val lat = cursor.getDouble(cursor.getColumnIndexOrThrow("latitude"))
                                        val lon = cursor.getDouble(cursor.getColumnIndexOrThrow("longitude"))
                                        Log.d(TAG, "  - $bsId: $stopName, 좌표: ($lon, $lat)")
                                    } while (cursor.moveToNext())
                                }
                            }
                        }
                    } while (it.moveToNext())
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "데이터베이스 정보 확인 오류: ${e.message}", e)
        } finally {
            db.close()
        }
    }

    // 정류장 검색 메서드
    suspend fun searchStations(
        searchText: String,
        latitude: Double = 0.0,
        longitude: Double = 0.0,
        radiusInMeters: Double = 0.0
    ): List<LocalStationSearchResult> = withContext(Dispatchers.IO) {
        if (latitude != 0.0 && longitude != 0.0 && radiusInMeters > 0) {
            Log.d(TAG, "데이터베이스 정보 확인 시작...")
            checkDatabaseInfo()
            Log.d(TAG, "데이터베이스 정보 확인 완료")
        }

        val db = readableDatabase
        val stations = mutableListOf<LocalStationSearchResult>()
        try {
            val (query, args) = if (latitude != 0.0 && longitude != 0.0 && radiusInMeters > 0) {
                if (searchText.isEmpty() || searchText == "*" || searchText.equals("all", ignoreCase = true)) {
                    "SELECT bsId, stop_name, latitude, longitude FROM bus_stops" to null
                } else {
                    "SELECT bsId, stop_name, latitude, longitude FROM bus_stops WHERE stop_name LIKE ? OR bsId LIKE ?" to
                            arrayOf("%$searchText%", "%$searchText%")
                }
            } else {
                if (searchText.isEmpty() || searchText == "*" || searchText.equals("all", ignoreCase = true)) {
                    "SELECT bsId, stop_name, latitude, longitude FROM bus_stops LIMIT 100" to null
                } else {
                    "SELECT bsId, stop_name, latitude, longitude FROM bus_stops WHERE stop_name LIKE ? OR bsId LIKE ?" to
                            arrayOf("%$searchText%", "%$searchText%")
                }
            }

            Log.d(TAG, "실행 쿼리: $query")
            if (args != null) Log.d(TAG, "쿼리 인자: ${args.joinToString()}")

            db.rawQuery(query, args).use { cursor ->
                Log.d(TAG, "쿼리 결과 행 수: ${cursor.count}개")
                if (cursor.moveToFirst()) {
                    val bsIdIndex = cursor.getColumnIndexOrThrow("bsId")
                    val stopNameIndex = cursor.getColumnIndexOrThrow("stop_name")
                    val latitudeIndex = cursor.getColumnIndexOrThrow("latitude")
                    val longitudeIndex = cursor.getColumnIndexOrThrow("longitude")

                    do {
                        val bsId = cursor.getString(bsIdIndex)
                        val stopName = cursor.getString(stopNameIndex)
                        val lat = cursor.getDouble(latitudeIndex)
                        val lon = cursor.getDouble(longitudeIndex)

                        if (latitude != 0.0 && longitude != 0.0 && radiusInMeters > 0) {
                            if (lat != 0.0 && lon != 0.0) {
                                val distance = calculateHaversineDistance(latitude, longitude, lat, lon)
                                if (distance <= radiusInMeters) {
                                    stations.add(
                                        LocalStationSearchResult(
                                            bsId = bsId,
                                            bsNm = stopName,
                                            latitude = lat,
                                            longitude = lon,
                                            stationId = bsId,
                                            distance = distance
                                        )
                                    )
                                    Log.d(TAG, "정류장 추가: $stopName, bsId: $bsId, 거리: ${distance}m")
                                }
                            }
                        } else {
                            stations.add(
                                LocalStationSearchResult(
                                    bsId = bsId,
                                    bsNm = stopName,
                                    latitude = lat,
                                    longitude = lon,
                                    stationId = bsId
                                )
                            )
                            Log.d(TAG, "정류장 추가: $stopName, bsId: $bsId")
                        }
                    } while (cursor.moveToNext())
                }
            }

            if (latitude != 0.0 && longitude != 0.0 && radiusInMeters > 0) {
                stations.sortBy { it.distance }
                return@withContext stations.take(30)
            }
        } catch (e: Exception) {
            Log.e(TAG, "정류장 검색 오류: ${e.message}", e)
            throw e // 예외를 상위로 전달
        } finally {
            db.close()
        }
        Log.d(TAG, "정류장 검색 결과: ${stations.size}개")
        return@withContext stations
    }

    // 데이터베이스 강제 재설치
    fun forceReinstallDatabase() {
        val dbPath = context.getDatabasePath(DATABASE_NAME)
        if (dbPath.exists()) {
            dbPath.delete()
            Log.d(TAG, "기존 데이터베이스 삭제됨")
        }
        copyDatabaseFromAssets(context, dbPath)
        Log.d(TAG, "데이터베이스 재설치 완료")
    }

    // Haversine 공식으로 거리 계산 (미터 단위)
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