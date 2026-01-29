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

  test('home_screen uses Korean arrival labels', () {
    final source = File('lib/screens/home_screen.dart').readAsStringSync();

    final hasArrivingSoon =
        source.contains('곧 도착') || source.contains(r'\uace7 \ub3c4\ucc29');
    final hasMinutes = source.contains('분') || source.contains(r'\ubd84');
    final hasNext = source.contains('다음') || source.contains(r'\ub2e4\uc74c');

    expect(hasArrivingSoon, isTrue);
    expect(hasMinutes, isTrue);
    expect(hasNext, isTrue);
  });
}
