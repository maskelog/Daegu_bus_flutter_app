class BusStop {
  final String id;
  final String name;
  final bool isFavorite;
  final String? wincId;
  final String? routeList;
  final String? distance;
  final String? ngisXPos;
  final String? ngisYPos;

  BusStop({
    required this.id,
    required this.name,
    required this.isFavorite,
    this.wincId,
    this.routeList,
    this.distance,
    this.ngisXPos,
    this.ngisYPos,
  });

  factory BusStop.fromJson(Map<String, dynamic> json) {
    return BusStop(
      id: json['bsId'] ?? '',
      name: json['bsNm'] ?? '',
      isFavorite: false, // 기본값은 즐겨찾기 아님
      wincId: json['wincId'],
      routeList: json['routeList'],
      distance: null,
      ngisXPos: json['ngisXPos'],
      ngisYPos: json['ngisYPos'],
    );
  }

  BusStop copyWith({
    String? id,
    String? name,
    bool? isFavorite,
    String? wincId,
    String? routeList,
    String? distance,
    String? ngisXPos,
    String? ngisYPos,
  }) {
    return BusStop(
      id: id ?? this.id,
      name: name ?? this.name,
      isFavorite: isFavorite ?? this.isFavorite,
      wincId: wincId ?? this.wincId,
      routeList: routeList ?? this.routeList,
      distance: distance ?? this.distance,
      ngisXPos: ngisXPos ?? this.ngisXPos,
      ngisYPos: ngisYPos ?? this.ngisYPos,
    );
  }

  // stations.json 데이터를 위한 메서드
  Map<String, dynamic> toJson() {
    return {
      'bsId': id,
      'bsNm': name,
      'wincId': wincId,
      'routeList': routeList,
      'ngisXPos': ngisXPos,
      'ngisYPos': ngisYPos,
    };
  }
}
