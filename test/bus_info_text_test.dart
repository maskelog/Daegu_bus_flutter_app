import 'package:flutter_test/flutter_test.dart';

import 'package:daegu_bus_app/models/bus_info.dart';

void main() {
  test('BusInfo parses Korean status strings correctly', () {
    final arrivingSoon = BusInfo(
      busNumber: '101',
      currentStation: '정류장',
      remainingStops: '0',
      estimatedTime: '곧 도착',
    );
    expect(arrivingSoon.getRemainingMinutes(), 0);
    expect(arrivingSoon.getRemainingTimeText(), '곧 도착');

    final outOfService = BusInfo(
      busNumber: '101',
      currentStation: '정류장',
      remainingStops: '0',
      estimatedTime: '운행종료',
    );
    expect(outOfService.getRemainingMinutes(), -1);
    expect(outOfService.getRemainingTimeText(), '운행 종료');

    final fiveMinutes = BusInfo(
      busNumber: '101',
      currentStation: '정류장',
      remainingStops: '0',
      estimatedTime: '5분',
    );
    expect(fiveMinutes.getRemainingMinutes(), 5);
    expect(fiveMinutes.getRemainingTimeText(), '5분');
  });

  test('BusInfo.fromJson flags out of service on 운행종료', () {
    final info = BusInfo.fromJson({
      'busNumber': '101',
      'currentStation': '정류장',
      'remainingStops': '0',
      'estimatedTime': '운행종료',
    });
    expect(info.isOutOfService, isTrue);
  });
}
