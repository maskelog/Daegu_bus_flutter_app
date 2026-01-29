import 'package:flutter_test/flutter_test.dart';

import 'package:daegu_bus_app/models/auto_alarm.dart';

void main() {
  test('Weekday.getName returns Korean short names', () {
    expect(Weekday.getName(Weekday.monday), '월');
    expect(Weekday.getName(Weekday.tuesday), '화');
    expect(Weekday.getName(Weekday.wednesday), '수');
    expect(Weekday.getName(Weekday.thursday), '목');
    expect(Weekday.getName(Weekday.friday), '금');
    expect(Weekday.getName(Weekday.saturday), '토');
    expect(Weekday.getName(Weekday.sunday), '일');
    expect(Weekday.getName(0), '?');
  });
}
