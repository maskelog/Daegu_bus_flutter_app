import 'package:intl/intl.dart';

/// 버스 알람 데이터 모델
class AlarmData {
  /// 버스 번호
  final String busNo;

  /// 정류장 이름
  final String stationName;

  /// 남은 시간 (분)
  int _remainingMinutes;

  /// 노선 ID
  final String routeId;

  /// 알람 예정 시간
  final DateTime scheduledTime;

  /// 현재 버스 위치 (정류장 이름)
  String? currentStation;

  /// TTS 사용 여부
  final bool useTTS;

  /// 마지막 업데이트 시간
  DateTime _lastUpdated;

  /// 생성자
  AlarmData({
    required this.busNo,
    required this.stationName,
    required int remainingMinutes,
    required this.scheduledTime,
    this.routeId = '',
    this.currentStation,
    this.useTTS = true,
  })  : _remainingMinutes = remainingMinutes,
        _lastUpdated = DateTime.now();

  /// JSON에서 객체 생성
  factory AlarmData.fromJson(Map<String, dynamic> json) {
    return AlarmData(
      busNo: json['busNo'] ?? '',
      stationName: json['stationName'] ?? '',
      remainingMinutes: json['remainingMinutes'] ?? 0,
      routeId: json['routeId'] ?? '',
      scheduledTime: json['scheduledTime'] != null
          ? DateTime.parse(json['scheduledTime'])
          : DateTime.now()
              .add(Duration(minutes: json['remainingMinutes'] ?? 0)),
      currentStation: json['currentStation'],
      useTTS: json['useTTS'] ?? true,
    );
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'busNo': busNo,
      'stationName': stationName,
      'remainingMinutes': _remainingMinutes,
      'routeId': routeId,
      'scheduledTime': scheduledTime.toIso8601String(),
      'currentStation': currentStation,
      'useTTS': useTTS,
    };
  }

  /// 남은 시간 getter (실시간 계산)
  int getRemainingMinutes() {
    final now = DateTime.now();
    final difference = scheduledTime.difference(now);
    return difference.inMinutes > 0 ? difference.inMinutes : 0;
  }

  /// 현재 시간 기준 남은 시간
  int getCurrentArrivalMinutes() {
    final now = DateTime.now();
    final lastUpdateDifference = now.difference(_lastUpdated);
    final adjustedMinutes = _remainingMinutes - lastUpdateDifference.inMinutes;
    return adjustedMinutes > 0 ? adjustedMinutes : 0;
  }

  /// 남은 시간 업데이트
  void updateRemainingMinutes(int minutes) {
    _remainingMinutes = minutes;
    _lastUpdated = DateTime.now();
  }

  /// 포맷된 예정 시간 문자열
  String getFormattedScheduledTime() {
    return DateFormat('HH:mm').format(scheduledTime);
  }

  /// 알람 ID 생성 (해시코드 이용)
  int getAlarmId() {
    return "${busNo}_${stationName}_$routeId".hashCode;
  }

  /// 알람이 현재 시간 이후인지 확인
  bool isFutureAlarm() {
    return scheduledTime.isAfter(DateTime.now());
  }

  /// 알람이 곧 도착하는지 확인 (5분 이내)
  bool isArrivingSoon() {
    return getRemainingMinutes() <= 5;
  }

  /// 복사본 생성 with 일부 필드 변경
  AlarmData copyWith({
    String? busNo,
    String? stationName,
    int? remainingMinutes,
    String? routeId,
    DateTime? scheduledTime,
    String? currentStation,
    bool? useTTS,
  }) {
    return AlarmData(
      busNo: busNo ?? this.busNo,
      stationName: stationName ?? this.stationName,
      remainingMinutes: remainingMinutes ?? _remainingMinutes,
      routeId: routeId ?? this.routeId,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      currentStation: currentStation ?? this.currentStation,
      useTTS: useTTS ?? this.useTTS,
    );
  }

  /// 객체 동등성 비교
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is AlarmData &&
        other.busNo == busNo &&
        other.stationName == stationName &&
        other.routeId == routeId &&
        other.scheduledTime.isAtSameMomentAs(scheduledTime) &&
        other.useTTS == useTTS;
  }

  /// 해시코드
  @override
  int get hashCode {
    return busNo.hashCode ^
        stationName.hashCode ^
        routeId.hashCode ^
        scheduledTime.hashCode ^
        useTTS.hashCode;
  }

  /// 문자열 표현
  @override
  String toString() {
    return 'AlarmData{busNo: $busNo, stationName: $stationName, remainingMinutes: $_remainingMinutes, scheduledTime: $scheduledTime}';
  }
}
