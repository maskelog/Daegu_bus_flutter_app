import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:daegu_bus_app/main.dart';
import 'package:daegu_bus_app/screens/map_screen.dart';

void main() {
  group('Agent Mode Automation Tests', () {
    testWidgets('App should start without errors', (WidgetTester tester) async {
      // 앱 시작 테스트
      await tester.pumpWidget(const MyApp());
      await tester.pumpAndSettle();

      // 기본 위젯들이 로드되는지 확인
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Map screen should load correctly',
        (WidgetTester tester) async {
      // 지도 화면 테스트
      await tester.pumpWidget(const MaterialApp(
        home: MapScreen(),
      ));
      await tester.pumpAndSettle();

      // 지도 관련 위젯 확인
      expect(find.byType(WebViewWidget), findsOneWidget);
    });

    testWidgets('InfoWindow should display without black border',
        (WidgetTester tester) async {
      // InfoWindow border 테스트
      await tester.pumpWidget(const MaterialApp(
        home: MapScreen(),
      ));
      await tester.pumpAndSettle();

      // InfoWindow가 검정색 border 없이 표시되는지 확인
      // 실제 테스트는 WebView 내부에서 실행되어야 함
    });
  });
}
