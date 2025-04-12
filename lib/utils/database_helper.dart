import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/bus_stop.dart';

class DatabaseHelper {
  static Database? _database;
  static bool _isInitializing = false;
  static final Completer<Database> _initCompleter = Completer<Database>();
  static const String databaseName = 'bus_stops.db';
  static const int databaseVersion = 1;

  // 앱 시작 시 미리 DB 초기화를 시작하는 메서드 추가
  static Future<void> preInitialize() async {
    if (_database != null || _isInitializing) return;
    _isInitializing = true;

    // sqflite_ffi 초기화
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;

    // 백그라운드에서 데이터베이스 초기화 시작
    try {
      final db = await compute(_initDatabaseInBackground, null);
      _database = db;
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete(db);
      }
      _isInitializing = false;
      debugPrint('✅ 데이터베이스 백그라운드 초기화 완료');
    } catch (e) {
      debugPrint('❌ 데이터베이스 백그라운드 초기화 실패: $e');
      _isInitializing = false;
      if (!_initCompleter.isCompleted) {
        _initCompleter.completeError(e);
      }
    }
  }

  // 백그라운드에서 실행될 DB 초기화 함수
  static Future<Database> _initDatabaseInBackground(void _) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, databaseName);

    try {
      bool dbExists = await databaseExists(path);
      if (!dbExists) {
        debugPrint('DB 파일이 존재하지 않음, assets에서 복사 시작');
        final byteData = await rootBundle.load('assets/bus_stops.db');
        final buffer = byteData.buffer.asUint8List();
        await File(path).writeAsBytes(buffer, flush: true);
        debugPrint('DB 파일 복사 성공: $path');
      }

      return await openDatabase(
        path,
        version: 1,
        readOnly: true, // 읽기 전용으로 열어 성능 향상
      );
    } catch (e) {
      debugPrint('DB 초기화 오류: $e');
      // 오류 발생 시 기존 DB 파일 삭제 후 재시도
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          debugPrint('손상된 DB 파일 삭제됨');
        }

        final byteData = await rootBundle.load('assets/bus_stops.db');
        final buffer = byteData.buffer.asUint8List();
        await File(path).writeAsBytes(buffer, flush: true);
        debugPrint('DB 파일 재복사 성공');

        return await openDatabase(path, version: 1, readOnly: true);
      } catch (retryError) {
        debugPrint('DB 복구 시도 실패: $retryError');
        throw Exception('데이터베이스 초기화 실패: $e, 복구 실패: $retryError');
      }
    }
  }

  Future<Database> get database async {
    if (_database != null) return _database!;

    if (_isInitializing) {
      // 이미 초기화 중이면 완료될 때까지 대기
      return _initCompleter.future;
    }

    // 아직 초기화되지 않았으면 초기화 시작
    _isInitializing = true;
    try {
      _database = await _initDatabase();
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete(_database);
      }
      return _database!;
    } catch (e) {
      _isInitializing = false;
      if (!_initCompleter.isCompleted) {
        _initCompleter.completeError(e);
      }
      rethrow;
    }
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, databaseName);

    bool dbExists = await databaseExists(path);
    if (!dbExists) {
      debugPrint('DB 파일이 존재하지 않음, assets에서 복사 시작');
      try {
        final byteData = await rootBundle.load('assets/$databaseName');
        final buffer = byteData.buffer.asUint8List();
        await File(path).writeAsBytes(buffer, flush: true);
        debugPrint('DB 파일 복사 성공: $path');
      } catch (e) {
        debugPrint('DB 파일 복사 실패: $e');
        throw Exception('DB 파일 로드 실패: $e');
      }
    }

    return await openDatabase(path, version: databaseVersion, readOnly: true);
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
