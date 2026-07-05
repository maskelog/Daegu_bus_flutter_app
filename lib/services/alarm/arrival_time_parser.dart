import '../../main.dart' show logMessage, LogLevel;

/// 문자열 형태의 도착 시간("5분", "곧 도착", "운행종료" 등)을 분 단위 정수로 변환.
///
/// 반환 규칙: 곧 도착 계열 → 0, 운행 종료·출발 예정·파싱 불가 → -1.
int parseRemainingMinutes(dynamic estimatedTime) {
  if (estimatedTime == null) return -1;

  final String timeStr = estimatedTime.toString().trim();

  // 곧 도착 관련
  if (timeStr == '곧 도착' || timeStr == '전' || timeStr == '도착') return 0;

  // 운행 종료 관련
  if (timeStr == '운행종료' ||
      timeStr == '운행 종료' ||
      timeStr == '-' ||
      timeStr == '운행종료.') {
    return -1;
  }

  // 출발 예정 관련
  if (timeStr.contains('출발예정') || timeStr.contains('기점출발')) return -1;

  // 숫자 + '분' 형태 처리
  if (timeStr.contains('분')) {
    final numericValue = timeStr.replaceAll(RegExp(r'[^0-9]'), '');
    return numericValue.isEmpty ? -1 : int.tryParse(numericValue) ?? -1;
  }

  // 순수 숫자인 경우
  final numericValue = timeStr.replaceAll(RegExp(r'[^0-9]'), '');
  if (numericValue.isNotEmpty) {
    final minutes = int.tryParse(numericValue);
    if (minutes != null && minutes >= 0 && minutes <= 180) {
      // 3시간 이내만 유효
      return minutes;
    }
  }

  logMessage('⚠️ 파싱할 수 없는 도착 시간 형식: "$timeStr"', level: LogLevel.warning);
  return -1;
}
