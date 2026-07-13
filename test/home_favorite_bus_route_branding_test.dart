import 'package:daegu_bus_app/models/bus_arrival.dart';
import 'package:daegu_bus_app/models/bus_info.dart';
import 'package:daegu_bus_app/screens/home_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('favorite bus route chip uses route branding colors', (tester) async {
    final arrival = BusArrival(
      routeNo: '직행1',
      routeId: 'R-DIRECT-1',
      busInfoList: [
        BusInfo(
          busNumber: 'bus-1',
          currentStation: '정류장',
          remainingStops: '3 개소전',
          estimatedTime: '7분',
        ),
      ],
    );

    await tester.pumpWidget(await buildTestMaterialApp(
      home: Material(
        child: HomeRouteItem(
          arrival: arrival,
          stationId: '7000000000',
          stationName: '테스트 정류장',
          getBusColor: (_, __, ___) => const Color(0xFF2196F3),
          isFavoriteBus: (_) => false,
          onToggleFavorite: (_, __) async {},
          onAlarmTap: (_, __, ___, ____) async {},
        ),
      ),
    ));

    final routeText = tester.widget<Text>(find.text('직행1'));
    expect(routeText.style?.color, const Color(0xFFE60012));
  });
  testWidgets('general route chip keeps readable text on a light fallback color', (tester) async {
    final arrival = BusArrival(
      routeNo: '503',
      routeId: 'R-GENERAL-503',
      busInfoList: [
        BusInfo(
          busNumber: 'bus-503',
          currentStation: '정류장',
          remainingStops: '3 개소전',
          estimatedTime: '7분',
        ),
      ],
    );

    await tester.pumpWidget(await buildTestMaterialApp(
      home: Material(
        child: HomeRouteItem(
          arrival: arrival,
          stationId: '7000000000',
          stationName: '테스트 정류장',
          getBusColor: (_, __, ___) => Colors.white,
          isFavoriteBus: (_) => false,
          onToggleFavorite: (_, __) async {},
          onAlarmTap: (_, __, ___, ____) async {},
        ),
      ),
    ));

    final routeText = tester.widget<Text>(find.text('503'));
    expect(routeText.style?.color, Colors.black);
  });
}
