import 'package:daegu_bus_app/utils/app_logger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

void main() {
  test('buildDebugPrintCallback suppresses output in release mode', () {
    final messages = <String?>[];

    final callback = buildDebugPrintCallback(
      isReleaseMode: true,
      fallback: (String? message, {int? wrapWidth}) {
        messages.add(message);
      },
    );

    callback('release log');

    expect(messages, isEmpty);
  });

  test('buildDebugPrintCallback forwards output in debug mode', () {
    final messages = <String?>[];

    final callback = buildDebugPrintCallback(
      isReleaseMode: false,
      fallback: (String? message, {int? wrapWidth}) {
        messages.add(message);
      },
    );

    callback('debug log');

    expect(messages, ['debug log']);
  });

  test('buildRootLogLevel disables logger output in release mode', () {
    expect(buildRootLogLevel(isReleaseMode: true), Level.OFF);
  });

  test('buildRootLogLevel keeps logger output enabled in debug mode', () {
    expect(buildRootLogLevel(isReleaseMode: false), Level.ALL);
  });
}
