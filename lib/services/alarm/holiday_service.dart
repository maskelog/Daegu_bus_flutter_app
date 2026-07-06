import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show logMessage, LogLevel;

/// 한국 공휴일 조회.
///
/// 우선순위: 메모리 → 영속 캐시(7일 이내) → CDN(성공 시 영속화) →
/// 만료된 영속 캐시 → 번들 에셋(assets/holidays).
///
/// CDN을 번들 에셋보다 먼저 보는 이유: 임시공휴일처럼 나중에 지정되는
/// 날짜는 번들에 반영될 수 없다. 반대로 오프라인이어도 영속 캐시·에셋으로
/// 동작하고, 실패를 영구 기억하지 않아 네트워크가 돌아오면 자동 복구된다.
class HolidayService {
  static const String _cdnBase =
      'https://cdn.jsdelivr.net/gh/hyunbinseo/open-data@main/data/holidays';
  static const Duration _cacheTtl = Duration(days: 7);
  static const Duration _failureRetryAfter = Duration(minutes: 30);

  // alarm_facade와 alarm_screen이 캐시를 공유하도록 싱글턴으로 제공.
  static HolidayService? _instance;
  factory HolidayService() => _instance ??= HolidayService.internal();

  @visibleForTesting
  HolidayService.internal({http.Client? client}) : _client = client;

  final http.Client? _client;

  final Map<int, List<DateTime>> _yearCache = {};
  final Map<int, Future<List<DateTime>>> _inFlight = {};
  final Map<int, DateTime> _lastFailureAt = {};

  Future<List<DateTime>> fetchHolidays(int year, int month) async {
    final yearHolidays = await _loadYear(year);
    return yearHolidays
        .where((d) => d.month == month)
        .toList(growable: false);
  }

  Future<List<DateTime>> _loadYear(int year) {
    final cached = _yearCache[year];
    if (cached != null) return Future.value(cached);

    // 동시 호출(현재 달·다음 달 연속 조회 등)이 CDN을 중복 타지 않게 합류
    return _inFlight[year] ??= _loadYearUncached(year).whenComplete(() {
      _inFlight.remove(year);
    });
  }

  Future<List<DateTime>> _loadYearUncached(int year) async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (_) {
      prefs = null;
    }
    final persisted = prefs == null ? null : _readPersisted(prefs, year);

    // 1. 신선한 영속 캐시
    if (persisted != null && persisted.isFresh) {
      _yearCache[year] = persisted.dates;
      return persisted.dates;
    }

    // 2. CDN (직전 실패 후 30분 안에는 건너뜀)
    final lastFailure = _lastFailureAt[year];
    final skipCdn = lastFailure != null &&
        DateTime.now().difference(lastFailure) < _failureRetryAfter;
    if (!skipCdn) {
      final fromCdn = await _tryLoadCdn(year);
      if (fromCdn != null) {
        _lastFailureAt.remove(year);
        _yearCache[year] = fromCdn;
        if (prefs != null) await _persist(prefs, year, fromCdn);
        return fromCdn;
      }
      _lastFailureAt[year] = DateTime.now();
    }

    // 3. 만료된 영속 캐시라도 사용 (임시공휴일 최신화만 늦어질 뿐)
    if (persisted != null) {
      logMessage('⚠️ 공휴일 CDN 실패, 만료된 캐시 사용: $year', level: LogLevel.warning);
      _yearCache[year] = persisted.dates;
      return persisted.dates;
    }

    // 4. 번들 에셋
    final fromAsset = await _tryLoadAsset(year);
    if (fromAsset != null) {
      logMessage('✅ 공휴일 번들 에셋 사용: $year');
      _yearCache[year] = fromAsset;
      return fromAsset;
    }

    // 빈 결과는 메모리에 캐시하지 않는다 — 다음 호출에서 재시도
    // (_lastFailureAt이 30분 과호출을 막는다)
    logMessage('❌ 공휴일 데이터 로드 실패: $year', level: LogLevel.error);
    return const [];
  }

  _PersistedHolidays? _readPersisted(SharedPreferences prefs, int year) {
    try {
      final raw = prefs.getString('holidays_cache_$year');
      if (raw == null) return null;
      final dates = (jsonDecode(raw) as List)
          .map((s) => _parseDate(s.toString()))
          .whereType<DateTime>()
          .toList(growable: false);
      final fetchedAt = prefs.getInt('holidays_cache_at_$year') ?? 0;
      final isFresh = DateTime.now().millisecondsSinceEpoch - fetchedAt <
          _cacheTtl.inMilliseconds;
      return _PersistedHolidays(dates, isFresh);
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist(
      SharedPreferences prefs, int year, List<DateTime> dates) async {
    try {
      final encoded = jsonEncode(dates
          .map((d) => '${d.year.toString().padLeft(4, '0')}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}')
          .toList());
      await prefs.setString('holidays_cache_$year', encoded);
      await prefs.setInt(
          'holidays_cache_at_$year', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      logMessage('⚠️ 공휴일 캐시 저장 실패: $e', level: LogLevel.warning);
    }
  }

  Future<List<DateTime>?> _tryLoadAsset(int year) async {
    try {
      final raw = await rootBundle.loadString('assets/holidays/$year.json');
      return _parse(raw);
    } catch (_) {
      return null;
    }
  }

  Future<List<DateTime>?> _tryLoadCdn(int year) async {
    try {
      final uri = Uri.parse('$_cdnBase/$year.json');
      final response = await (_client?.get(uri) ?? http.get(uri))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        final parsed = _parse(response.body);
        logMessage('✅ 공휴일 CDN 로드: $year (${parsed.length}일)');
        return parsed;
      }
      logMessage(
        '❌ 공휴일 CDN 응답 오류: ${response.statusCode}',
        level: LogLevel.error,
      );
      return null;
    } catch (e) {
      logMessage('❌ 공휴일 CDN 호출 오류: $e', level: LogLevel.error);
      return null;
    }
  }

  /// CDN·에셋 공통 포맷: {"yyyy-MM-dd": "이름", ...}
  List<DateTime> _parse(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.keys
        .map(_parseDate)
        .whereType<DateTime>()
        .toList(growable: false);
  }

  DateTime? _parseDate(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return null;
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y == null || m == null || d == null) return null;
    return DateTime(y, m, d);
  }
}

class _PersistedHolidays {
  const _PersistedHolidays(this.dates, this.isFresh);

  final List<DateTime> dates;
  final bool isFresh;
}
