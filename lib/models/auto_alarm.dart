class AutoAlarm {
  final String id;
  final int hour;
  final int minute;
  final String stationId;
  final String stationName;
  final String routeId;
  final String routeNo;
  final List<int> repeatDays;
  final bool excludeWeekends;
  final bool excludeHolidays;
  final bool isActive;
  final bool useTTS;

  const AutoAlarm({
    required this.id,
    required this.hour,
    required this.minute,
    required this.stationId,
    required this.stationName,
    required this.routeId,
    required this.routeNo,
    required this.repeatDays,
    required this.excludeWeekends,
    required this.excludeHolidays,
    required this.isActive,
    this.useTTS = true,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'hour': hour,
        'minute': minute,
        'stationId': stationId,
        'stationName': stationName,
        'routeId': routeId,
        'routeNo': routeNo,
        'repeatDays': repeatDays,
        'excludeWeekends': excludeWeekends,
        'excludeHolidays': excludeHolidays,
        'isActive': isActive,
        'useTTS': useTTS,
      };

  factory AutoAlarm.fromJson(Map<String, dynamic> json) {
    return AutoAlarm(
      id: json['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
      hour: json['hour'] ?? 7,
      minute: json['minute'] ?? 0,
      stationId: json['stationId'] ?? '',
      stationName: json['stationName'] ?? '',
      routeId: json['routeId'] ?? '',
      routeNo: json['routeNo'] ?? '',
      repeatDays: json['repeatDays'] != null
          ? List<int>.from(json['repeatDays'])
          : [1, 2, 3, 4, 5],
      excludeWeekends: json['excludeWeekends'] ?? true,
      excludeHolidays: json['excludeHolidays'] ?? true,
      isActive: json['isActive'] ?? true,
      useTTS: json['useTTS'] ?? true,
    );
  }

  AutoAlarm copyWith({
    String? id,
    int? hour,
    int? minute,
    String? stationId,
    String? stationName,
    String? routeId,
    String? routeNo,
    List<int>? repeatDays,
    bool? excludeWeekends,
    bool? excludeHolidays,
    bool? isActive,
    bool? useTTS,
  }) {
    return AutoAlarm(
      id: id ?? this.id,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      stationId: stationId ?? this.stationId,
      stationName: stationName ?? this.stationName,
      routeId: routeId ?? this.routeId,
      routeNo: routeNo ?? this.routeNo,
      repeatDays: repeatDays ?? this.repeatDays,
      excludeWeekends: excludeWeekends ?? this.excludeWeekends,
      excludeHolidays: excludeHolidays ?? this.excludeHolidays,
      isActive: isActive ?? this.isActive,
      useTTS: useTTS ?? this.useTTS,
    );
  }
}
