import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bus_arrival.dart';
import '../models/bus_stop.dart';

/// 버스 정보 캐시 관리자
class BusCacheManager {
  static const int cacheDurationSeconds = 300; // 5분
  static const int maxCacheEntries = 50; // 최대 캐시 항목 수
  static const String cachePrefix = 'bus_cache_';
  static const String timestampPrefix = 'bus_timestamp_';
  static const String cacheKeys = 'cache_keys';

  static BusCacheManager? _instance;
  static BusCacheManager get instance => _instance ??= BusCacheManager._();

  BusCacheManager._();

  SharedPreferences? _prefs;

  /// SharedPreferences 초기화
  Future<void> initialize() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 캐시 유효성 검증
  bool isValidCache(String key) {
    final timestampKey = '$timestampPrefix$key';
    final cachedTime = _prefs?.getInt(timestampKey);

    if (cachedTime == null) return false;

    final cacheAge = DateTime.now().millisecondsSinceEpoch - cachedTime;
    return cacheAge < (cacheDurationSeconds * 1000);
  }

  /// 버스 도착 정보 캐시 저장
  Future<void> cacheBusArrivals(
      String stationId, List<BusArrival> arrivals) async {
    await initialize();

    // 유효한 데이터만 캐시
    final validArrivals = arrivals
        .where((arrival) =>
            arrival.busInfoList.isNotEmpty &&
            arrival.busInfoList.any((bus) =>
                !bus.isOutOfService &&
                bus.estimatedTime.isNotEmpty &&
                bus.estimatedTime != "운행종료"))
        .toList();

    if (validArrivals.isEmpty) return;

    final key = '$cachePrefix$stationId';
    final timestampKey = '$timestampPrefix$stationId';

    // 데이터 직렬화
    final jsonData = validArrivals.map((arrival) => arrival.toJson()).toList();

    await _prefs?.setString(key, jsonEncode(jsonData));
    await _prefs?.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);

    // 캐시 키 목록 업데이트
    await _updateCacheKeys(stationId);

