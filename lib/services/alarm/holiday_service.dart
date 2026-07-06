import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:klc/klc.dart' as klc;
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

    // 5. 최후 fallback: 양력 고정 + 음력 계산 공휴일을 반환.
    // 결과는 메모리에 캐시하지 않는다 — 다음 호출에서 재시도
    // (_lastFailureAt이 30분 과호출을 막는다)
    logMessage(
      '❌ 공휴일 데이터 로드 실패: $year — 계산된 공휴일로 대체',
      level: LogLevel.error,
    );
    return fallbackHolidaysForYear(year);
  }

  /// 연도 데이터가 전혀 없을 때의 최후 fallback.
  /// 양력 고정 공휴일 + 음력 변환으로 계산한 설날·부처님오신날·추석 연휴에
  /// 「관공서의 공휴일에 관한 규정」 제3조의 대체공휴일 규칙을 적용한다.
  /// (임시공휴일·선거일은 계산할 수 없으므로 여전히 부분적이다)
  ///
  /// 규칙 요약 — 대체공휴일이 생기는 조건:
  /// - 설·추석 연휴: 연휴 중 하루가 일요일이거나 다른 공휴일과 겹칠 때
  /// - 어린이날·부처님오신날·기독탄신일: 토·일 또는 다른 공휴일과 겹칠 때
  /// - 삼일절·광복절·개천절·한글날: 토·일과 겹칠 때
  /// - 신정·현충일: 대체공휴일 없음
  /// 대체일은 겹친 날(연휴는 연휴 끝) 이후 첫 번째 비공휴일 평일.
  @visibleForTesting
  List<DateTime> fallbackHolidaysForYear(int year) {
    final noSubstitute = [
      DateTime(year, 1, 1), // 신정
      DateTime(year, 6, 6), // 현충일
    ];
    final weekendRule = [
      DateTime(year, 3, 1), // 삼일절
      DateTime(year, 8, 15), // 광복절
      DateTime(year, 10, 3), // 개천절
      DateTime(year, 10, 9), // 한글날
    ];
    final buddhaDay = _lunarToSolarOrNull(year, 4, 8); // 부처님오신날
    final overlapRule = [
      DateTime(year, 5, 5), // 어린이날
      DateTime(year, 12, 25), // 기독탄신일
      if (buddhaDay != null) buddhaDay,
    ];
    final seollalRun = _lunarRun(year, 1, 1); // 설날 연휴 (전날~다음날)
    final chuseokRun = _lunarRun(year, 8, 15); // 추석 연휴

    // 겹침 판정용 카운트 (같은 날짜에 공휴일 2개 = 겹침, 예: 2025 어린이날+부처님오신날)
    final allBase = <DateTime>[
      ...noSubstitute,
      ...weekendRule,
      ...overlapRule,
      ...seollalRun,
      ...chuseokRun,
    ];
    final counts = <DateTime, int>{};
    for (final d in allBase) {
      counts[d] = (counts[d] ?? 0) + 1;
    }
    final holidays = counts.keys.toSet();

    bool isWeekend(DateTime d) =>
        d.weekday == DateTime.saturday || d.weekday == DateTime.sunday;
    bool overlapsOther(DateTime d) => (counts[d] ?? 0) > 1;

    // 대체공휴일 청구: (기준일 anchor) 목록. 같은 날짜의 겹침은 1건으로 센다.
    final anchors = <DateTime>[];
    for (final run in [seollalRun, chuseokRun]) {
      if (run.isEmpty) continue;
      final runEnd = run.last;
      for (final day in run) {
        if (day.weekday == DateTime.sunday || overlapsOther(day)) {
          anchors.add(runEnd);
        }
      }
    }
    for (final d in weekendRule) {
      if (isWeekend(d)) anchors.add(d);
    }
    for (final d in overlapRule.toSet()) {
      if (isWeekend(d) || overlapsOther(d)) anchors.add(d);
    }

    // 대체일 배정: anchor 이후 첫 비공휴일 평일 (이미 배정된 대체일도 회피)
    final substitutes = <DateTime>{};
    for (final anchor in anchors..sort()) {
      var candidate = anchor.add(const Duration(days: 1));
      while (isWeekend(candidate) ||
          holidays.contains(candidate) ||
          substitutes.contains(candidate)) {
        candidate = candidate.add(const Duration(days: 1));
      }
      substitutes.add(candidate);
    }

    return [...holidays, ...substitutes]..sort();
  }

  /// 음력 연휴(당일 ± 1일)를 양력으로. 변환 불가면 빈 리스트.
  List<DateTime> _lunarRun(int year, int lunarMonth, int lunarDay) {
    final day = _lunarToSolarOrNull(year, lunarMonth, lunarDay);
    if (day == null) return const [];
    return [
      day.subtract(const Duration(days: 1)),
      day,
      day.add(const Duration(days: 1)),
    ];
  }

  /// klc(한국천문연구원 기준 KoreanLunarCalendar 포트)의 음력→양력 변환.
  /// 지원 범위(1900~2049) 밖이거나 실패하면 null.
  ///
  /// 주의: 중국력 기반 변환기를 쓰면 안 된다 — 자오선 차이(UTC+8/+9)로
  /// 한국 설날과 하루 어긋나는 해가 있다 (예: 2027년 중국 춘절 2/6, 한국 설날 2/7).
  /// 정확성은 테스트에서 확정 공휴일 데이터(2025~2027)와 교차 검증한다.
  DateTime? _lunarToSolarOrNull(int year, int lunarMonth, int lunarDay) {
    if (year < 1900 || year > 2049) return null;
    try {
      if (!klc.setLunarDate(year, lunarMonth, lunarDay, false)) return null;
      final parsed = DateTime.parse(klc.getSolarIsoFormat());
      return DateTime(parsed.year, parsed.month, parsed.day);
    } catch (e) {
      logMessage(
        '⚠️ 음력 변환 실패($year-$lunarMonth-$lunarDay): $e',
        level: LogLevel.warning,
      );
      return null;
    }
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

  /// 관공서 공휴일이 아닌데 월력요항 기반 데이터에 섞여 오는 이름들.
  ///
  /// - 제헌절: 2008년부터 공휴일이 아님 (2026·2027 upstream 데이터에 잘못 포함)
  /// - 노동절(근로자의 날): 관공서 공휴일이 아니고 버스도 평일 운행 —
  ///   알람이 안 울려 지각하는 것보다 울리는 쪽이 안전하다.
  ///   쉬는 사용자는 커스텀 예외 날짜로 직접 추가할 수 있다.
  ///
  /// "대체공휴일(제헌절)" 형태도 걸러지도록 부분 문자열로 매칭한다.
  static const List<String> _nonPublicHolidayNames = ['제헌절', '노동절', '근로자의 날'];

  /// CDN·에셋 공통 포맷: {"yyyy-MM-dd": ["이름", ...], ...}
  List<DateTime> _parse(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final dates = <DateTime>[];
    decoded.forEach((key, value) {
      final date = _parseDate(key);
      if (date == null) return;

      // 같은 날짜에 유효한 공휴일이 하나라도 겹치면 유지
      // (예: 어린이날+부처님오신날), 전부 비공휴일 이름이면 제외.
      final names = value is List
          ? value.map((e) => e.toString()).toList()
          : <String>[value.toString()];
      final allNonPublic =
          names.isNotEmpty && names.every(_isNonPublicHoliday);
      if (allNonPublic) return;

      dates.add(date);
    });
    return dates;
  }

  bool _isNonPublicHoliday(String name) =>
      _nonPublicHolidayNames.any((blocked) => name.contains(blocked));

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
