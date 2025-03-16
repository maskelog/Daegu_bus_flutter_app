class BusRoute {
  final String id;
  final String routeNo;
  final String? startPoint;
  final String? endPoint;
  final String? routeDescription;

  BusRoute({
    required this.id,
    required this.routeNo,
    this.startPoint,
    this.endPoint,
    this.routeDescription,
  });

  factory BusRoute.fromJson(Map<String, dynamic> json) {
    return BusRoute(
      id: json['routeId'] as String,
      routeNo: json['routeNo'] as String,
      startPoint: json['startPoint'] as String?,
      endPoint: json['endPoint'] as String?,
      routeDescription: json['routeTCd'] as String?,
    );
  }
}
