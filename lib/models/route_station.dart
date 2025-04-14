/// 버스 노선의 정류장 정보 모델
class RouteStation {
  /// 정류장 ID
  final String stationId;

  /// 정류장 이름
  final String stationName;

  /// 노선 내 순서 번호
  final int sequenceNo;

  /// 진행 방향
  final String direction;

  /// 위도
  final double? latitude;

  /// 경도
  final double? longitude;

  /// 정류장 유형
  final StationType stationType;

  /// 생성자
  RouteStation({
    required this.stationId,
    required this.stationName,
    required this.sequenceNo,
    this.direction = '',
    this.latitude,
    this.longitude,
    this.stationType = StationType.normal,
  });

  /// JSON에서 객체 생성
  factory RouteStation.fromJson(Map<String, dynamic> json) {
    // 정류장 유형 처리
    StationType type = StationType.normal;
    if (json.containsKey('stationType')) {
      switch (json['stationType']) {
        case 'start':
          type = StationType.start;
          break;
        case 'end':
          type = StationType.end;
          break;
        case 'main':
          type = StationType.main;
          break;
      }
    } else if (json['sequenceNo'] == 1) {
      type = StationType.start;
    }

    return RouteStation(
      stationId: json['stationId'] ?? '',
      stationName: json['stationName'] ?? '',
      sequenceNo: json['sequenceNo'] is int
          ? json['sequenceNo']
          : int.tryParse(json['sequenceNo']?.toString() ?? '0') ?? 0,
      direction: json['direction'] ?? '',
      latitude: json['lat'] is double
          ? json['lat']
          : double.tryParse(json['lat']?.toString() ?? '0'),
      longitude: json['lng'] is double
          ? json['lng']
          : double.tryParse(json['lng']?.toString() ?? '0'),
      stationType: type,
    );
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    String typeString;
    switch (stationType) {
      case StationType.start:
        typeString = 'start';
        break;
      case StationType.end:
        typeString = 'end';
        break;
      case StationType.main:
        typeString = 'main';
        break;
      default:
        typeString = 'normal';
    }

    return {
      'stationId': stationId,
      'stationName': stationName,
      'sequenceNo': sequenceNo,
      'direction': direction,
      'lat': latitude,
      'lng': longitude,
      'stationType': typeString,
    };
  }

  /// 복사본 생성 with 일부 필드 변경
  RouteStation copyWith({
    String? stationId,
    String? stationName,
    int? sequenceNo,
    String? direction,
    double? latitude,
    double? longitude,
    StationType? stationType,
  }) {
    return RouteStation(
      stationId: stationId ?? this.stationId,
      stationName: stationName ?? this.stationName,
      sequenceNo: sequenceNo ?? this.sequenceNo,
      direction: direction ?? this.direction,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      stationType: stationType ?? this.stationType,
    );
  }

  /// 시작 정류장인지 확인
  bool get isStartStation =>
      stationType == StationType.start || sequenceNo == 1;

  /// 종점 정류장인지 확인
  bool get isEndStation => stationType == StationType.end;

  /// 주요 정류장인지 확인
  bool get isMainStation => stationType == StationType.main;

  @override
  String toString() {
    String typeStr = '';
    if (isStartStation) typeStr = '[출발]';
    if (isEndStation) typeStr = '[종점]';
    if (isMainStation) typeStr = '[주요]';

    return 'RouteStation{$sequenceNo: $stationName $typeStr}';
  }

  /// 동등성 비교 (ID와 순서 기준)
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RouteStation &&
        other.stationId == stationId &&
        other.sequenceNo == sequenceNo;
  }

  @override
  int get hashCode => stationId.hashCode ^ sequenceNo.hashCode;
}

/// 정류장 유형 열거형
enum StationType {
  /// 일반 정류장
  normal,

  /// 시작 정류장
  start,

  /// 종점 정류장
  end,

  /// 주요 정류장
  main,
}
