import '../services/bus_api_service.dart';

/// 버스 개별 정보 모델
class BusInfo {
  /// 버스 번호
  final String busNumber;

  /// 현재 정류장 위치
  final String currentStation;

  /// 남은 정류장 수
  final String remainingStops;

  /// 예상 도착 시간 (분)
  final String estimatedTime;

  /// 저상 버스 여부
  final bool isLowFloor;

  /// 운행종료 여부
  final bool isOutOfService;

  /// 생성자
  BusInfo({
    required this.busNumber,
    required this.currentStation,
    required this.remainingStops,
    required this.estimatedTime,
    this.isLowFloor = false,
    this.isOutOfService = false,
  });

  /// JSON에서 객체 생성
  factory BusInfo.fromJson(Map<String, dynamic> json) {
    // 운행 종료 확인 로직
    bool outOfService = false;
    String estTime = json['estimatedTime'] ?? '';

    if (estTime == '운행종료' ||
        json['isOutOfService'] == true ||
        json['busTCd3'] == '1') {
      outOfService = true;
    }

    return BusInfo(
      busNumber: json['busNumber'] ?? '',
      currentStation: json['currentStation'] ?? '',
      remainingStops: json['remainingStops'] ?? '0',
      estimatedTime: estTime,
      isLowFloor: json['isLowFloor'] == true || json['busTCd2'] == '1',
      isOutOfService: outOfService,
    );
  }

  /// BusInfoData에서 객체 생성
  factory BusInfo.fromBusInfoData(BusInfoData data) {
    // 버스 번호에서 저상버스 정보 추출
    bool isLowFloor = data.busNumber.contains('저상');
    String busNumber = data.busNumber.replaceAll(RegExp(r'\(저상\)|\(일반\)'), '');

    // 운행 종료 여부 확인
    bool isOutOfService = data.estimatedTime == '운행종료';

    return BusInfo(
      busNumber: busNumber,
      currentStation: data.currentStation,
      remainingStops: data.remainingStations,
      estimatedTime: data.estimatedTime,
      isLowFloor: isLowFloor,
      isOutOfService: isOutOfService,
    );
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'busNumber': busNumber,
      'currentStation': currentStation,
      'remainingStops': remainingStops,
      'estimatedTime': estimatedTime,
      'isLowFloor': isLowFloor,
      'isOutOfService': isOutOfService,
    };
  }

  /// 남은 시간(분) 계산
  int getRemainingMinutes() {
    if (isOutOfService) return 0;

    // "전" 또는 "곧 도착", "진입" 같은 특수 케이스
    if (estimatedTime.contains('전') ||
        estimatedTime.contains('곧 도착') ||
        estimatedTime.contains('진입') ||
        estimatedTime.trim() == '0' ||
        estimatedTime.trim() == '0분') {
      return 0;
    }

    // 숫자로 파싱 가능한 경우 (예: "9분", "12분")
    final numberMatch = RegExp(r'(\d+)분?').firstMatch(estimatedTime);
    if (numberMatch != null) {
      try {
        return int.parse(numberMatch.group(1)!);
      } catch (_) {
        // 파싱 오류 시 예외 처리
      }
    }

    // estimatedTime이 순수한 숫자인 경우 (네이티브에서 전달된 값)
    try {
      if (estimatedTime.trim().isNotEmpty &&
          int.tryParse(estimatedTime.trim()) != null) {
        return int.parse(estimatedTime.trim());
      }
    } catch (_) {
      // 파싱 오류 시 예외 처리
    }

    // 남은 정류장 수를 기준으로 대략적인 시간 추정 (1정류장 = 약 2분)
    try {
      final stops = int.parse(remainingStops.replaceAll(RegExp(r'[^0-9]'), ''));
      return stops * 2;
    } catch (_) {
      // 파싱 오류 시 예외 처리
    }

    return 0;
  }

  /// 남은 시간 텍스트
  String getRemainingTimeText() {
    if (isOutOfService) {
      return '운행종료';
    }

    final minutes = getRemainingMinutes();
    if (minutes <= 0) {
      return '곧 도착';
    } else {
      return '$minutes분 후';
    }
  }

  /// 저상 버스 표시
  String getLowFloorText() {
    return isLowFloor ? '[저상]' : '';
  }

  /// 복사본 생성 with 일부 필드 변경
  BusInfo copyWith({
    String? busNumber,
    String? currentStation,
    String? remainingStops,
    String? estimatedTime,
    bool? isLowFloor,
    bool? isOutOfService,
  }) {
    return BusInfo(
      busNumber: busNumber ?? this.busNumber,
      currentStation: currentStation ?? this.currentStation,
      remainingStops: remainingStops ?? this.remainingStops,
      estimatedTime: estimatedTime ?? this.estimatedTime,
      isLowFloor: isLowFloor ?? this.isLowFloor,
      isOutOfService: isOutOfService ?? this.isOutOfService,
    );
  }

  /// 객체 동등성 비교
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is BusInfo &&
        other.busNumber == busNumber &&
        other.currentStation == currentStation &&
        other.remainingStops == remainingStops &&
        other.estimatedTime == estimatedTime &&
        other.isLowFloor == isLowFloor &&
        other.isOutOfService == isOutOfService;
  }

  /// 해시코드
  @override
  int get hashCode {
    return busNumber.hashCode ^
        currentStation.hashCode ^
        remainingStops.hashCode ^
        estimatedTime.hashCode ^
        isLowFloor.hashCode ^
        isOutOfService.hashCode;
  }

  @override
  String toString() {
    return 'BusInfo{busNumber: $busNumber, remainingTime: ${getRemainingMinutes()}분, currentStation: $currentStation, isLowFloor: $isLowFloor}';
  }
}
