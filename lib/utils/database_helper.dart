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
        debugPrint('Processing station: ID=$bsId, Name=$name');
        return BusStop(
          id: bsId,
          name: name,
          isFavorite: false,
          ngisXPos: maps[i]['longitude']?.toString() ?? '0.0',
          ngisYPos: maps[i]['latitude']?.toString() ?? '0.0',
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

  // 기타 메서드 (getStationById 등)는 필요 시 동일하게 수정
}
