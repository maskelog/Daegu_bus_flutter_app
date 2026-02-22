import 'package:flutter_test/flutter_test.dart';
import 'package:daegu_bus_app/models/auto_alarm.dart';
import 'package:daegu_bus_app/services/settings_service.dart';

void main() {
  group('AutoAlarm getNextAlarmTime Logic Tests', () {
    test('Should return next day if time has passed and no repeat days set', () {
      final now = DateTime.now();
      final alarm = AutoAlarm(
        id: '1',
        routeNo: '410',
        stationName: 'Test',
        stationId: '123',
        routeId: '456',
        hour: now.hour - 1, // Past time
        minute: 0,
        repeatDays: [],
      );

      final nextAlarm = alarm.getNextAlarmTime(holidays: []);
      expect(nextAlarm?.day, equals(now.add(const Duration(days: 1)).day));
    });

    test('Should exclude weekends if toggled', () {
      // Find next Saturday
      var saturday = DateTime.now();
      while (saturday.weekday != 6) {
        saturday = saturday.add(const Duration(days: 1));
      }

      final alarm = AutoAlarm(
        id: '2',
        routeNo: '410',
        stationName: 'Test',
        stationId: '123',
        routeId: '456',
        hour: saturday.hour > 0 ? saturday.hour - 1 : 23,
        minute: 0,
        repeatDays: [6], // Only repeats on Saturday
        excludeWeekends: true, // But we exclude them!
      );

      final nextAlarm = alarm.getNextAlarmTime(holidays: []);
      // If we exclude the only repeat day, it shouldn't find a valid day within basic lookahead
      expect(nextAlarm, isNull);
    });

    test('Should exclude custom holidays', () {
      final now = DateTime.now();
      final targetDate = now.add(const Duration(days: 2));

      final alarm = AutoAlarm(
        id: '3',
        routeNo: '410',
        stationName: 'Test',
        stationId: '123',
        routeId: '456',
        hour: targetDate.hour,
        minute: targetDate.minute,
        repeatDays: [targetDate.weekday], // Set to repeat on that day
        excludeHolidays: true,
      );

      // We make the targetDate a "custom exclude date/holiday"
      final holidays = [DateTime(targetDate.year, targetDate.month, targetDate.day)];
      final nextAlarm = alarm.getNextAlarmTime(holidays: holidays);

      // It should skip the target date and find the week after (or be null if no repeat applies in lookahead)
      expect(nextAlarm?.day, isNot(equals(targetDate.day)));
    });
  });
}
