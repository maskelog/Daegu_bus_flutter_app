import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daegu_bus_app/services/bus_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('searchStations completes all pending futures with latest results', () async {
    SharedPreferences.setMockInitialValues({});

    const channel = MethodChannel('com.example.daegu_bus_app/bus_api');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'searchStations') {
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final query = args['searchText'] as String;
        calls.add(query);
        return jsonEncode([
          {'bsId': query, 'bsNm': 'Test Station'},
        ]);
      }
      return null;
    });

    final service = BusApiService();

    final future1 = service.searchStations('a');
    final future2 = service.searchStations('ab');

    final results = await Future.wait([future1, future2])
        .timeout(const Duration(seconds: 2));

    expect(calls, ['ab']);
    expect(results[0].first.bsId, 'ab');
    expect(results[1].first.bsId, 'ab');

    messenger.setMockMethodCallHandler(channel, null);
  });
}
