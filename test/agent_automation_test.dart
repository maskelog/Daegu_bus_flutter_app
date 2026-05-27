import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:daegu_bus_app/screens/map_screen.dart';

import 'helpers/test_app.dart';

void main() {
  group('Agent Mode Automation Tests', () {
    testWidgets('App should start without errors', (WidgetTester tester) async {
      await tester.pumpWidget(await buildTestMyApp());
      await tester.pump();

      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('Map screen shows initialization error in widget test',
        (WidgetTester tester) async {
      await tester.pumpWidget(await buildTestMaterialApp(
        home: const MapScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('지도 초기화 중 오류'), findsOneWidget);
    });

    testWidgets('Map screen widget can be mounted',
        (WidgetTester tester) async {
      await tester.pumpWidget(await buildTestMaterialApp(
        home: const MapScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(MapScreen), findsOneWidget);
    });
  });
}