    // 캐시 크기 제한
    await _enforceCacheLimit();
  }

  /// 버스 도착 정보 캐시 조회
  Future<List<BusArrival>?> getCachedBusArrivals(String stationId) async {
    await initialize();

    if (!isValidCache(stationId)) return null;

    final key = '$cachePrefix$stationId';
    final jsonString = _prefs?.getString(key);

    if (jsonString == null) return null;

    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => BusArrival.fromJson(json)).toList();
    } catch (e) {
      // 캐시 데이터가 손상된 경우 제거
      await removeCachedBusArrivals(stationId);
      return null;
    }
  }

  /// 정류장 정보 캐시 저장
  Future<void> cacheBusStops(String searchKey, List<BusStop> stops) async {
    await initialize();

    if (stops.isEmpty) return;

    final key = '${cachePrefix}stations_$searchKey';
    final timestampKey = '${timestampPrefix}stations_$searchKey';

    final jsonData = stops.map((stop) => stop.toJson()).toList();

    await _prefs?.setString(key, jsonEncode(jsonData));
    await _prefs?.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);

    await _updateCacheKeys('stations_$searchKey');
    await _enforceCacheLimit();
  }

  /// 정류장 정보 캐시 조회
  Future<List<BusStop>?> getCachedBusStops(String searchKey) async {
    await initialize();

    if (!isValidCache('stations_$searchKey')) return null;

    final key = '${cachePrefix}stations_$searchKey';
    final jsonString = _prefs?.getString(key);

    if (jsonString == null) return null;

    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((json) => BusStop.fromJson(json)).toList();
    } catch (e) {
      await removeCachedBusStops(searchKey);
      return null;
    }
  }

  /// 특정 정류장의 버스 정보 캐시 삭제
  Future<void> removeCachedBusArrivals(String stationId) async {
    await initialize();

    final key = '$cachePrefix$stationId';
    final timestampKey = '$timestampPrefix$stationId';

    await _prefs?.remove(key);
    await _prefs?.remove(timestampKey);

    await _removeCacheKey(stationId);
  }

  /// 특정 검색키의 정류장 정보 캐시 삭제
  Future<void> removeCachedBusStops(String searchKey) async {
    await initialize();

    final key = '${cachePrefix}stations_$searchKey';
    final timestampKey = '${timestampPrefix}stations_$searchKey';

    await _prefs?.remove(key);
    await _prefs?.remove(timestampKey);

    await _removeCacheKey('stations_$searchKey');
  }

  /// 만료된 캐시 정리
  Future<void> cleanExpiredCache() async {
    await initialize();

    final cacheKeys = await _getCacheKeys();
    final expiredKeys = <String>[];

    for (final key in cacheKeys) {
      if (!isValidCache(key)) {
        expiredKeys.add(key);
      }
    }

    for (final key in expiredKeys) {
      await _prefs?.remove('$cachePrefix$key');
      await _prefs?.remove('$timestampPrefix$key');
    }

    if (expiredKeys.isNotEmpty) {
      final remainingKeys =
          cacheKeys.where((k) => !expiredKeys.contains(k)).toList();
      await _prefs?.setStringList(BusCacheManager.cacheKeys, remainingKeys);
    }
  }

  /// 전체 캐시 삭제
  Future<void> clearAllCache() async {
    await initialize();

    final cacheKeys = await _getCacheKeys();

    for (final key in cacheKeys) {
      await _prefs?.remove('$cachePrefix$key');
      await _prefs?.remove('$timestampPrefix$key');
    }

    await _prefs?.remove(BusCacheManager.cacheKeys);
  }

  /// 캐시 통계 정보 조회
  Future<CacheStats> getCacheStats() async {
    await initialize();

    final cacheKeys = await _getCacheKeys();
    int validCount = 0;
    int expiredCount = 0;

    for (final key in cacheKeys) {
      if (isValidCache(key)) {
        validCount++;
      } else {
        expiredCount++;
      }
    }

    return CacheStats(
      totalEntries: cacheKeys.length,
      validEntries: validCount,
      expiredEntries: expiredCount,
    );
  }

  /// 캐시 키 목록 업데이트
  Future<void> _updateCacheKeys(String key) async {
    final keys = await _getCacheKeys();

    if (!keys.contains(key)) {
      keys.add(key);
      await _prefs?.setStringList(BusCacheManager.cacheKeys, keys);
    }
  }

  /// 캐시 키 제거
  Future<void> _removeCacheKey(String key) async {
    final keys = await _getCacheKeys();
    keys.remove(key);
    await _prefs?.setStringList(BusCacheManager.cacheKeys, keys);
  }

  /// 캐시 키 목록 조회
  Future<List<String>> _getCacheKeys() async {
    return _prefs?.getStringList(BusCacheManager.cacheKeys) ?? [];
  }

  /// 캐시 크기 제한 적용
  Future<void> _enforceCacheLimit() async {
    final keys = await _getCacheKeys();

    if (keys.length > maxCacheEntries) {
      // 가장 오래된 캐시부터 제거
      final keysWithTimestamp = <MapEntry<String, int>>[];

      for (final key in keys) {
        final timestamp = _prefs?.getInt('$timestampPrefix$key') ?? 0;
        keysWithTimestamp.add(MapEntry(key, timestamp));
      }

      keysWithTimestamp.sort((a, b) => a.value.compareTo(b.value));

      final keysToRemove = keysWithTimestamp
          .take(keysWithTimestamp.length - maxCacheEntries)
          .map((e) => e.key)
          .toList();

      for (final key in keysToRemove) {
        await _prefs?.remove('$cachePrefix$key');
        await _prefs?.remove('$timestampPrefix$key');
      }

      final remainingKeys =
          keys.where((k) => !keysToRemove.contains(k)).toList();
      await _prefs?.setStringList(BusCacheManager.cacheKeys, remainingKeys);
    }
  }
}

/// 캐시 통계 정보
class CacheStats {
  final int totalEntries;
  final int validEntries;
  final int expiredEntries;

  CacheStats({
    required this.totalEntries,
    required this.validEntries,
    required this.expiredEntries,
  });

  double get hitRate => totalEntries > 0 ? validEntries / totalEntries : 0.0;

  @override
  String toString() {
    return 'CacheStats{total: $totalEntries, valid: $validEntries, expired: $expiredEntries, hitRate: ${(hitRate * 100).toStringAsFixed(1)}%}';
  }
}
