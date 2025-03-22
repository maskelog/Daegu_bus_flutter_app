// BusArrival 클래스
import 'package:flutter/material.dart';

class BusArrival {
  final String stationId;
  final String routeId;
  final String routeNo;
  final String destination;
  final List<BusInfo> buses;

  BusArrival({
    required this.stationId,
    required this.routeId,
    required this.routeNo,
    required this.destination,
    required this.buses,
  });

  // JSON 파싱 메서드 수정
  factory BusArrival.fromJson(Map<String, dynamic> json) {
    try {
      // 서버에서 오는 JSON 구조 로깅
      debugPrint('BusArrival.fromJson 입력: ${json.keys.join(', ')}');

      // 기본 필드 추출 (키 이름이 다를 수 있음)
      final routeId = json['routeId'] ?? json['id'] ?? '';
      final routeNo = json['routeNo'] ?? json['name'] ?? '';
      final destination = json['moveDir'] ?? json['forward'] ?? '';
      final stationId = json['stationId'] ?? ''; // 필요 시 외부에서 주입

      // 버스 목록 추출 (구조가 다를 수 있음)
      List<BusInfo> buses = [];

      // arrList가 있는 경우 (새로운 API 응답 형식)
      if (json.containsKey('arrList') && json['arrList'] is List) {
        buses = (json['arrList'] as List)
            .map((bus) => BusInfo.fromJson(bus))
            .toList();
      }
      // bus 키가 있는 경우 (이전 형식)
      else if (json.containsKey('bus') && json['bus'] is List) {
        buses =
            (json['bus'] as List).map((bus) => BusInfo.fromJson(bus)).toList();
      }

      return BusArrival(
        stationId: stationId,
        routeId: routeId,
        routeNo: routeNo,
        destination: destination,
        buses: buses,
      );
    } catch (e) {
      // 파싱 오류 상세 로깅
      debugPrint('BusArrival.fromJson 파싱 오류: $e');
      debugPrint('문제의 JSON: $json');

      // 빈 객체 반환하기보다 예외를 다시 던져서 호출자가 처리하도록 함
      rethrow;
    }
  }
}

// BusInfo 클래스
class BusInfo {
  final String busNumber;
  final bool isLowFloor;
  final String currentStation;
  final String remainingStops;
  final String arrivalTime;
  final bool isOutOfService;

  BusInfo({
    required this.busNumber,
    required this.isLowFloor,
    required this.currentStation,
    required this.remainingStops,
    required this.arrivalTime,
    this.isOutOfService = false,
  });

  // JSON 파싱 메서드 수정
  factory BusInfo.fromJson(Map<String, dynamic> json) {
    try {
      // 서버에서 오는 JSON 구조 로깅
      debugPrint('BusInfo.fromJson 입력: ${json.keys.join(', ')}');

      // 버스 번호 - 여러 가능한 키 확인
      final busNumber =
          json['vhcNo2'] ?? json['busNumber'] ?? json['버스번호'] ?? '';

      // 저상버스 여부
      bool isLowFloor = false;
      if (json.containsKey('busTCd2')) {
        isLowFloor = json['busTCd2'] == 'N';
      } else if (json.containsKey('isLowFloor')) {
        isLowFloor = json['isLowFloor'] == true;
      } else if (busNumber.contains('저상')) {
        isLowFloor = true;
      }

      // 현재 정류소
      final currentStation =
          json['bsNm'] ?? json['currentStation'] ?? json['현재정류소'] ?? '';

      // 남은 정류소 수
      String remainingStops = '';
      if (json.containsKey('bsGap')) {
        remainingStops = json['bsGap'].toString();
      } else if (json.containsKey('remainingStops')) {
        remainingStops = json['remainingStops'];
      } else if (json.containsKey('남은정류소')) {
        remainingStops = json['남은정류소'];
      }

      // 도착 예정 시간
      String arrivalTime = '';
      if (json.containsKey('arrState')) {
        arrivalTime = json['arrState'] ?? '';
      } else if (json.containsKey('arrivalTime')) {
        arrivalTime = json['arrivalTime'];
      } else if (json.containsKey('estimatedTime')) {
        arrivalTime = json['estimatedTime'];
      } else if (json.containsKey('도착예정소요시간')) {
        arrivalTime = json['도착예정소요시간'];
      }

      // 운행종료 여부
      bool isOutOfService = false;
      if (arrivalTime == '운행종료') {
        isOutOfService = true;
      } else if (json.containsKey('isOutOfService')) {
        isOutOfService = json['isOutOfService'] == true;
      }

      return BusInfo(
        busNumber: busNumber,
        isLowFloor: isLowFloor,
        currentStation: currentStation,
        remainingStops: remainingStops,
        arrivalTime: arrivalTime,
        isOutOfService: isOutOfService,
      );
    } catch (e) {
      // 파싱 오류 상세 로깅
      debugPrint('BusInfo.fromJson 파싱 오류: $e');
      debugPrint('문제의 JSON: $json');
      rethrow;
    }
  }

  int getRemainingMinutes() {
    if (isOutOfService) return 0;

    // arrivalTime에서 숫자만 추출
    final regex = RegExp(r'(\d+)');
    final match = regex.firstMatch(arrivalTime);

    if (match != null) {
      final minutes = int.tryParse(match.group(1) ?? '0') ?? 0;
      return minutes;
    } else if (arrivalTime.contains('곧') || arrivalTime.contains('잠시후')) {
      // '곧 도착' 또는 '잠시후' 같은 텍스트인 경우
      return 0;
    } else if (arrivalTime.contains('출발')) {
      // '출발' 텍스트가 있는 경우 (예: '출발 대기중')
      try {
        return int.tryParse(remainingStops) ?? 5;
      } catch (_) {
        return 5; // 기본값
      }
    }

    // 도착 시간 정보가 없거나 해석할 수 없는 경우
    return 0;
  }
}
