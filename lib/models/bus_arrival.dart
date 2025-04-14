import 'bus_info.dart';

/// 버스 도착 정보 모델
class BusArrival {
  /// 노선 번호
  final String routeNo;

  /// 노선 ID
  final String routeId;

  /// 버스 정보 리스트
  final List<BusInfo> busInfoList;

  /// 진행 방향
  final String direction;

  /// 생성자
  BusArrival({
    required this.routeNo,
    required this.routeId,
    required this.busInfoList,
    this.direction = '',
  });

  /// JSON에서 객체 생성
  factory BusArrival.fromJson(Map<String, dynamic> json) {
    final List<dynamic> busList = json['busInfoList'] ?? [];

    return BusArrival(
      routeNo: json['routeNo'] ?? '',
      routeId: json['routeId'] ?? '',
      busInfoList: busList.map((info) => BusInfo.fromJson(info)).toList(),
      direction: json['direction'] ?? '',
    );
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'routeNo': routeNo,
      'routeId': routeId,
      'busInfoList': busInfoList.map((info) => info.toJson()).toList(),
      'direction': direction,
    };
  }

  /// 가장 빨리 도착하는 버스 정보
  BusInfo? get firstBus => busInfoList.isNotEmpty ? busInfoList[0] : null;

  /// 두 번째로 빨리 도착하는 버스 정보
  BusInfo? get secondBus => busInfoList.length > 1 ? busInfoList[1] : null;

  /// 버스가 있는지 확인
  bool get hasArrival => busInfoList.isNotEmpty;

  /// 저상 버스가 있는지 확인
  bool get hasLowFloorBus => busInfoList.any((bus) => bus.isLowFloor);

  /// 도착 정보에서 버스가 도착 예정인지 확인
  bool get hasArrivalInfo => busInfoList
      .any((bus) => !bus.isOutOfService && bus.getRemainingMinutes() > 0);

  /// 첫 번째 버스의 도착 시간 (분)
  int getFirstArrivalMinutes() {
    return firstBus?.getRemainingMinutes() ?? 0;
  }

  /// 첫 번째 버스의 도착 시간 문자열
  String getFirstArrivalTimeText() {
    final first = firstBus;
    if (first == null) {
      return '도착 정보 없음';
    }

    if (first.isOutOfService) {
      return '운행종료';
    }

    final minutes = first.getRemainingMinutes();
    if (minutes <= 0) {
      return '곧 도착';
    } else {
      return '$minutes분 후';
    }
  }

  /// 두 번째 버스의 도착 시간 문자열
  String getSecondArrivalTimeText() {
    final second = secondBus;
    if (second == null) {
      return '';
    }

    if (second.isOutOfService) {
      return '운행종료';
    }

    final minutes = second.getRemainingMinutes();
    if (minutes <= 0) {
      return '곧 도착';
    } else {
      return '$minutes분 후';
    }
  }

  /// 요약 정보 텍스트 (예: 금방 도착 / 3분, 15분 후)
  String getSummaryText() {
    if (!hasArrival) {
      return '도착 예정 버스 없음';
    }

    final first = getFirstArrivalTimeText();
    final second = getSecondArrivalTimeText();

    if (second.isEmpty) {
      return first;
    } else {
      return '$first, $second';
    }
  }

  /// 복사본 생성 with 일부 필드 변경
  BusArrival copyWith({
    String? routeNo,
    String? routeId,
    List<BusInfo>? busInfoList,
    String? direction,
  }) {
    return BusArrival(
      routeNo: routeNo ?? this.routeNo,
      routeId: routeId ?? this.routeId,
      busInfoList: busInfoList ?? this.busInfoList,
      direction: direction ?? this.direction,
    );
  }

  @override
  String toString() {
    return 'BusArrival{routeNo: $routeNo, direction: $direction, buses: ${busInfoList.length}}';
  }
}
