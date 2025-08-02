import 'package:flutter/foundation.dart';

class DebugHelper {
  static void logInfoWindowState(String state) {
    if (kDebugMode) {
      print('🔍 [InfoWindow Debug] $state');
    }
  }

  static void logMapEvent(String event, Map<String, dynamic> data) {
    if (kDebugMode) {
      print('🗺️ [Map Event] $event: $data');
    }
  }

  static void logBorderTest(String testName, bool hasBorder) {
    if (kDebugMode) {
      print(
          '🎨 [Border Test] $testName: ${hasBorder ? "❌ Border detected" : "✅ No border"}');
    }
  }

  static void logPerformance(String operation, int milliseconds) {
    if (kDebugMode) {
      print('⚡ [Performance] $operation: ${milliseconds}ms');
    }
  }
}
