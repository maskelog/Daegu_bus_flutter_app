class BusRoute {
  final String id;
  final String routeNo;
  final String startPoint;
  final String endPoint;
  final String routeDescription;

  BusRoute({
    required this.id,
    required this.routeNo,
    required this.startPoint,
    required this.endPoint,
    this.routeDescription = '',
  });

  factory BusRoute.fromJson(Map<String, dynamic> json) {
    return BusRoute(
      id: json['id'] ?? '',
      routeNo: json['routeNo'] ?? '',
      startPoint: json['startPoint'] ?? '',
      endPoint: json['endPoint'] ?? '',
      routeDescription: json['description'] ?? '',
    );
  }
}
