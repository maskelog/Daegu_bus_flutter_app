/// 요일 상수 정의
class Weekday {
  static const int monday = 1;
  static const int tuesday = 2;
  static const int wednesday = 3;
  static const int thursday = 4;
  static const int friday = 5;
  static const int saturday = 6;
  static const int sunday = 7;

  /// 요일 이름 가져오기
  static String getName(int weekday) {
    switch (weekday) {
      case monday:
        return '월';
      case tuesday:
        return '화';
      case wednesday:
        return '수';
      case thursday:
        return '목';
      case friday:
        return '금';
      case saturday:
        return '토';
      case sunday:
        return '일';
      default:
        return '?';
    }
  }
}

/// 자동 알람 모델 - 정해진 시간/요일에 자동으로 실행되는 알람
class AutoAlarm {
  /// 알람 고유 ID
  final String id;

  /// 버스 노선 번호
  final String routeNo;

  /// 정류장 이름
  final String stationName;

  /// 정류장 ID
  final String stationId;

  /// 노선 ID
  final String routeId;

  /// 알람 시간 (시)
  final int hour;

  /// 알람 시간 (분)
  final int minute;

  /// 반복 요일 (1-7, 월-일)
  final List<int> repeatDays;

  /// 주말 제외 여부
  final bool excludeWeekends;

  /// 공휴일 제외 여부
  final bool excludeHolidays;

  /// 활성화 여부
  final bool isActive;

  /// TTS 사용 여부
  final bool useTTS;

  /// 생성자
  AutoAlarm({
    required this.id,
    required this.routeNo,
    required this.stationName,
    required this.stationId,
    required this.routeId,
    required this.hour,
    required this.minute,
    required this.repeatDays,
    this.excludeWeekends = false,
    this.excludeHolidays = false,
    this.isActive = true,
    this.useTTS = true,
  });

  /// JSON에서 객체 생성
  factory AutoAlarm.fromJson(Map<String, dynamic> json) {
    // repeatDays가 문자열인 경우 처리 (레거시 데이터 지원)
    List<int> parsedRepeatDays;
    if (json['repeatDays'] is String) {
      parsedRepeatDays = (json['repeatDays'] as String)
          .split(',')
          .map((day) => int.tryParse(day.trim()) ?? 0)
          .where((day) => day > 0 && day <= 7)
          .toList();
    } else if (json['repeatDays'] is List) {
      parsedRepeatDays = (json['repeatDays'] as List)
          .map((day) => day is int ? day : int.tryParse(day.toString()) ?? 0)
          .where((day) => day > 0 && day <= 7)
          .toList();
    } else {
      parsedRepeatDays = [];
    }

    return AutoAlarm(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      routeNo: json['routeNo'] ?? '',
      stationName: json['stationName'] ?? '',
      stationId: json['stationId'] ?? '',
      routeId: json['routeId'] ?? '',
      hour: json['hour'] ?? 8,
      minute: json['minute'] ?? 0,
      repeatDays: parsedRepeatDays,
      excludeWeekends: json['excludeWeekends'] ?? false,
      excludeHolidays: json['excludeHolidays'] ?? false,
      isActive: json['isActive'] ?? true,
      useTTS: json['useTTS'] ?? true,
    );
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'routeNo': routeNo,
      'stationName': stationName,
      'stationId': stationId,
      'routeId': routeId,
      'hour': hour,
      'minute': minute,
      'repeatDays': repeatDays,
      'excludeWeekends': excludeWeekends,
      'excludeHolidays': excludeHolidays,
      'isActive': isActive,
      'useTTS': useTTS,
    };
  }

  /// 스케줄된 시간 [DateTime] 객체
  DateTime get scheduledTime {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  /// 시간 포맷 (HH:MM)
  String getFormattedTime() {
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  /// 요일 문자열 (예: 월,화,금)
  String getFormattedWeekdays() {
    return repeatDays.map((day) => Weekday.getName(day)).join(',');
  }

  /// 알람 설명 문자열
  String getDescription() {
    return '${getFormattedTime()} [${getFormattedWeekdays()}] $routeNo번 버스, $stationName';
  }

  /// 다음 알람 시간 계산
  DateTime? getNextAlarmTime() {
    final now = DateTime.now();

    // 오늘 요일이 반복 요일에 포함되는지 확인
    if (repeatDays.contains(now.weekday)) {
      // 주말 제외 옵션 확인
      if (excludeWeekends && (now.weekday == 6 || now.weekday == 7)) {
        // 주말이면 다음 평일 찾기
        return _findNextValidDay(now);
      }

      // TODO: 공휴일 체크 로직 필요

      // 오늘 알람 시간 생성
      final todayAlarm = DateTime(
        now.year,
        now.month,
        now.day,
        hour,
        minute,
      );

      // 아직 알람 시간이 지나지 않았으면 오늘 알람 반환
      if (todayAlarm.isAfter(now)) {
        return todayAlarm;
      }
    }

    return _findNextValidDay(now);
  }

  /// 다음 유효한 알람 요일 찾기
  DateTime? _findNextValidDay(DateTime now) {
    // 다음 요일 찾기
    for (int i = 1; i <= 7; i++) {
      final nextDate = now.add(Duration(days: i));

      // 반복 요일에 포함되는지 확인
      if (!repeatDays.contains(nextDate.weekday)) {
        continue;
      }

      // 주말 제외 옵션 확인
      if (excludeWeekends && (nextDate.weekday == 6 || nextDate.weekday == 7)) {
        continue;
      }

      // TODO: 공휴일 체크 로직 필요

      return DateTime(
        nextDate.year,
        nextDate.month,
        nextDate.day,
        hour,
        minute,
      );
    }

    // 반복 요일이 설정되어 있지 않은 경우
    return null;
  }

  /// 복사본 생성 with 일부 필드 변경
  AutoAlarm copyWith({
    String? id,
    String? routeNo,
    String? stationName,
    String? stationId,
    String? routeId,
    int? hour,
    int? minute,
    List<int>? repeatDays,
    bool? excludeWeekends,
    bool? excludeHolidays,
    bool? isActive,
    bool? useTTS,
  }) {
    return AutoAlarm(
      id: id ?? this.id,
      routeNo: routeNo ?? this.routeNo,
      stationName: stationName ?? this.stationName,
      stationId: stationId ?? this.stationId,
      routeId: routeId ?? this.routeId,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      repeatDays: repeatDays ?? this.repeatDays,
      excludeWeekends: excludeWeekends ?? this.excludeWeekends,
      excludeHolidays: excludeHolidays ?? this.excludeHolidays,
      isActive: isActive ?? this.isActive,
      useTTS: useTTS ?? this.useTTS,
    );
  }

  /// 알람 ID 생성
  int getAlarmId() {
    return "$routeNo.$stationId.$hour.$minute.${repeatDays.join('')}".hashCode;
  }

  @override
  String toString() {
    return 'AutoAlarm{id: $id, routeNo: $routeNo, stationName: $stationName, time: ${getFormattedTime()}, days: ${getFormattedWeekdays()}}';
  }
}
