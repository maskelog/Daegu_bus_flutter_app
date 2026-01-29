import 'package:flutter_test/flutter_test.dart';

import 'package:daegu_bus_app/models/bus_arrival.dart';
import 'package:daegu_bus_app/models/bus_info.dart';

void main() {
  test('BusArrival time text uses Korean labels', () {
    final arrival = BusArrival(
      routeNo: '101',
      routeId: 'R1',
      busInfoList: [
        BusInfo(
          busNumber: '101',
          currentStation: '정류장',
          remainingStops: '0',
          estimatedTime: '곧 도착',
        ),
      ],
    );

    expect(arrival.getFirstArrivalTimeText(), '곧 도착');
    expect(arrival.getSummaryText(), '곧 도착');
  });

  test('BusArrival out-of-service text uses Korean labels', () {
    final arrival = BusArrival(
      routeNo: '101',
      routeId: 'R1',
      busInfoList: [
        BusInfo(
          busNumber: '101',
          currentStation: '정류장',
          remainingStops: '0',
          estimatedTime: '운행종료',
        ),
      ],
    );

    expect(arrival.getFirstArrivalTimeText(), '운행 종료');
  });

  test('BusArrival minute text uses 분 suffix', () {
    final arrival = BusArrival(
      routeNo: '101',
      routeId: 'R1',
      busInfoList: [
        BusInfo(
          busNumber: '101',
          currentStation: '정류장',
          remainingStops: '0',
          estimatedTime: '5분',
        ),
      ],
    );

    expect(arrival.getFirstArrivalTimeText(), '5분');
  });
}
