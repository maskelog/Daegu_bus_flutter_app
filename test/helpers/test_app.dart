import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daegu_bus_app/main.dart';
import 'package:daegu_bus_app/services/alarm_service.dart';
import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:daegu_bus_app/services/settings_service.dart';

Future<Widget> buildTestMyApp() async {
  return _buildWithProviders(const MyApp());
}

Future<Widget> buildTestMaterialApp({
  required Widget home,
}) async {
  return _buildWithProviders(MaterialApp(home: home));
}

Future<Widget> _buildWithProviders(Widget child) async {
  SharedPreferences.setMockInitialValues({});

  final settingsService = SettingsService();
  await settingsService.initialize();

  final notificationService = NotificationService();
  final alarmService = AlarmService(
    notificationService: notificationService,
    settingsService: settingsService,
  );

  return MultiProvider(
    providers: [
      ChangeNotifierProvider<NotificationService>.value(
        value: notificationService,
      ),
      ChangeNotifierProvider<SettingsService>.value(
        value: settingsService,
      ),
      ChangeNotifierProvider<AlarmService>.value(
        value: alarmService,
      ),
    ],
    child: child,
  );
}
