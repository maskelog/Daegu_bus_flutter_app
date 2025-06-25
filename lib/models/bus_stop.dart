import 'dart:convert';
import 'package:flutter/material.dart';

/// 버스 정류장 모델
class BusStop {
  /// 정류장 ID
  final String id;

  /// 정류장 이름
  final String name;

  /// 즐겨찾기 여부
  final bool isFavorite;

  /// WincID (정류장의 다른 식별자)
  final String? wincId;

  /// API 호출용 StationID
  final String? stationId;

  /// 위도
  final double? latitude;

  /// 경도
  final double? longitude;

  /// 현재 위치로부터의 거리 (미터)
  final double? distance;

  /// 노선 목록
  final List<String>? routeList;

  /// 생성자
  BusStop({
    required this.id,
    required this.name,
    this.isFavorite = false,
    this.wincId,
    this.stationId,
    this.latitude,
    this.longitude,
    this.distance,
    this.routeList,
  });

  /// JSON에서 객체 생성
  factory BusStop.fromJson(Map<String, dynamic> json) {
    // 좌표 변환 (NGIS 좌표계 -> 위도/경도)
    double? lat, lng;

    try {
      if (json.containsKey('ngisYPos') && json['ngisYPos'] != null) {
        lat = double.tryParse(json['ngisYPos'].toString());
      } else if (json.containsKey('latitude') && json['latitude'] != null) {
        lat = double.tryParse(json['latitude'].toString());
      }

      if (json.containsKey('ngisXPos') && json['ngisXPos'] != null) {
        lng = double.tryParse(json['ngisXPos'].toString());
      } else if (json.containsKey('longitude') && json['longitude'] != null) {
        lng = double.tryParse(json['longitude'].toString());
      }
    } catch (e) {
      debugPrint('좌표 파싱 오류: $e');
    }

    // 노선 목록 처리
    List<String>? routes;
    if (json.containsKey('routeList')) {
      if (json['routeList'] is List) {
        routes = (json['routeList'] as List)
            .map((route) => route.toString())
            .toList();
      } else if (json['routeList'] is String) {
        try {
          final parsed = jsonDecode(json['routeList'] as String);
          if (parsed is List) {
            routes = parsed.map((route) => route.toString()).toList();
          }
        } catch (e) {
          debugPrint('노선 목록 파싱 오류: $e');
        }
      }
    }

    return BusStop(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      isFavorite: json['isFavorite'] == true,
      wincId: json['wincId'],
      stationId: json['stationId'],
      latitude: lat,
      longitude: lng,
      distance: json.containsKey('distance')
          ? double.tryParse(json['distance'].toString())
          : null,
      routeList: routes,
    );
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'isFavorite': isFavorite,
      'wincId': wincId,
      'stationId': stationId,
      'latitude': latitude, // latitude로 통일
      'longitude': longitude, // longitude로 통일
      'distance': distance,
      'routeList': routeList,
    };
  }

  /// 효과적인 API 호출을 위한 정류장 ID 반환
  String getEffectiveStationId() {
    // 우선순위: stationId > id > wincId
    if (stationId != null && stationId!.isNotEmpty) {
      return stationId!;
    } else if (id.startsWith('7') && id.length == 10) {
      return id;
    } else if (wincId != null && wincId!.isNotEmpty) {
      return wincId!;
    } else {
      return id;
    }
  }

  /// 거리 포맷팅 (미터 or 킬로미터)
  String getFormattedDistance() {
    if (distance == null) {
      return '거리 정보 없음';
    }

    if (distance! < 1000) {
      return '${distance!.toInt()}m';
    } else {
      return '${(distance! / 1000).toStringAsFixed(1)}km';
    }
  }

  /// 정류장 표시 이름 (정류장 번호 포함)
  String getDisplayName() {
    if (wincId != null && wincId!.isNotEmpty) {
      return '$name ($wincId)';
    } else {
      return name;
    }
  }

  /// 복사본 생성 with 일부 필드 변경
  BusStop copyWith({
    String? id,
    String? name,
    bool? isFavorite,
    String? wincId,
    String? stationId,
    double? latitude,
    double? longitude,
    double? distance,
    List<String>? routeList,
  }) {
    return BusStop(
      id: id ?? this.id,
      name: name ?? this.name,
      isFavorite: isFavorite ?? this.isFavorite,
      wincId: wincId ?? this.wincId,
      stationId: stationId ?? this.stationId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      distance: distance ?? this.distance,
      routeList: routeList ?? this.routeList,
    );
  }

  /// 동등성 비교 (ID 기준)
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BusStop && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() {
    return 'BusStop{id: $id, name: $name, distance: ${getFormattedDistance()}}';
  }
}
