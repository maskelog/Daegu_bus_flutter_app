class RouteStation {
  final String bsId; // stationId 대신 사용
  final String bsNm; // stationName 대신 사용
  final double lat;
  final double lng;
  final int sequenceNo;

  RouteStation({
    required this.bsId,
    required this.bsNm,
    required this.lat,
    required this.lng,
    required this.sequenceNo,
  });

  factory RouteStation.fromJson(Map<String, dynamic> json) {
    return RouteStation(
      bsId: json['bsId'] as String,
      bsNm: json['bsNm'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      sequenceNo: (json['seq'] as num).toInt(),
    );
  }
}
