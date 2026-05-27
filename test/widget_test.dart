import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('App smoke test renders MaterialApp',
      (WidgetTester tester) async {
    await tester.pumpWidget(await buildTestMyApp());
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
