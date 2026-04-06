import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show logMessage, LogLevel;
import '../../models/auto_alarm.dart';
import 'alarm_state.dart';

class AutoAlarmEngine {
  AutoAlarmEngine({
    required AlarmState state,
    required String Function(String stationName, String routeId) resolveStationId,
  })  : _state = state,
        _resolveStationId = resolveStationId;

  final AlarmState _state;
  final String Function(String stationName, String routeId) _resolveStationId;

  Future<void> saveAutoAlarms() async {
    await _saveAutoAlarms();
  }

  Future<void> _saveAutoAlarms() async {
    try {
      logMessage('🔄 자동 알람 저장 시작...');
      final prefs = await SharedPreferences.getInstance();
      final List<String> alarms = _state.autoAlarms.map((alarm) {
        final autoAlarm = AutoAlarm(
          id: alarm.id,
          routeNo: alarm.busNo,
          stationName: alarm.stationName,
          stationId: _resolveStationId(alarm.stationName, alarm.routeId),
          routeId: alarm.routeId,
          hour: alarm.scheduledTime.hour,
          minute: alarm.scheduledTime.minute,
          repeatDays: alarm.repeatDays ?? [],
          useTTS: alarm.useTTS,
          isActive: true,
        );

        final json = autoAlarm.toJson();
        json['scheduledTime'] = alarm.scheduledTime.toIso8601String();
        final jsonString = jsonEncode(json);

        logMessage('📝 알람 데이터 변환: ${alarm.busNo}번 버스');
        logMessage('  - ID: ${autoAlarm.id}');
        logMessage('  - 시간: ${autoAlarm.hour}:${autoAlarm.minute}');
        logMessage(
          '  - 정류장: ${autoAlarm.stationName} (${autoAlarm.stationId})',
        );
        logMessage(
          '  - 반복: ${autoAlarm.repeatDays.map((d) => [
                '월',
                '화',
                '수',
                '목',
                '금',
                '토',
                '일'
              ][d - 1]).join(", ")}',
        );
        logMessage('  - JSON: $jsonString');

        return jsonString;
      }).toList();

      logMessage('📊 저장할 알람 수: ${alarms.length}개');
      await prefs.setStringList('auto_alarms', alarms);

      final savedAlarms = prefs.getStringList('auto_alarms') ?? [];
      logMessage('✅ 자동 알람 저장 완료');
      logMessage('  - 저장된 알람 수: ${savedAlarms.length}개');
      if (savedAlarms.isNotEmpty) {
        final firstAlarm = jsonDecode(savedAlarms.first);
        logMessage('  - 첫 번째 알람 정보:');
        logMessage('    • 버스: ${firstAlarm['routeNo']}');
        logMessage('    • 시간: ${firstAlarm['scheduledTime']}');
        logMessage(
          '    • 반복: ${(firstAlarm['repeatDays'] as List).map((d) => [
                '월',
                '화',
                '수',
                '목',
                '금',
                '토',
                '일'
              ][d - 1]).join(", ")}',
        );
      }
    } catch (e) {
      logMessage('❌ 자동 알람 저장 오류: $e', level: LogLevel.error);
      logMessage('  - 스택 트레이스: ${e is Error ? e.stackTrace : "없음"}');
    }
  }
}
