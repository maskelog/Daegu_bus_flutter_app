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
}
