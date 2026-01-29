import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daegu_bus_app/services/alarm_service.dart';
import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:daegu_bus_app/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restart prevention duration is 3000ms', () {
    SharedPreferences.setMockInitialValues({});

    final service = AlarmService(
      notificationService: NotificationService(),
      settingsService: SettingsService(),
    );

    expect(service.restartPreventionDurationMs, 3000);
  });
}
