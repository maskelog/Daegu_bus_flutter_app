import 'package:daegu_bus_app/widgets/station_number_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('station number badge uses dark mode contrast colors', (tester) async {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.dark,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Center(
            child: StationNumberBadge(
              stationNumber: '1234',
            ),
          ),
        ),
      ),
    );

    final badgeFinder = find.descendant(
      of: find.byType(StationNumberBadge),
      matching: find.byType(Container),
    ).first;
    final badge = tester.widget<Container>(badgeFinder);
    final decoration = badge.decoration as BoxDecoration;
    expect(decoration.color, theme.colorScheme.surfaceContainerHighest);

    final text = tester.widget<Text>(find.text('1234'));
    expect(text.style?.color, theme.colorScheme.onSurface);
  });

  testWidgets('station number badge keeps light mode container accent', (tester) async {
    final theme = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.blue,
        brightness: Brightness.light,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Scaffold(
          body: Center(
            child: StationNumberBadge(
              stationNumber: '1234',
            ),
          ),
        ),
      ),
    );

    final badgeFinder = find.descendant(
      of: find.byType(StationNumberBadge),
      matching: find.byType(Container),
    ).first;
    final badge = tester.widget<Container>(badgeFinder);
    final decoration = badge.decoration as BoxDecoration;
    expect(decoration.color, theme.colorScheme.primaryContainer);

    final text = tester.widget<Text>(find.text('1234'));
    expect(text.style?.color, theme.colorScheme.onPrimaryContainer);
  });
}
