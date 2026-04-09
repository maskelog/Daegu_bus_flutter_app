import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daegu_bus_app/services/alarm_service.dart';
import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:daegu_bus_app/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadAutoAlarms re-registers native alarms on app startup', () async {
    final now = DateTime.now().add(const Duration(minutes: 10));
    SharedPreferences.setMockInitialValues({
      'auto_alarms': [
        jsonEncode({
          'id': 'alarm-1',
          'routeNo': '410',
          'stationName': '테스트정류장',
          'stationId': 'ST001',
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
    expect(scheduledCalls.single.arguments['stationId'], 'ST001');
    expect(scheduledCalls.single.arguments['routeId'], 'R001');

    messenger.setMockMethodCallHandler(channel, null);
  });
}
