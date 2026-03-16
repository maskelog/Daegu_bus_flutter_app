class FavoriteBus {
  final String stationId;
  final String stationName;
  final String routeId;
  final String routeNo;

  const FavoriteBus({
    required this.stationId,
    required this.stationName,
    required this.routeId,
    required this.routeNo,
  });

  FavoriteBus copyWith({
    String? stationId,
    String? stationName,
    String? routeId,
    String? routeNo,
  }) {
    return FavoriteBus(
      stationId: stationId ?? this.stationId,
      stationName: stationName ?? this.stationName,
      routeId: routeId ?? this.routeId,
      routeNo: routeNo ?? this.routeNo,
    );
  }

  String get key => '$stationId|$routeId';

  factory FavoriteBus.fromJson(Map<String, dynamic> json) {
    return FavoriteBus(
      stationId: json['stationId'] ?? '',
      stationName: json['stationName'] ?? '',
      routeId: json['routeId'] ?? '',
      routeNo: json['routeNo'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'stationId': stationId,
      'stationName': stationName,
      'routeId': routeId,
      'routeNo': routeNo,
    };
  }
}
