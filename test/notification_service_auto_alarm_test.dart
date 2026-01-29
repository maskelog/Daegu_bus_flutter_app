import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daegu_bus_app/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('auto alarm update does not call getBusInfo when stationId missing',
      () async {
    SharedPreferences.setMockInitialValues({});

    const stationChannel =
        MethodChannel('com.example.daegu_bus_app/station_tracking');
    const busChannel = MethodChannel('com.example.daegu_bus_app/bus_api');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    var stationCalled = false;
    messenger.setMockMethodCallHandler(stationChannel, (call) async {
      if (call.method == 'getBusInfo') {
        stationCalled = true;
        return jsonEncode({
          'remainingMinutes': 5,
          'currentStation': 'Test Station',
        });
      }
      return null;
    });

    messenger.setMockMethodCallHandler(busChannel, (call) async {
      if (call.method == 'showNotification') {
        return true;
      }
      return null;
    });

    final service = NotificationService();
    service.startAutoAlarmUpdates(
      id: 1,
      busNo: '101',
      stationName: 'Test Stop',
      routeId: 'R1',
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(stationCalled, isFalse);

    service.stopAutoAlarmUpdates();
    messenger.setMockMethodCallHandler(stationChannel, null);
    messenger.setMockMethodCallHandler(busChannel, null);
  });
}
