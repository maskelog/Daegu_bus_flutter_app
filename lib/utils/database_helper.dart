import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';
import '../models/bus_stop.dart';

class DatabaseHelper {
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'bus_stops.db');

    bool dbExists = await databaseExists(path);
    if (!dbExists) {
      debugPrint('DB file does not exist, copying from assets');
      try {
        final byteData = await rootBundle.load('assets/bus_stops.db');
        final buffer = byteData.buffer.asUint8List();
        await File(path).writeAsBytes(buffer, flush: true);
        debugPrint('DB file copied successfully to: $path');
      } catch (e) {
        debugPrint('Failed to copy DB file: $e');
        throw Exception('Failed to load DB file: $e');
      }
    } else {
      debugPrint('DB file already exists at: $path');
    }

    return await openDatabase(path, version: 1);
  }

  Future<List<BusStop>> getAllStations() async {
    final db = await database;
    try {
      debugPrint('Querying all stations from bus_stops table');
      final List<Map<String, dynamic>> maps = await db.query('bus_stops');
      debugPrint('Query returned ${maps.length} rows');
      if (maps.isEmpty) {
        debugPrint('No data found in bus_stops table');
        return [];
      }
      final stations = List.generate(maps.length, (i) {
        final name = maps[i]['stop_name']?.toString() ??
            '알 수 없는 정류장'; // stop-name -> stop_name
        final bsId = maps[i]['bsId']?.toString() ?? ''; // bsld -> bsId

        // 좌표 데이터 처리
        double? longitude;
        double? latitude;

        // 문자열을 double로 변환
        try {
          if (maps[i]['longitude'] != null) {
            longitude = double.tryParse(maps[i]['longitude'].toString());
          }
          if (maps[i]['latitude'] != null) {
            latitude = double.tryParse(maps[i]['latitude'].toString());
          }
        } catch (e) {
          debugPrint('Error parsing coordinates for station $bsId: $e');
        }

        // 추가 정보: stationId
        final stationId = maps[i]['stationId']?.toString();

        debugPrint(
            'Processing station: ID=$bsId, Name=$name, StationId=$stationId');

        return BusStop(
          id: bsId,
          name: name,
          isFavorite: false,
          stationId: stationId, // stationId 필드 추가
          ngisXPos: longitude,
          ngisYPos: latitude,
          wincId: bsId, // wincId와 bsId는 동일하게 설정
        );
      });
      debugPrint('Successfully generated ${stations.length} BusStop objects');
      return stations;
    } catch (e) {
      debugPrint(
          'Error querying stations: $e - Stack trace: ${StackTrace.current}');
      throw Exception('Error querying stations: $e');
    }
  }

  // 특정 stationId로 정류장 검색
  Future<BusStop?> getStationByStationId(String stationId) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'bus_stops',
        where: 'stationId = ?',
        whereArgs: [stationId],
      );

      if (maps.isEmpty) {
        return null;
      }

      final map = maps.first;
      final name = map['stop_name']?.toString() ?? '알 수 없는 정류장';
      final bsId = map['bsId']?.toString() ?? '';

      // 좌표 데이터 처리
      double? longitude;
      double? latitude;

      try {
        if (map['longitude'] != null) {
          longitude = double.tryParse(map['longitude'].toString());
        }
        if (map['latitude'] != null) {
          latitude = double.tryParse(map['latitude'].toString());
        }
      } catch (e) {
        debugPrint('Error parsing coordinates for station $bsId: $e');
      }

      return BusStop(
        id: bsId,
        name: name,
        isFavorite: false,
        stationId: stationId,
        ngisXPos: longitude,
        ngisYPos: latitude,
        wincId: bsId,
      );
    } catch (e) {
      debugPrint('Error querying station by stationId: $e');
      return null;
    }
  }

  // bsId로 stationId 조회
  Future<String?> getStationIdFromBsId(String bsId) async {
    final db = await database;
    try {
      final List<Map<String, dynamic>> maps = await db.query(
        'bus_stops',
        columns: ['stationId'],
        where: 'bsId = ?',
        whereArgs: [bsId],
      );

      if (maps.isEmpty) {
        return null;
      }

      return maps.first['stationId']?.toString();
    } catch (e) {
      debugPrint('Error querying stationId by bsId: $e');
      return null;
    }
  }
}
