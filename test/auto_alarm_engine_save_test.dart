import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daegu_bus_app/models/alarm_data.dart';
import 'package:daegu_bus_app/services/alarm/alarm_state.dart';
import 'package:daegu_bus_app/services/alarm/auto_alarm_engine.dart';

Map<String, dynamic> _storedAlarm({
  required String id,
  required String routeNo,
  required bool isActive,
}) {
  return {
    'id': id,
    'routeNo': routeNo,
    'stationName': '테스트정류장',
    'stationId': '7000000001',
    'routeId': 'R001',
    'hour': 8,
    'minute': 0,
    'repeatDays': [1, 2, 3],
    'useTTS': true,
    'isActive': isActive,
    'isCommuteAlarm': true,
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('saveAutoAlarms preserves inactive alarms stored in prefs', () async {
    SharedPreferences.setMockInitialValues({
      'auto_alarms': [
        // 상태 리스트에도 있는 활성 알람 (갱신 대상)
        jsonEncode(_storedAlarm(id: 'a-1', routeNo: '410', isActive: true)),
        // off 상태 알람 — 덮어쓰기 후에도 보존되어야 한다
        jsonEncode(_storedAlarm(id: 'a-2', routeNo: '503', isActive: false)),
        // 상태 리스트에서 삭제된 활성 알람 — 저장 후 제거되어야 한다
        jsonEncode(_storedAlarm(id: 'a-3', routeNo: '719', isActive: true)),
      ],
    });

    final state = AlarmState();
    state.autoAlarms.add(AlarmData(
      id: 'a-1',
      busNo: '410',
      stationName: '테스트정류장',
      remainingMinutes: 5,
      scheduledTime: DateTime(2026, 7, 13, 8, 0),
      routeId: 'R001',
      isAutoAlarm: true,
      repeatDays: const [1, 2, 3],
    ));

    final engine = AutoAlarmEngine(
      state: state,
      resolveStationId: (_, __) => '7000000001',
    );

    await engine.saveAutoAlarms();

    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getStringList('auto_alarms') ?? [])
        .map((e) => jsonDecode(e) as Map<String, dynamic>)
        .toList();

    final ids = saved.map((e) => e['id']).toList();
    expect(ids, containsAll(['a-1', 'a-2']));
    expect(ids, isNot(contains('a-3')),
        reason: '상태 리스트에서 제거된 활성 알람은 저장소에서도 삭제되어야 한다');
    expect(ids.length, 2, reason: '중복 저장이 없어야 한다');

    final inactive = saved.firstWhere((e) => e['id'] == 'a-2');
    expect(inactive['isActive'], false,
        reason: 'off 알람의 비활성 상태가 뒤집히지 않아야 한다');
  });

  test('saveAutoAlarms does not duplicate an alarm that turned active again',
      () async {
    SharedPreferences.setMockInitialValues({
      'auto_alarms': [
        // 저장소에는 off로 남아 있지만 상태 리스트에서 다시 활성화된 알람
        jsonEncode(_storedAlarm(id: 'a-1', routeNo: '410', isActive: false)),
      ],
    });

    final state = AlarmState();
    state.autoAlarms.add(AlarmData(
      id: 'a-1',
      busNo: '410',
      stationName: '테스트정류장',
      remainingMinutes: 5,
      scheduledTime: DateTime(2026, 7, 13, 8, 0),
      routeId: 'R001',
      isAutoAlarm: true,
      repeatDays: const [1, 2, 3],
    ));

    final engine = AutoAlarmEngine(
      state: state,
      resolveStationId: (_, __) => '7000000001',
    );

    await engine.saveAutoAlarms();

    final prefs = await SharedPreferences.getInstance();
    final saved = (prefs.getStringList('auto_alarms') ?? [])
        .map((e) => jsonDecode(e) as Map<String, dynamic>)
        .toList();

    expect(saved.length, 1);
    expect(saved.single['id'], 'a-1');
    expect(saved.single['isActive'], true);
  });
}
