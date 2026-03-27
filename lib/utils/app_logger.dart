import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

typedef DebugPrintCallback = void Function(String? message, {int? wrapWidth});

DebugPrintCallback buildDebugPrintCallback({
  required bool isReleaseMode,
  required DebugPrintCallback fallback,
}) {
  if (isReleaseMode) {
    return (String? _, {int? wrapWidth}) {};
  }

  return fallback;
}

Level buildRootLogLevel({required bool isReleaseMode}) {
  return isReleaseMode ? Level.OFF : Level.ALL;
}

void configureAppLogging() {
  debugPrint = buildDebugPrintCallback(
    isReleaseMode: kReleaseMode,
    fallback: debugPrintThrottled,
  );

  Logger.root.level = buildRootLogLevel(isReleaseMode: kReleaseMode);
  Logger.root.onRecord.listen((record) {
    debugPrint(
      '[${record.level.name}] ${record.time}: ${record.loggerName}: ${record.message}',
    );
  });
}
