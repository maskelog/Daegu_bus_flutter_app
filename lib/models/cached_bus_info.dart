class CachedBusInfo {
  final String busNo;
  final String routeId;
  int remainingMinutes;
  String currentStation;
  DateTime lastUpdated;

  CachedBusInfo({
    required this.busNo,
    required this.routeId,
    required this.remainingMinutes,
    required this.currentStation,
    required this.lastUpdated,
  });

  int getRemainingMinutes() {
    // 마지막 업데이트로부터 경과 시간 계산 (분 단위)
    final elapsedMinutes = DateTime.now().difference(lastUpdated).inMinutes;

    // 분 단위로 경과 시간이 30초보다 클 경우에만 시간 차감
    if (elapsedMinutes > 0) {
      // 경과 시간이 지난 경우 차감 로직 적용
      final currentEstimate = remainingMinutes - elapsedMinutes;
      return currentEstimate > 0 ? currentEstimate : 0;
    } else {
      // 경과 시간이 1분 미만인 경우 원래 값 그대로 사용
      return remainingMinutes;
    }
  }
}
