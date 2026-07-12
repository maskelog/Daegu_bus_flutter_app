import 'package:daegu_bus_app/models/bus_arrival.dart';
import 'package:daegu_bus_app/models/bus_info.dart';
import 'package:daegu_bus_app/widgets/unified_bus_detail_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('express route keeps arrival cards neutral while route accent stays red', (tester) async {
    final arrival = BusArrival(
      routeNo: '급행2',
      routeId: 'REXP2',
      busInfoList: [
        BusInfo(
          busNumber: 'bus-1',
          currentStation: '경북대체육센터건너',
          remainingStops: '4 개소전',
          estimatedTime: '10분',
        ),
        BusInfo(
          busNumber: 'bus-2',
          currentStation: '파군재삼거리1',
          remainingStops: '14 개소전',
          estimatedTime: '23분',
        ),
      ],
    );

    await tester.pumpWidget(await buildTestMaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showUnifiedBusDetailModal(
            context,
            arrival,
            '7021024000',
            '새동네아파트앞',
          ),
          child: const Text('상세 열기'),
        ),
      ),
    ));

    final theme = Theme.of(tester.element(find.byType(ElevatedButton)));

    await tester.tap(find.text('상세 열기'));
    await tester.pumpAndSettle();

    final redArrivalBackgroundFinder = find.ancestor(
      of: find.text('먼저 도착'),
      matching: find.byWidgetPredicate((widget) {
        if (widget is! Container) return false;
        final decoration = widget.decoration;
        if (decoration is! BoxDecoration) return false;
        return decoration.color == const Color(0xFFE53935);
      }),
    );
    expect(redArrivalBackgroundFinder, findsNothing);

    final tenTexts = tester.widgetList<Text>(find.text('10'));
    expect(
      tenTexts.any((text) => text.style?.color == theme.colorScheme.onSurfaceVariant),
      isTrue,
    );

    final redRouteButtonFinder = find.byWidgetPredicate((widget) {
      if (widget is! Ink) return false;
      final decoration = widget.decoration;
      if (decoration is! BoxDecoration) return false;
      return decoration.color == const Color(0xFFE60012);
    });
    expect(redRouteButtonFinder, findsWidgets);
  });

  testWidgets('arrival time turns red only when the bus is imminent', (tester) async {
    final arrival = BusArrival(
      routeNo: '급행2',
      routeId: 'REXP2',
      busInfoList: [
        BusInfo(
          busNumber: 'bus-1',
          currentStation: '경북대체육센터건너',
          remainingStops: '1 개소전',
          estimatedTime: '2분',
        ),
      ],
    );

    await tester.pumpWidget(await buildTestMaterialApp(
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showUnifiedBusDetailModal(
            context,
            arrival,
            '7021024000',
            '새동네아파트앞',
          ),
          child: const Text('상세 열기'),
        ),
      ),
    ));

    final theme = Theme.of(tester.element(find.byType(ElevatedButton)));

    await tester.tap(find.text('상세 열기'));
    await tester.pumpAndSettle();

    final redTimeTextFinder = find.byWidgetPredicate((widget) {
      if (widget is! Text) return false;
      return widget.data == '2' && widget.style?.color == theme.colorScheme.error;
    });
    expect(redTimeTextFinder, findsWidgets);
  });
}




