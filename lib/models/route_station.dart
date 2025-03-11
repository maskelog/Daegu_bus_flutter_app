class RouteStation {
  final String stationId;
  final String stationName;
  final int sequenceNo;
  final String direction;

  RouteStation({
    required this.stationId,
    required this.stationName,
    required this.sequenceNo,
    required this.direction,
  });

  factory RouteStation.fromJson(Map<String, dynamic> json) {
    return RouteStation(
      stationId: json['stationId'] ?? '',
      stationName: json['stationName'] ?? '',
      sequenceNo: json['sequenceNo'] ?? 0,
      direction: json['direction'] ?? '',
    );
  }
}
