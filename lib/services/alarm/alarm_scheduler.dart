import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show logMessage, LogLevel;
import '../../models/auto_alarm.dart';
import '../../services/settings_service.dart';
import 'alarm_keys.dart';
import '../../utils/database_helper.dart';
import '../../utils/simple_tts_helper.dart';

class AlarmScheduler {
  AlarmScheduler({
    MethodChannel? methodChannel,
    required bool Function(Map<String, dynamic>) validateRequiredFields,
  })  : _methodChannel = methodChannel,
        _validateRequiredFields = validateRequiredFields;

  MethodChannel? _methodChannel;
  final bool Function(Map<String, dynamic>) _validateRequiredFields;

  void setMethodChannel(MethodChannel? methodChannel) {
    _methodChannel = methodChannel;
  }

  Future<void> scheduleAutoAlarm(
    AutoAlarm alarm,
    DateTime scheduledTime,
  ) async {
    if (!_validateRequiredFields(alarm.toJson())) {
      logMessage(
        '❌ 필수 파라미터 누락으로 자동 알람 예약 거부: ${alarm.toJson()}',
        level: LogLevel.error,
      );
      return;
    }

    try {
      final now = DateTime.now();
      final String uniqueAlarmId = "auto_alarm_${alarm.id}";
      final initialDelay = scheduledTime.difference(now);

      final actualDelay =
          initialDelay.inDays > 3 ? const Duration(days: 3) : initialDelay;

      final executionDelay = actualDelay.isNegative ? Duration.zero : actualDelay;

      final bool isImmediate =
          executionDelay.isNegative || executionDelay.inSeconds <= 30;

      String effectiveStationId = alarm.stationId;
      if (effectiveStationId.length < 10 || !effectiveStationId.startsWith('7')) {
        final dbStationId = await DatabaseHelper().getStationIdFromBsId(effectiveStationId);
        if (dbStationId != null && dbStationId.isNotEmpty) {
          logMessage('✅ stationId 변환: $effectiveStationId → $dbStationId');
          effectiveStationId = dbStationId;
        } else {
          logMessage('⚠️ stationId 변환 실패, 원본 사용: $effectiveStationId', level: LogLevel.warning);
        }
      }

      await _methodChannel?.invokeMethod('scheduleNativeAlarm', {
        // Dart String.hashCode는 버전 간 안정성이 없어 결정적 해시로 고정
        // (BootReceiver가 저장·재사용하는 ID와 반드시 일치해야 함)
        'alarmId': AlarmKeys.autoAlarmNativeId(alarm.id),
        'busNo': alarm.routeNo,
        'stationName': alarm.stationName,
        'routeId': alarm.routeId,
        'stationId': effectiveStationId,
        'useTTS': alarm.useTTS,
        'hour': scheduledTime.hour,
        'minute': scheduledTime.minute,
        'repeatDays': alarm.repeatDays,
        'scheduledTimeMillis': scheduledTime.millisecondsSinceEpoch,
        'isImmediate': isImmediate,
        'isCommuteAlarm': alarm.isCommuteAlarm,
        'alertOnArrivalOnly': SettingsService().alertOnArrivalOnly,
        'excludeHolidays': alarm.excludeHolidays,
      });

      logMessage(
        '✅ 네이티브 AlarmManager 스케줄링 요청 완료: ${alarm.routeNo} at $scheduledTime, 즉시 실행: $isImmediate',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'last_scheduled_alarm_$uniqueAlarmId',
        jsonEncode({
          'workId': 'native_alarm_$uniqueAlarmId',
          'busNo': alarm.routeNo,
          'stationName': alarm.stationName,
          'scheduledTime': scheduledTime.toIso8601String(),
          'registeredAt': now.toIso8601String(),
        }),
      );

      logMessage(
        '✅ 자동 알람 예약 성공: ${alarm.routeNo} at $scheduledTime (${executionDelay.inMinutes}분 후), 작업 ID: native_alarm_$uniqueAlarmId',
      );
    } catch (e) {
      logMessage('❌ 자동 알람 예약 오류: $e', level: LogLevel.error);
      await _notifySchedulingFailure(alarm);
    }
  }

  /// 예약 실패를 사용자에게 알린다. 별도의 백업 알람은 없다 —
  /// 네이티브가 이미 알람 시각 5분 전(trackingStartTime)에 발화하므로
  /// 같은 시각의 "백업"은 중복일 뿐이다.
  Future<void> _notifySchedulingFailure(AutoAlarm alarm) async {
    try {
      await SimpleTTSHelper.speak(
        "${alarm.routeNo}번 버스 자동 알람 예약에 문제가 발생했습니다. 앱을 다시 실행해 주세요.",
      );
    } catch (e) {
      logMessage('🔊 TTS 알림 실패: $e', level: LogLevel.error);
    }
  }
}
