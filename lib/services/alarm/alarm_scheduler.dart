import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show logMessage, LogLevel;
import '../../models/auto_alarm.dart';
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

      await _methodChannel?.invokeMethod('scheduleNativeAlarm', {
        'alarmId': uniqueAlarmId.hashCode,
        'busNo': alarm.routeNo,
        'stationName': alarm.stationName,
        'routeId': alarm.routeId,
        'stationId': alarm.stationId,
        'useTTS': alarm.useTTS,
        'hour': scheduledTime.hour,
        'minute': scheduledTime.minute,
        'repeatDays': alarm.repeatDays,
        'isImmediate': isImmediate,
        'isCommuteAlarm': alarm.isCommuteAlarm,
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

      if (executionDelay.inSeconds > 30) {
        await _scheduleBackupAlarm(alarm, uniqueAlarmId.hashCode, scheduledTime);
        logMessage(
          '✅ 백업 알람 등록: ${alarm.routeNo}번, ${executionDelay.inMinutes}분 후 실행',
          level: LogLevel.info,
        );
      }
    } catch (e) {
      logMessage('❌ 자동 알람 예약 오류: $e', level: LogLevel.error);
      await _scheduleLocalBackupAlarm(alarm, scheduledTime);
    }
  }

  Future<void> _scheduleLocalBackupAlarm(
    AutoAlarm alarm,
    DateTime scheduledTime,
  ) async {
    try {
      logMessage(
        '⏰ 로컬 백업 알람 등록 시도: ${alarm.routeNo}, ${alarm.stationName}',
        level: LogLevel.debug,
      );

      try {
        await SimpleTTSHelper.speak(
          "${alarm.routeNo}번 버스 자동 알람 예약에 문제가 발생했습니다. 앱을 다시 실행해 주세요.",
        );
      } catch (e) {
        logMessage('🔊 TTS 알림 실패: $e', level: LogLevel.error);
      }

      final prefs = await SharedPreferences.getInstance();
      final alarmInfo = {
        'routeNo': alarm.routeNo,
        'stationName': alarm.stationName,
        'scheduledTime': scheduledTime.toIso8601String(),
        'registeredAt': DateTime.now().toIso8601String(),
        'hasSchedulingError': true,
      };

      await prefs.setString('alarm_scheduling_error', jsonEncode(alarmInfo));
      await prefs.setBool('has_alarm_scheduling_error', true);

      logMessage('⏰ 로컬 백업 알람 정보 저장 완료', level: LogLevel.debug);
    } catch (e) {
      logMessage('❌ 로컬 백업 알람 등록 실패: $e', level: LogLevel.error);
    }
  }

  Future<void> _scheduleBackupAlarm(
    AutoAlarm alarm,
    int id,
    DateTime scheduledTime,
  ) async {
    try {
      final backupTime = scheduledTime.subtract(const Duration(minutes: 5));
      final now = DateTime.now();
      if (backupTime.isBefore(now)) {
        logMessage(
          '⚠️ 백업 알람 시간($backupTime)이 현재($now)보다 빠릅니다. 백업 알람 등록 취소.',
        );
        return;
      }

      logMessage(
        '✅ 네이티브 백업 알람 스케줄링 요청 완료: ${alarm.routeNo} at $backupTime',
      );
    } catch (e) {
      logMessage('❌ 백업 알람 예약 오류: $e', level: LogLevel.error);
    }
  }
}
