import '../../main.dart' show logMessage, LogLevel;

/// 자동 알람 JSON 데이터의 필수 필드 검증.
bool validateAutoAlarmFields(Map<String, dynamic> data) {
  final requiredFields = [
    'routeNo',
    'stationId',
    'routeId',
    'stationName',
    'repeatDays',
  ];
  // scheduledTime 또는 hour/minute 중 하나는 필수
  if (data['scheduledTime'] == null &&
      (data['hour'] == null || data['minute'] == null)) {
    logMessage(
      '! 자동 알람 데이터 필수 필드 누락: scheduledTime 또는 hour/minute',
      level: LogLevel.error,
    );
    return false;
  }

  final missingFields = requiredFields
      .where(
        (field) =>
            data[field] == null ||
            (data[field] is String && data[field].isEmpty) ||
            (data[field] is List && (data[field] as List).isEmpty),
      )
      .toList();
  if (missingFields.isNotEmpty) {
    logMessage(
      '! 자동 알람 데이터 필수 필드 누락: ${missingFields.join(", ")}',
      level: LogLevel.error,
    );
    return false;
  }
  return true;
}
