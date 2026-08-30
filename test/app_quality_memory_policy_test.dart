import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('무거운 지도는 선택된 탭에서만 생성한다', () {
    final source = File('lib/screens/home_screen.dart').readAsStringSync();

    expect(source, isNot(contains('MapScreen.preloadKakaoMapHtml()')));
    expect(
      source,
      contains(
        '_tabController.index == 0\n'
        '                            ? _buildMapScreen()\n'
        '                            : const SizedBox.shrink()',
      ),
    );
    expect(
      source,
      contains(
        '_tabController.index == 1\n'
        '                            ? _buildMapTab()\n'
        '                            : const SizedBox.shrink()',
      ),
    );
  });

  test('지도 런타임 캐시는 상한을 두고 화면 종료 시 비운다', () {
    final source = File('lib/screens/map_screen.dart').readAsStringSync();

    expect(source, contains('_nearbyCacheLimit = 12'));
    expect(source, contains('_stationInfoCacheLimit = 24'));
    expect(source, contains('_stationIdCacheLimit = 100'));
    expect(source, contains('_trimRuntimeCaches();'));
    expect(source, contains('_clearRuntimeCaches();'));
  });

  test('기기 이전은 사용자 설정을 유지하고 재생성 가능한 데이터는 제외한다', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final modernRulesFile = File(
      'android/app/src/main/res/xml/data_extraction_rules.xml',
    );
    final legacyRulesFile = File(
      'android/app/src/main/res/xml/backup_rules.xml',
    );

    expect(manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
    expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
    expect(modernRulesFile.existsSync(), isTrue);
    expect(legacyRulesFile.existsSync(), isTrue);
    final modernRules = modernRulesFile.readAsStringSync();
    final legacyRules = legacyRulesFile.readAsStringSync();
    for (final rules in [modernRules, legacyRules]) {
      expect(rules, contains('domain="database" path="."'));
      expect(rules, contains('domain="sharedpref" path="BusRouteCache.xml"'));
      expect(rules, isNot(contains('FlutterSharedPreferences.xml')));
    }
  });
}
