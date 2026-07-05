/// 정류장 이름 → stationId 매핑.
///
/// DB 조회가 불가능하거나 실패했을 때 쓰는 하드코딩 fallback.
/// 매칭 실패 시 [fallbackRouteId]를 그대로 반환한다.
String resolveStationIdFromName(String stationName, String fallbackRouteId) {
  const Map<String, String> stationMapping = {
    '새동네아파트앞': '7021024000',
    '새동네아파트건너': '7021023900',
    '칠성고가도로하단': '7021051300',
    '대구삼성창조캠퍼스3': '7021011000',
    '대구삼성창조캠퍼스': '7021011200',
    '동대구역': '7021052100',
    '동대구역건너': '7021052000',
    '경명여고건너': '7021024200',
    '경명여고': '7021024100',
  };

  // 정확한 매칭 시도
  if (stationMapping.containsKey(stationName)) {
    return stationMapping[stationName]!;
  }

  // 부분 매칭 시도
  for (var entry in stationMapping.entries) {
    if (stationName.contains(entry.key) || entry.key.contains(stationName)) {
      return entry.value;
    }
  }

  // 매칭 실패 시 fallback 사용
  return fallbackRouteId;
}
