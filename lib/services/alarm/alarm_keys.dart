/// 알람·캐시 키의 표준 포맷.
///
/// 같은 키를 만드는 문자열 조립이 여러 파일에 흩어져 있으면 포맷이 어긋났을 때
/// 알람 상태 동기화가 조용히 깨진다. 키는 반드시 이 헬퍼로만 생성할 것.
class AlarmKeys {
  AlarmKeys._();

  /// 활성 알람 식별 키 (activeAlarmsMap 등).
  static String alarm(String busNo, String stationName, String routeId) =>
      '${busNo}_${stationName}_$routeId';

  /// 버스 정보 캐시 키 (cachedBusInfo).
  static String cache(String busNo, String routeId) => '${busNo}_$routeId';

  /// 취소 이벤트 중복 처리 방지 키 (processedEventTimestamps).
  static String cancellationEvent(
          String busNo, String stationName, String routeId) =>
      '${busNo}_${routeId}_${stationName}_cancellation';

  /// 네이티브 AlarmManager PendingIntent requestCode용 자동 알람 ID.
  ///
  /// Dart의 String.hashCode는 SDK 버전 간 안정성이 보장되지 않아,
  /// 결정적인 Java String.hashCode 알고리즘으로 고정한다.
  /// 네이티브(auto_alarm_store)에는 이 값이 그대로 저장·왕복되므로
  /// Kotlin 쪽에서 재계산할 일은 없어야 한다.
  static int autoAlarmNativeId(String alarmId) =>
      javaStringHashCode('auto_alarm_$alarmId');

  /// Java String.hashCode와 동일한 32-bit signed 해시.
  static int javaStringHashCode(String s) {
    var h = 0;
    for (final unit in s.codeUnits) {
      h = (h * 31 + unit) & 0xFFFFFFFF;
    }
    return h >= 0x80000000 ? h - 0x100000000 : h;
  }
}
