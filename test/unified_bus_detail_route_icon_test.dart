import 'package:daegu_bus_app/models/bus_arrival.dart';
import 'package:daegu_bus_app/screens/route_map_screen.dart';
import 'package:daegu_bus_app/widgets/unified_bus_detail_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('bus detail route badge shows a route map icon', (tester) async {
    final arrival = BusArrival(
      routeNo: '304',
      routeId: 'R304',
      busInfoList: const [],
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

    expect(find.byIcon(Icons.route_rounded), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == '304번 노선도 보기',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byIcon(Icons.route_rounded));
    await tester.pump();

    expect(find.byType(RouteMapScreen), findsOneWidget);

    await tester.pump(const Duration(seconds: 16));
    await tester.pumpAndSettle();
  });
}
