import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../../main.dart' show logMessage, LogLevel;

class HolidayService {
  static const String _cdnBase =
      'https://cdn.jsdelivr.net/gh/hyunbinseo/open-data@main/data/holidays';

  final Map<int, List<DateTime>> _yearCache = {};

  Future<List<DateTime>> fetchHolidays(int year, int month) async {
    final yearHolidays = await _loadYear(year);
    return yearHolidays
        .where((d) => d.month == month)
        .toList(growable: false);
  }

  Future<List<DateTime>> _loadYear(int year) async {
    final cached = _yearCache[year];
    if (cached != null) return cached;

    final fromAsset = await _tryLoadAsset(year);
    if (fromAsset != null) {
      _yearCache[year] = fromAsset;
      return fromAsset;
    }

    final fromCdn = await _tryLoadCdn(year);
    if (fromCdn != null) {
      _yearCache[year] = fromCdn;
      return fromCdn;
    }

    logMessage('❌ 공휴일 데이터 로드 실패: $year', level: LogLevel.error);
    _yearCache[year] = const [];
    return const [];
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
      final response = await http
          .get(Uri.parse('$_cdnBase/$year.json'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        logMessage('✅ 공휴일 CDN fallback 사용: $year');
        return _parse(response.body);
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

  List<DateTime> _parse(String raw) {
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final dates = <DateTime>[];
    for (final key in decoded.keys) {
      final parts = key.split('-');
      if (parts.length != 3) continue;
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final d = int.tryParse(parts[2]);
      if (y == null || m == null || d == null) continue;
      dates.add(DateTime(y, m, d));
    }
    return dates;
  }
}
