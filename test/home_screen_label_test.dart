import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home_screen does not use min/Next labels', () {
    final source = File('lib/screens/home_screen.dart').readAsStringSync();

    final hasMinLabel = RegExp(r"Text\(\s*'min'").hasMatch(source);
    final hasNextLabel = RegExp(r"Text\(\s*'Next'").hasMatch(source);

    expect(hasMinLabel, isFalse);
    expect(hasNextLabel, isFalse);
  });

  test('arrival time labels are Korean (BusArrival model)', () {
    // 홈 화면의 도착 라벨은 BusArrival.getFirstArrivalTimeText()에서 나온다.
    final source = File('lib/models/bus_arrival.dart').readAsStringSync();

    expect(source.contains('곧 도착'), isTrue);
    expect(source.contains('분'), isTrue);
  });
}
