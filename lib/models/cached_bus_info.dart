import '../models/bus_info.dart';

/// 버스 정보의 캐시를 관리하는 모델 클래스
class CachedBusInfo {
  /// 도착까지 남은 시간(분)
  int remainingMinutes;

  /// 현재 버스 위치 (정류장 이름)
  String currentStation;

  /// 목적지 정류장 이름
  String stationName;

  /// 버스 번호
  String busNo;

  /// 노선 ID
  String routeId;

  /// 마지막 업데이트 시간
  DateTime _lastUpdated;

  CachedBusInfo({
    required this.remainingMinutes,
    required this.currentStation,
    required this.stationName,
    required this.busNo,
    required this.routeId,
    required DateTime lastUpdated,
  }) : _lastUpdated = lastUpdated;

  /// 마지막 업데이트 시간 getter
  DateTime get lastUpdated => _lastUpdated;

  /// BusInfo 객체로부터 CachedBusInfo 생성하는 팩토리 메서드
  factory CachedBusInfo.fromBusInfo({
    required BusInfo busInfo,
    required String busNumber,
    required String routeId,
  }) {
    return CachedBusInfo(
      remainingMinutes: busInfo.getRemainingMinutes(),
      currentStation: busInfo.currentStation,
      stationName: busInfo.currentStation, // 현재 정류장을 stationName으로 사용
      busNo: busNumber,
      routeId: routeId,
      lastUpdated: DateTime.now(),
    );
  }

  /// 현재 시간 기준으로 계산된 남은 시간 반환
  int getRemainingMinutes() {
    final now = DateTime.now();
    final difference = now.difference(_lastUpdated);
    return (remainingMinutes - difference.inMinutes).clamp(0, remainingMinutes);
  }

  /// 캐시된 정보가 최신인지 확인 (기본 10분 이내)
  bool isRecent({int withinMinutes = 10}) {
    return DateTime.now().difference(_lastUpdated).inMinutes < withinMinutes;
  }

  /// 데이터 갱신
  void updateData({
    int? remainingMinutes,
    String? currentStation,
    DateTime? lastUpdated,
  }) {
    if (remainingMinutes != null) this.remainingMinutes = remainingMinutes;
    if (currentStation != null) this.currentStation = currentStation;
    _lastUpdated = lastUpdated ?? DateTime.now();
  }

  /// 복사본 생성 with 일부 필드 변경
  CachedBusInfo copyWith({
    int? remainingMinutes,
    String? currentStation,
    String? stationName,
    String? busNo,
    String? routeId,
    DateTime? lastUpdated,
  }) {
    return CachedBusInfo(
      remainingMinutes: remainingMinutes ?? this.remainingMinutes,
      currentStation: currentStation ?? this.currentStation,
      stationName: stationName ?? this.stationName,
      busNo: busNo ?? this.busNo,
      routeId: routeId ?? this.routeId,
      lastUpdated: lastUpdated ?? _lastUpdated,
    );
  }

  /// 객체 동등성 비교
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is CachedBusInfo &&
        other.remainingMinutes == remainingMinutes &&
        other.currentStation == currentStation &&
        other.stationName == stationName &&
        other.busNo == busNo &&
        other.routeId == routeId;
  }

  /// 해시코드
  @override
  int get hashCode {
    return remainingMinutes.hashCode ^
        currentStation.hashCode ^
        stationName.hashCode ^
        busNo.hashCode ^
        routeId.hashCode;
  }

  /// 문자열 표현 오버라이드
  @override
  String toString() {
    return 'CachedBusInfo{busNo: $busNo, remainingMinutes: $remainingMinutes, currentStation: $currentStation, lastUpdated: $_lastUpdated}';
  }
}
