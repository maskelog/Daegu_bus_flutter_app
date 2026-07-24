import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Android edge-to-edge 설정은 불필요한 Material 의존성을 포함하지 않는다', () {
    final buildGradle = File('android/app/build.gradle').readAsStringSync();

    expect(
      buildGradle,
      isNot(contains('com.google.android.material:material')),
      reason: '사용하지 않는 MaterialDatePicker가 Android 15 지원 중단 시스템 바 API를 '
          '릴리스 APK에 포함시킨다.',
    );
  });

  test('MainActivity는 AndroidX 권장 edge-to-edge API를 사용한다', () {
    final mainActivity = File(
      'android/app/src/main/kotlin/com/devground/daegubus/MainActivity.kt',
    ).readAsStringSync();

    expect(mainActivity, contains('WindowCompat.enableEdgeToEdge(window)'));
    expect(mainActivity, isNot(contains('setDecorFitsSystemWindows')));
  });
}
