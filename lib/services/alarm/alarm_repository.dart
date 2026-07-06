import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show logMessage, LogLevel;
import '../../models/alarm_data.dart' as alarm_model;
import '../../models/auto_alarm.dart';
import 'alarm_keys.dart';
import 'auto_alarm_validator.dart';
import 'station_id_resolver.dart';

/// 알람 영속화(SharedPreferences) 전담.
///
/// 읽기는 파싱·유효성 필터까지 마친 모델을 돌려주고,
/// 상태(activeAlarmsMap 등) 반영과 notifyListeners는 호출자(AlarmService) 몫이다.
class AlarmRepository {
  /// 백그라운드 isolate에서 플랫폼 채널을 쓰기 전에 메신저를 초기화한다.
  /// 메인 isolate에서는 no-op에 가깝고, 실패해도 무시한다.
  static void ensureBackgroundMessenger(String tag) {
    if (kIsWeb) return;
    try {
      final rootIsolateToken = RootIsolateToken.instance;
      if (rootIsolateToken != null) {
        BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
        logMessage('✅ [$tag] BackgroundIsolateBinaryMessenger 초기화 성공');
      } else {
        logMessage(
          '⚠️ [$tag] RootIsolateToken이 null입니다. 메인 스레드에서 실행 중인지 확인하세요.',
          level: LogLevel.warning,
        );
      }
    } catch (e) {
      logMessage(
        '⚠️ [$tag] BackgroundIsolateBinaryMessenger 초기화 오류 (무시): $e',
        level: LogLevel.warning,
      );
    }
  }

  /// 저장된 일반 알람을 로드한다. 5분 이상 지난 알람은 걸러낸다.
  Future<Map<String, alarm_model.AlarmData>> loadActiveAlarms() async {
    ensureBackgroundMessenger('alarms');

    final prefs = await SharedPreferences.getInstance();
    final alarms = prefs.getStringList('alarms') ?? [];
    final result = <String, alarm_model.AlarmData>{};

    for (var json in alarms) {
      try {
        final data = jsonDecode(json);
        final alarm = alarm_model.AlarmData.fromJson(data);
        if (_isAlarmValid(alarm)) {
          final key =
              AlarmKeys.alarm(alarm.busNo, alarm.stationName, alarm.routeId);
          result[key] = alarm;
        }
      } catch (e) {
        logMessage('알람 데이터 파싱 오류: $e', level: LogLevel.error);
      }
    }
    return result;
  }

  bool _isAlarmValid(alarm_model.AlarmData alarm) {
    final now = DateTime.now();
    final difference = alarm.scheduledTime.difference(now);
    return difference.inMinutes > -5; // 5분 이상 지난 알람은 제외
  }

  Future<void> saveActiveAlarms(
      Iterable<alarm_model.AlarmData> alarms) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> encoded =
          alarms.map((alarm) => jsonEncode(alarm.toJson())).toList();
      await prefs.setStringList('alarms', encoded);
      logMessage('✅ 알람 저장 완료: ${encoded.length}개');
    } catch (e) {
      logMessage('❌ 알람 저장 오류: $e', level: LogLevel.error);
    }
  }

  /// 저장된 자동 알람을 로드한다.
  /// scheduledTime 변환·stationId 보정·필수 필드 검증까지 마친 모델만 반환.
  Future<List<AutoAlarm>> loadAutoAlarms() async {
    ensureBackgroundMessenger('auto_alarms');

    final prefs = await SharedPreferences.getInstance();
    final alarms = prefs.getStringList('auto_alarms') ?? [];
    logMessage('자동 알람 데이터 로드 시작: ${alarms.length}개');

    final result = <AutoAlarm>[];
    for (var alarmJson in alarms) {
      try {
        final Map<String, dynamic> data = jsonDecode(alarmJson);

        // scheduledTime이 문자열이면 DateTime으로 변환
        if (data['scheduledTime'] is String) {
          data['scheduledTime'] = DateTime.parse(data['scheduledTime']);
        }

        // stationId가 없는 경우, stationName과 routeId로 찾아옴
        if (data['stationId'] == null || data['stationId'].isEmpty) {
          data['stationId'] = resolveStationIdFromName(
            data['stationName'],
            data['routeId'],
          );
        }

        // 필수 필드 검증
        if (!validateAutoAlarmFields(data)) {
          logMessage('⚠️ 자동 알람 데이터 필수 필드 누락: $data', level: LogLevel.warning);
          continue;
        }

        result.add(AutoAlarm.fromJson(data));
      } catch (e) {
        logMessage('❌ 자동 알람 파싱 오류: $e', level: LogLevel.error);
      }
    }
    return result;
  }

  /// 예약된 자동 알람의 마지막 스케줄 마커 제거.
  Future<void> removeScheduledAlarmMarker(String uniqueAlarmId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('last_scheduled_alarm_$uniqueAlarmId');
  }

  /// 공휴일·커스텀 예외 날짜를 네이티브가 읽을 수 있는 형태로 저장.
  ///
  /// 네이티브(AlarmReceiver 체인·BootReceiver)는 앱 실행 없이 다음 알람을
  /// 재계산하므로, excludeHolidays 판단에 쓸 날짜 목록을 String(JSON)으로
  /// 내려둔다. setString은 FlutterSharedPreferences에 평문으로 저장되어
  /// Kotlin에서 getString("flutter.excluded_dates")로 읽힌다.
  Future<void> saveExcludedDates(List<DateTime> dates) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final formatted = dates
          .map((d) => '${d.year.toString().padLeft(4, '0')}-'
              '${d.month.toString().padLeft(2, '0')}-'
              '${d.day.toString().padLeft(2, '0')}')
          .toSet()
          .toList();
      await prefs.setString('excluded_dates', jsonEncode(formatted));
    } catch (e) {
      logMessage('❌ 예외 날짜 저장 오류: $e', level: LogLevel.error);
    }
  }
}
