// BusStop 모델 클래스 수정

import 'dart:convert';

class BusStop {
  final String id; // bsId (기존 id)
  final String name;
  final bool isFavorite;
  final String? wincId; // 일부 API에서 사용하는 ID (현재 wincId가 bsId와 같을 수 있음)
  final String? stationId; // API 호출에 사용되는 실제 stationId (7로 시작하는 10자리 형식)
  final double? ngisXPos;
  final double? ngisYPos;
  final String? routeList;
  final double? distance;

  BusStop({
    required this.id,
    required this.name,
    this.isFavorite = false,
    this.wincId,
    this.stationId,
    this.ngisXPos,
    this.ngisYPos,
    this.routeList,
    this.distance,
  });

  factory BusStop.fromJson(Map<String, dynamic> json) {
    return BusStop(
      id: json['id'] as String,
      name: json['name'] as String,
      isFavorite: json['isFavorite'] as bool? ?? false,
      wincId: json['wincId'] as String?,
      stationId: json['stationId'] as String?,
      ngisXPos: json['ngisXPos'] != null
          ? (json['ngisXPos'] as num).toDouble()
          : null,
      ngisYPos: json['ngisYPos'] != null
          ? (json['ngisYPos'] as num).toDouble()
          : null,
      routeList: json['routeList'] != null
          ? json['routeList'] is String
              ? json['routeList'] as String
              : jsonEncode(json['routeList'])
          : null,
      distance: json['distance'] != null
          ? (json['distance'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isFavorite': isFavorite,
      'wincId': wincId,
      'stationId': stationId,
      'ngisXPos': ngisXPos,
      'ngisYPos': ngisYPos,
      'routeList': routeList,
      'distance': distance,
    };
  }

  BusStop copyWith({
    String? id,
    String? name,
    bool? isFavorite,
    String? wincId,
    String? stationId,
    double? ngisXPos,
    double? ngisYPos,
    String? routeList,
    double? distance,
  }) {
    return BusStop(
      id: id ?? this.id,
      name: name ?? this.name,
      isFavorite: isFavorite ?? this.isFavorite,
      wincId: wincId ?? this.wincId,
      stationId: stationId ?? this.stationId,
      ngisXPos: ngisXPos ?? this.ngisXPos,
      ngisYPos: ngisYPos ?? this.ngisYPos,
      routeList: routeList ?? this.routeList,
      distance: distance ?? this.distance,
    );
  }
}
