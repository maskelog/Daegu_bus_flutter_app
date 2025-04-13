class AutoAlarm {
  final String id;
  final String routeNo;
  final String stationName;
  final String stationId;
  final String routeId;
  final int hour;
  final int minute;
  final List<int> repeatDays;
  final bool excludeWeekends;
  final bool excludeHolidays;
  final bool isActive;
  final bool useTTS;

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

  Map<String, dynamic> toJson() => {
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

  factory AutoAlarm.fromJson(Map<String, dynamic> json) {
    return AutoAlarm(
      id: json['id'] as String,
      routeNo: json['routeNo'] as String,
      stationName: json['stationName'] as String,
      stationId: json['stationId'] as String,
      routeId: json['routeId'] as String,
      hour: json['hour'] as int,
      minute: json['minute'] as int,
      repeatDays: List<int>.from(json['repeatDays'] as List),
      excludeWeekends: json['excludeWeekends'] as bool? ?? false,
      excludeHolidays: json['excludeHolidays'] as bool? ?? false,
      isActive: json['isActive'] as bool? ?? true,
      useTTS: json['useTTS'] as bool? ?? true,
    );
  }

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
}
