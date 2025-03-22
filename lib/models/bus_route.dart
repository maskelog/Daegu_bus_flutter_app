class BusRoute {
  final String id;
  final String routeNo;
  final String? routeTp;
  final String? startPoint;
  final String? endPoint;
  final String? routeDescription;

  BusRoute({
    required this.id,
    required this.routeNo,
    this.routeTp,
    this.startPoint,
    this.endPoint,
    this.routeDescription,
  });

  factory BusRoute.fromJson(Map<dynamic, dynamic> json) {
    final Map<String, dynamic> safeJson = {};
    json.forEach((key, value) {
      if (key != null) {
        safeJson[key.toString()] = value;
      }
    });

    return BusRoute(
      id: safeJson['id']?.toString() ?? '',
      routeNo: safeJson['routeNo']?.toString() ?? '',
      routeTp: safeJson['routeTp']?.toString(),
      startPoint: safeJson['startPoint']?.toString() ?? '',
      endPoint: safeJson['endPoint']?.toString() ?? '',
      routeDescription: safeJson['routeDescription']?.toString(),
    );
  }
}
