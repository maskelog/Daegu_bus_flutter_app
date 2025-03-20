package com.example.daegu_bus_app

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import android.util.Log

class DatabaseHelper(context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {
    companion object {
        private const val DATABASE_NAME = "bus_stops.db"
        private const val DATABASE_VERSION = 3
        private const val TAG = "DatabaseHelper"
    }

    override fun onCreate(db: SQLiteDatabase) {
        // 버스 도착 정보 테이블 생성
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS bus_arrivals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                station_id TEXT NOT NULL,
                route_id TEXT NOT NULL,
                route_no TEXT NOT NULL,
                destination TEXT,
                bus_number TEXT,
                current_station TEXT,
                remaining_stops TEXT,
                estimated_time TEXT,
                is_low_floor INTEGER,
                is_out_of_service INTEGER,
                last_updated INTEGER
            )
        """)

        // bus_stops 테이블 생성
        db.execSQL("""
            CREATE TABLE IF NOT EXISTS bus_stops (
                bsId TEXT PRIMARY KEY,
                stop_name TEXT NOT NULL,
                latitude REAL,
                longitude REAL
            )
        """)

        // 테스트 데이터 삽입
        db.execSQL("INSERT INTO bus_stops (bsId, stop_name, latitude, longitude) VALUES ('STOP_001', '새동네', 35.870, 128.590)")
        db.execSQL("INSERT INTO bus_stops (bsId, stop_name, latitude, longitude) VALUES ('STOP_002', '강남역', 37.497, 127.027)")
    }

    override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
        if (oldVersion < 2) {
            db.execSQL("""
                CREATE TABLE IF NOT EXISTS bus_arrivals (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    station_id TEXT NOT NULL,
                    route_id TEXT NOT NULL,
                    route_no TEXT NOT NULL,
                    destination TEXT,
                    bus_number TEXT,
                    current_station TEXT,
                    remaining_stops TEXT,
                    estimated_time TEXT,
                    is_low_floor INTEGER,
                    is_out_of_service INTEGER,
                    last_updated INTEGER
                )
            """)
        }
        if (oldVersion < 3) {
            db.execSQL("""
                CREATE TABLE IF NOT EXISTS bus_stops (
                    bsId TEXT PRIMARY KEY,
                    stop_name TEXT NOT NULL,
                    latitude REAL,
                    longitude REAL
                )
            """)
        }
    }

    // 버스 도착 정보 저장
    fun saveBusArrivalInfo(stationId: String, arrivalInfo: BusArrivalInfo) {
        val db = writableDatabase
        try {
            // 기존 데이터 삭제
            db.delete("bus_arrivals", "station_id = ?", arrayOf(stationId))

            // 새 데이터 삽입
            arrivalInfo.buses.forEach { bus ->
                val values = ContentValues().apply {
                    put("station_id", stationId)
                    put("route_id", arrivalInfo.routeId)
                    put("route_no", arrivalInfo.routeNo)
                    put("destination", arrivalInfo.destination)
                    put("bus_number", bus.busNumber)
                    put("current_station", bus.currentStation)
                    put("remaining_stops", bus.remainingStops)
                    put("estimated_time", bus.estimatedTime)
                    put("is_low_floor", if (bus.isLowFloor) 1 else 0)
                    put("is_out_of_service", if (bus.isOutOfService) 1 else 0)
                    put("last_updated", System.currentTimeMillis())
                }
                db.insert("bus_arrivals", null, values)
            }
        } catch (e: Exception) {
            Log.e(TAG, "버스 도착 정보 저장 오류: ${e.message}", e)
        } finally {
            db.close()
        }
    }

    // 버스 도착 정보 조회
    fun getBusArrivalInfo(stationId: String): List<BusArrivalInfo> {
        val db = readableDatabase
        val cursor = db.query(
            "bus_arrivals",
            null,
            "station_id = ?",
            arrayOf(stationId),
            "route_id",
            null,
            "last_updated DESC"
        )

        val arrivalMap = mutableMapOf<String, MutableList<BusInfo>>()
        try {
            if (cursor.moveToFirst()) {
                do {
                    val routeId = cursor.getString(cursor.getColumnIndexOrThrow("route_id"))
                    val routeNo = cursor.getString(cursor.getColumnIndexOrThrow("route_no"))
                    val destination = cursor.getString(cursor.getColumnIndexOrThrow("destination"))
                    val busNumber = cursor.getString(cursor.getColumnIndexOrThrow("bus_number"))
                    val currentStation = cursor.getString(cursor.getColumnIndexOrThrow("current_station"))
                    val remainingStops = cursor.getString(cursor.getColumnIndexOrThrow("remaining_stops"))
                    val estimatedTime = cursor.getString(cursor.getColumnIndexOrThrow("estimated_time"))
                    val isLowFloor = cursor.getInt(cursor.getColumnIndexOrThrow("is_low_floor")) == 1
                    val isOutOfService = cursor.getInt(cursor.getColumnIndexOrThrow("is_out_of_service")) == 1

                    val busInfo = BusInfo(
                        busNumber = busNumber,
                        currentStation = currentStation,
                        remainingStops = remainingStops,
                        estimatedTime = estimatedTime,
                        isLowFloor = isLowFloor,
                        isOutOfService = isOutOfService
                    )

                    val key = "$routeId|$routeNo|$destination"
                    if (!arrivalMap.containsKey(key)) {
                        arrivalMap[key] = mutableListOf()
                    }
                    arrivalMap[key]!!.add(busInfo)
                } while (cursor.moveToNext())
            }
        } catch (e: Exception) {
            Log.e(TAG, "버스 도착 정보 조회 오류: ${e.message}", e)
        } finally {
            cursor.close()
            db.close()
        }

        return arrivalMap.map { (key, buses) ->
            val parts = key.split("|")
            BusArrivalInfo(
                routeId = parts[0],
                routeNo = parts[1],
                destination = parts[2],
                buses = buses
            )
        }
    }

    // 정류장 검색 메서드
    fun searchStations(searchText: String): List<StationSearchResult> {
        val db = readableDatabase
        val stations = mutableListOf<StationSearchResult>()
        val cursor = db.rawQuery(
            "SELECT bsId, stop_name FROM bus_stops WHERE stop_name LIKE ?",
            arrayOf("%$searchText%")
        )

        try {
            if (cursor.moveToFirst()) {
                do {
                    val stationId = cursor.getString(cursor.getColumnIndexOrThrow("bsId"))
                    val stationName = cursor.getString(cursor.getColumnIndexOrThrow("stop_name"))
                    stations.add(StationSearchResult(bsId = stationId, bsNm = stationName))
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