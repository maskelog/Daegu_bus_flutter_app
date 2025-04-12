class BusInfo {
  final String estimatedTime;
  final String currentStation;
  final String remainingStations;

  BusInfo({
    required this.estimatedTime,
    required this.currentStation,
    required this.remainingStations,
  });

  factory BusInfo.fromBusInfoData(dynamic busInfoData) {
    return BusInfo(
      estimatedTime: busInfoData.estimatedTime,
      currentStation: busInfoData.currentStation,
      remainingStations: busInfoData.remainingStations,
    );
  }
}
