import 'package:daegu_bus_app/models/bus_arrival.dart';
import 'package:daegu_bus_app/models/bus_info.dart';
import 'package:daegu_bus_app/widgets/unified_bus_detail_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('bus detail presents arrivals as one ordered list',
      (tester) async {
    final arrival = BusArrival(
      routeNo: '501',
      routeId: 'R501',
      busInfoList: [
        BusInfo(
          busNumber: 'bus-1',
          currentStation: '경북대체육센터건너',
          remainingStops: '4 개소전',
          estimatedTime: '6분',
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

    await tester.tap(find.text('상세 열기'));
    await tester.pumpAndSettle();

    expect(find.text('도착 예정'), findsOneWidget);
    expect(find.text('2대'), findsOneWidget);
    expect(find.text('먼저 도착'), findsOneWidget);
    expect(find.text('다음 도착'), findsOneWidget);
    expect(find.text('첫 번째 버스'), findsNothing);
    expect(find.text('다음 버스'), findsNothing);
  });
}
