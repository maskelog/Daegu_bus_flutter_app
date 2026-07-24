import 'package:daegu_bus_app/screens/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('지도 정류장 카드는 핀과 중복되는 이름을 숨기고 짧은 CTA를 표시한다', (tester) async {
    var showOnHomePressed = false;
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomLeft,
            child: SizedBox(
              width: 377,
              child: StationMapActionCard(
                stationName: '칠성고가도로하단',
                onShowOnHome: () => showOnHomePressed = true,
                onClose: () {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('칠성고가도로하단'), findsNothing);
    expect(find.text('도착정보 보기'), findsOneWidget);
    expect(find.bySemanticsLabel('칠성고가도로하단 도착정보 보기'), findsOneWidget);

    final actionButton = find.byKey(
      const Key('map_show_station_on_home_button'),
    );
    final buttonSize = tester.getSize(actionButton);
    expect(buttonSize.height, greaterThanOrEqualTo(48));
    expect(buttonSize.width, greaterThan(280));

    final label = tester.widget<Text>(find.text('도착정보 보기'));
    expect(label.maxLines, 1);
    expect(label.softWrap, isFalse);
    expect(
      tester.getSize(find.byType(StationMapActionCard)).height,
      48,
    );
    expect(
      find.descendant(
        of: find.byType(StationMapActionCard),
        matching: find.byType(FilledButton),
      ),
      findsNothing,
    );
    expect(tester.widget(actionButton), isA<InkWell>());

    await tester.tap(actionButton);
    expect(showOnHomePressed, isTrue);
    semantics.dispose();
  });

  testWidgets('지도 정류장 카드 닫기 버튼은 48dp 터치 영역을 제공한다', (tester) async {
    var closePressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: StationMapActionCard(
          stationName: '칠성고가도로하단',
          onShowOnHome: () {},
          onClose: () => closePressed = true,
        ),
      ),
    );

    final closeButton = find.byTooltip('선택한 정류장 닫기');
    expect(tester.getSize(closeButton).height, greaterThanOrEqualTo(48));
    expect(tester.getSize(closeButton).width, greaterThanOrEqualTo(48));

    await tester.tap(closeButton);
    expect(closePressed, isTrue);
  });
}
