class BusStop {
  final String id;
  final String name;
  final String? ngisXPos;
  final String? ngisYPos;
  final double? latitude;
  final double? longitude;
  final bool isFavorite;
  final String? routeList;
  final String? wincId;
  final double? distance;

  BusStop({
    required this.id,
    required this.name,
    this.ngisXPos,
    this.ngisYPos,
    this.latitude,
    this.longitude,
    this.isFavorite = false,
    this.routeList,
    this.wincId,
    this.distance,
  });

  BusStop copyWith({
    String? id,
    String? name,
    String? ngisXPos,
    String? ngisYPos,
    double? latitude,
    double? longitude,
    bool? isFavorite,
    String? routeList,
    String? wincId,
    double? distance,
  }) {
    return BusStop(
      id: id ?? this.id,
      name: name ?? this.name,
      ngisXPos: ngisXPos ?? this.ngisXPos,
      ngisYPos: ngisYPos ?? this.ngisYPos,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isFavorite: isFavorite ?? this.isFavorite,
      routeList: routeList ?? this.routeList,
      wincId: wincId ?? this.wincId,
      distance: distance ?? this.distance,
    );
  }

  factory BusStop.fromJson(Map<String, dynamic> json) {
    // distance 필드 처리 개선
    double? distanceValue;
    if (json['distance'] != null) {
      if (json['distance'] is double) {
        distanceValue = json['distance'] as double;
      } else if (json['distance'] is int) {
        distanceValue = (json['distance'] as int).toDouble();
      } else if (json['distance'] is String) {
        distanceValue = double.tryParse(json['distance'] as String);
      }
    }

    return BusStop(
      id: json['id'] as String? ?? json['bsId'] as String? ?? '',
      name: json['name'] as String? ?? json['stop_name'] as String? ?? '',
      ngisXPos: json['ngisXPos']?.toString(),
      ngisYPos: json['ngisYPos']?.toString(),
      latitude: json['latitude'] != null
          ? (json['latitude'] as num).toDouble()
          : null,
      longitude: json['longitude'] != null
          ? (json['longitude'] as num).toDouble()
          : null,
      isFavorite: json['isFavorite'] as bool? ?? false,
      routeList: json['routeList']?.toString(),
      wincId: json['wincId'] as String?,
      distance: distanceValue,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'ngisXPos': ngisXPos,
      'ngisYPos': ngisYPos,
      'latitude': latitude,
      'longitude': longitude,
      'isFavorite': isFavorite,
      'routeList': routeList,
      'wincId': wincId,
      'distance': distance,
    };
  }
}
