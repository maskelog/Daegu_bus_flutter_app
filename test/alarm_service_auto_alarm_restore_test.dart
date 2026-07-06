import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daegu_bus_app/models/auto_alarm.dart';
import 'package:daegu_bus_app/services/alarm/alarm_keys.dart';
import 'package:daegu_bus_app/services/alarm_service.dart';
import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:daegu_bus_app/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadAutoAlarms re-registers native alarms on app startup', () async {
    final rawNow = DateTime.now().add(const Duration(minutes: 10));
    final now = DateTime(
      rawNow.year,
      rawNow.month,
      rawNow.day,
      rawNow.hour,
      rawNow.minute,
    );
    SharedPreferences.setMockInitialValues({
      'auto_alarms': [
        jsonEncode({
          'id': 'alarm-1',
          'routeNo': '410',
          'stationName': '테스트정류장',
          'stationId': '7000000001',
          'routeId': 'R001',
          'scheduledTime': now.toIso8601String(),
          'repeatDays': [now.weekday],
          'useTTS': true,
          'isActive': true,
          'isCommuteAlarm': true,
        }),
      ],
    });

    const channel = MethodChannel('com.devground.daegubus/bus_api');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final scheduledCalls = <MethodCall>[];

    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'scheduleNativeAlarm') {
        scheduledCalls.add(call);
        return true;
      }
      return null;
    });

    final service = AlarmService(
      notificationService: NotificationService(),
      settingsService: SettingsService(),
    );

    await service.loadAutoAlarms();

    expect(scheduledCalls, hasLength(1));
    expect(scheduledCalls.single.arguments['busNo'], '410');
    expect(scheduledCalls.single.arguments['stationId'], '7000000001');
    expect(scheduledCalls.single.arguments['routeId'], 'R001');
    expect(scheduledCalls.single.arguments['scheduledTimeMillis'],
        now.millisecondsSinceEpoch);

    messenger.setMockMethodCallHandler(channel, null);
  });

  test('updateAutoAlarms preserves inactive alarms in preferences', () async {
    final rawNow = DateTime.now().add(const Duration(minutes: 10));
    final now = DateTime(
      rawNow.year,
      rawNow.month,
      rawNow.day,
      rawNow.hour,
      rawNow.minute,
    );
    final activeAlarm = {
      'id': 'active-alarm',
      'routeNo': '410',
      'stationName': '활성정류장',
      'stationId': '7000000001',
      'routeId': 'R001',
      'hour': now.hour,
      'minute': now.minute,
      'repeatDays': [now.weekday],
      'useTTS': true,
      'isActive': true,
      'isCommuteAlarm': true,
    };
    final inactiveAlarm = {
      'id': 'inactive-alarm',
      'routeNo': '623',
      'stationName': '비활성정류장',
      'stationId': '7000000002',
      'routeId': 'R002',
      'hour': now.hour,
      'minute': now.minute,
      'repeatDays': [now.weekday],
      'useTTS': true,
      'isActive': false,
      'isCommuteAlarm': true,
    };

    SharedPreferences.setMockInitialValues({
      'auto_alarms': [
        jsonEncode(activeAlarm),
        jsonEncode(inactiveAlarm),
      ],
    });

    const channel = MethodChannel('com.devground.daegubus/bus_api');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async => true);

    final service = AlarmService(
      notificationService: NotificationService(),
      settingsService: SettingsService(),
    );

    await service.updateAutoAlarms([
      AutoAlarm.fromJson(activeAlarm),
      AutoAlarm.fromJson(inactiveAlarm),
    ]);

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('auto_alarms') ?? [];
    final savedIds = saved
        .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
        .map((json) => json['id'])
        .toList();

    expect(savedIds, containsAll(['active-alarm', 'inactive-alarm']));
    expect(saved, hasLength(2));

    messenger.setMockMethodCallHandler(channel, null);
  });

  test('cancelScheduledAutoAlarm cancels native alarm and clears schedule marker',
      () async {
    const alarmId = 'alarm-to-cancel';
    const uniqueAlarmId = 'auto_alarm_$alarmId';
    SharedPreferences.setMockInitialValues({
      'last_scheduled_alarm_$uniqueAlarmId': '{"registeredAt":"test"}',
    });

    const channel = MethodChannel('com.devground.daegubus/bus_api');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    final service = AlarmService(
      notificationService: NotificationService(),
      settingsService: SettingsService(),
    );

    await service.cancelScheduledAutoAlarm(alarmId);

    // 현행 ID + 구버전 ID 2종(Dart hashCode, Math.abs(Java hash))을 함께 취소한다.
    expect(calls.map((call) => call.method).toSet(), {'cancelNativeAutoAlarm'});
    final cancelledIds =
        calls.map((call) => call.arguments['alarmId'] as int).toList();
    expect(cancelledIds.first, AlarmKeys.autoAlarmNativeId(alarmId));
    expect(cancelledIds, contains(uniqueAlarmId.hashCode));
    expect(cancelledIds, contains(AlarmKeys.javaStringHashCode(alarmId).abs()));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('last_scheduled_alarm_$uniqueAlarmId'), isFalse);

    messenger.setMockMethodCallHandler(channel, null);
  });

  test('updateAutoAlarms cancels stale native schedule before rescheduling edit',
      () async {
    final rawNow = DateTime.now().add(const Duration(minutes: 10));
    final now = DateTime(
      rawNow.year,
      rawNow.month,
      rawNow.day,
      rawNow.hour,
      rawNow.minute,
    );
    final editedAlarm = {
      'id': 'edited-alarm',
      'routeNo': '410',
      'stationName': '수정정류장',
      'stationId': '7000000001',
      'routeId': 'R001',
      'hour': now.hour,
      'minute': now.minute,
      'repeatDays': [now.weekday],
      'useTTS': true,
      'isActive': true,
      'isCommuteAlarm': true,
    };

    SharedPreferences.setMockInitialValues({});

    const channel = MethodChannel('com.devground.daegubus/bus_api');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'cancelNativeAutoAlarm' ||
          call.method == 'scheduleNativeAlarm') {
        calls.add(call);
      }
      return true;
    });

    final service = AlarmService(
      notificationService: NotificationService(),
      settingsService: SettingsService(),
    );

    await service.updateAutoAlarms([AutoAlarm.fromJson(editedAlarm)]);

    // 취소(현행 + 구버전 ID들)가 모두 스케줄 등록보다 먼저 와야 한다.
    expect(calls.last.method, 'scheduleNativeAlarm');
    expect(
      calls.sublist(0, calls.length - 1).map((call) => call.method).toSet(),
      {'cancelNativeAutoAlarm'},
    );
    final nativeId = AlarmKeys.autoAlarmNativeId(editedAlarm['id'] as String);
    expect(calls.first.arguments['alarmId'], nativeId);
    expect(calls.last.arguments['alarmId'], nativeId);
    expect(calls.last.arguments['scheduledTimeMillis'],
        now.millisecondsSinceEpoch);

    messenger.setMockMethodCallHandler(channel, null);
  });
}
