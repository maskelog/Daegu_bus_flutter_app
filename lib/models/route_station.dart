class RouteStation {
  final String bsId;
  final String bsNm;
  final int sequenceNo;
  final double lat;
  final double lng;

  RouteStation({
    required this.bsId,
    required this.bsNm,
    required this.sequenceNo,
    required this.lat,
    required this.lng,
  });

  factory RouteStation.fromJson(Map<dynamic, dynamic> json) {
    // 안전한 타입 변환을 위해 새 Map 생성
    final Map<String, dynamic> safeJson = {};
    json.forEach((key, value) {
      if (key != null) {
        safeJson[key.toString()] = value;
      }
    });

    return RouteStation(
      bsId: safeJson['stationId']?.toString() ?? '',
      bsNm: safeJson['stationName']?.toString() ?? '',
      sequenceNo: safeJson['sequenceNo'] is int
          ? safeJson['sequenceNo']
          : int.tryParse(safeJson['sequenceNo']?.toString() ?? '0') ?? 0,
      lat: safeJson['lat'] is double
          ? safeJson['lat']
          : double.tryParse(safeJson['lat']?.toString() ?? '0') ?? 0.0,
      lng: safeJson['lng'] is double
          ? safeJson['lng']
          : double.tryParse(safeJson['lng']?.toString() ?? '0') ?? 0.0,
    );
  }
}
