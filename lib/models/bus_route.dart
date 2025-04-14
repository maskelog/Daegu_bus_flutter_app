/// 버스 노선 유형
enum BusRouteType {
  /// 일반버스
  regular,

  /// 좌석버스
  seat,

  /// 급행버스
  express,

  /// 마을버스
  village,

  /// 광역버스
  metropolitan,

  /// 기타
  other
}

/// 버스 노선 모델
class BusRoute {
  /// 노선 ID
  final String id;

  /// 노선 번호
  final String routeNo;

  /// 노선 유형 코드
  final String routeTp;

  /// 출발지
  final String startPoint;

  /// 도착지
  final String endPoint;

  /// 노선 설명
  final String? routeDescription;

  /// 생성자
  BusRoute({
    required this.id,
    required this.routeNo,
    required this.routeTp,
    required this.startPoint,
    required this.endPoint,
    this.routeDescription,
  });

  /// JSON에서 객체 생성
  factory BusRoute.fromJson(Map<String, dynamic> json) {
    return BusRoute(
      id: json['id'] ?? '',
      routeNo: json['routeNo'] ?? '',
      routeTp: json['routeTp'] ?? '',
      startPoint: json['startPoint'] ?? '',
      endPoint: json['endPoint'] ?? '',
      routeDescription: json['routeDescription'],
    );
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'routeNo': routeNo,
      'routeTp': routeTp,
      'startPoint': startPoint,
      'endPoint': endPoint,
      'routeDescription': routeDescription,
    };
  }

  /// 노선 유형 가져오기
  BusRouteType getRouteType() {
    switch (routeTp) {
      case '1':
        return BusRouteType.regular;
      case '2':
        return BusRouteType.seat;
      case '3':
        return BusRouteType.express;
      case '4':
        return BusRouteType.village;
      case '5':
        return BusRouteType.metropolitan;
      default:
        return BusRouteType.other;
    }
  }

  /// 노선 유형 이름
  String getRouteTypeName() {
    switch (getRouteType()) {
      case BusRouteType.regular:
        return '일반';
      case BusRouteType.seat:
        return '좌석';
      case BusRouteType.express:
        return '급행';
      case BusRouteType.village:
        return '마을';
      case BusRouteType.metropolitan:
        return '광역';
      case BusRouteType.other:
        return '기타';
    }
  }

  /// 노선 색상 코드
  int getRouteColor() {
    switch (getRouteType()) {
      case BusRouteType.regular:
        return 0xFF3F51B5; // 파란색
      case BusRouteType.seat:
        return 0xFF4CAF50; // 녹색
      case BusRouteType.express:
        return 0xFFFF5722; // 주황색
      case BusRouteType.village:
        return 0xFF9C27B0; // 보라색
      case BusRouteType.metropolitan:
        return 0xFF607D8B; // 회색
      case BusRouteType.other:
        return 0xFF795548; // 갈색
    }
  }

  /// 노선 요약 정보
  String getSummary() {
    final type = getRouteTypeName();
    return '$routeNo번 ($type) - $startPoint → $endPoint';
  }

  /// 복사본 생성 with 일부 필드 변경
  BusRoute copyWith({
    String? id,
    String? routeNo,
    String? routeTp,
    String? startPoint,
    String? endPoint,
    String? routeDescription,
  }) {
    return BusRoute(
      id: id ?? this.id,
      routeNo: routeNo ?? this.routeNo,
      routeTp: routeTp ?? this.routeTp,
      startPoint: startPoint ?? this.startPoint,
      endPoint: endPoint ?? this.endPoint,
      routeDescription: routeDescription ?? this.routeDescription,
    );
  }

  @override
  String toString() {
    return 'BusRoute{routeNo: $routeNo, type: ${getRouteTypeName()}, $startPoint → $endPoint}';
  }

  /// 동등성 비교 (ID 기준)
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BusRoute && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
