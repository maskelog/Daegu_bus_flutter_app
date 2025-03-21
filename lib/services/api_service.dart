import 'dart:async';
import 'dart:convert';
import 'package:daegu_bus_app/models/bus_route.dart';
import 'package:daegu_bus_app/models/route_station.dart';
import 'package:daegu_bus_app/models/bus_stop.dart';
import 'package:daegu_bus_app/models/bus_arrival.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ApiService {
  static const MethodChannel _busApiChannel =
      MethodChannel('com.example.daegu_bus_app/bus_api');

  static const String baseUrl = 'https://businfo.daegu.go.kr:8095/dbms_web_api';

  // JSON 응답을 파싱하는 유틸리티 메서드
  static List<dynamic> _parseJsonResponse(dynamic response) {
    if (response is String) {
      return json.decode(response) as List<dynamic>;
    } else if (response is List) {
      return response;
    } else {
      throw Exception('Unexpected response type: ${response.runtimeType}');
    }
  }

  // Map 응답을 파싱하는 유틸리티 메서드
  static Map<String, dynamic> _parseMapResponse(dynamic response) {
    if (response is String) {
      return json.decode(response) as Map<String, dynamic>;
    } else if (response is Map) {
      return response.cast<String, dynamic>();
    } else {
      throw Exception('Unexpected response type: ${response.runtimeType}');
    }
  }

  // 정류장 검색 (웹 또는 로컬 DB)
  static Future<List<BusStop>> searchStations(String query,
      {String searchType = 'web'}) async {
    if (query.isEmpty) {
      debugPrint('검색어가 비어 있습니다.');
      return [];
    }

    try {
      debugPrint('정류장 검색 시작: query="$query", searchType="$searchType"');
      final dynamic response = await _busApiChannel.invokeMethod(
        'searchStations',
        {
          'searchText': query,
          'searchType': searchType, // 'web' 또는 'local'
        },
      );

      final jsonList = _parseJsonResponse(response);
      final stations = jsonList.map((json) => BusStop.fromJson(json)).toList();
      debugPrint('정류장 검색 결과: ${stations.length}개');
      return stations;
    } catch (e) {
      debugPrint('정류장 검색 오류: $e');
      throw Exception('정류장 검색 중 오류 발생: $e');
    }
  }

  // 주변 정류장 검색 (getNearbyStations)
  static Future<List<BusStop>> getNearbyStations(
      double latitude, double longitude, double radius) async {
    try {
      debugPrint(
          '주변 정류장 검색 시작: latitude=$latitude, longitude=$longitude, radius=$radius');
      final dynamic response = await _busApiChannel.invokeMethod(
        'findNearbyStations', // Android에서 정의된 메서드 이름과 일치
        {
          'latitude': latitude,
          'longitude': longitude,
          'radiusKm': radius,
        },
      );

      final jsonList = _parseJsonResponse(response);
      final stations = jsonList.map((json) => BusStop.fromJson(json)).toList();
      debugPrint('주변 정류장 검색 결과: ${stations.length}개');
      return stations;
    } catch (e) {
      debugPrint('주변 정류장 검색 오류: $e');
      throw Exception('주변 정류장 검색 중 오류 발생: $e');
    }
  }

  // 모든 정류장 가져오기 (로컬 DB에서 조회)
  static Future<List<BusStop>> getAllStations() async {
    try {
      debugPrint('모든 정류장 조회 시작');
      final dynamic response = await _busApiChannel.invokeMethod(
        'searchStations',
        {
          'searchText': '*', // 모든 정류장을 가져오기 위한 특수 검색어
          'searchType': 'local',
        },
      );

      final jsonList = _parseJsonResponse(response);
      final stations = jsonList.map((json) => BusStop.fromJson(json)).toList();
      debugPrint('모든 정류장 조회 결과: ${stations.length}개');
      return stations;
    } catch (e) {
      debugPrint('모든 정류장 조회 오류: $e');
      throw Exception('모든 정류장 조회 중 오류 발생: $e');
    }
  }

  // 노선 검색 (MethodChannel 사용)
  static Future<List<BusRoute>> searchBusRoutes(String query) async {
    if (query.isEmpty) {
      debugPrint('노선 검색어가 비어 있습니다.');
      return [];
    }

    try {
      debugPrint('노선 검색 시작: query="$query"');
      final dynamic response = await _busApiChannel.invokeMethod(
        'searchBusRoutes',
        {'searchText': query},
      );

      final jsonList = _parseJsonResponse(response);
      final routes = jsonList.map((json) => BusRoute.fromJson(json)).toList();
      debugPrint('노선 검색 결과: ${routes.length}개');
      return routes;
    } catch (e) {
      debugPrint('노선 검색 오류: $e');
      throw Exception('노선 검색 중 오류 발생: $e');
    }
  }

  // 노선 정류장 조회 (MethodChannel 사용)
  static Future<List<RouteStation>> getRouteStations(String routeId) async {
    if (routeId.isEmpty) {
      debugPrint('노선 ID가 비어 있습니다.');
      return [];
    }

    try {
      debugPrint('노선 정류장 조회 시작: routeId="$routeId"');
      final dynamic response = await _busApiChannel.invokeMethod(
        'getRouteStations',
        {'routeId': routeId},
      );

      final jsonList = _parseJsonResponse(response);
      final stations =
          jsonList.map((json) => RouteStation.fromJson(json)).toList();
      debugPrint('노선 정류장 조회 결과: ${stations.length}개');
      return stations;
    } catch (e) {
      debugPrint('노선 정류장 조회 오류: $e');
      throw Exception('노선 정류장 조회 중 오류 발생: $e');
    }
  }

  // 정류장 도착 정보 조회
  static Future<List<BusArrival>> getStationInfo(String stationId) async {
    if (stationId.isEmpty) {
      debugPrint('정류장 ID가 비어 있습니다.');
      return [];
    }

    try {
      debugPrint('정류장 도착 정보 조회 시작: stationId="$stationId"');
      final dynamic response = await _busApiChannel.invokeMethod(
        'getStationInfo',
        {'stationId': stationId},
      );

      final jsonList = _parseJsonResponse(response);
      final arrivals =
          jsonList.map((json) => BusArrival.fromJson(json)).toList();
      debugPrint('정류장 도착 정보 조회 결과: ${arrivals.length}개');
      return arrivals;
    } catch (e) {
      debugPrint('정류장 도착 정보 조회 오류: $e');
      throw Exception('정류장 도착 정보 조회 중 오류 발생: $e');
    }
  }

  // 노선 상세 정보 조회
  static Future<BusRoute?> getRouteDetails(String routeId) async {
    if (routeId.isEmpty) {
      debugPrint('노선 ID가 비어 있습니다.');
      return null;
    }

    try {
      debugPrint('노선 상세 정보 조회 시작: routeId="$routeId"');
      final dynamic response = await _busApiChannel.invokeMethod(
        'getBusRouteDetails',
        {'routeId': routeId},
      );

      final jsonMap = _parseMapResponse(response);
      final route = jsonMap.isNotEmpty ? BusRoute.fromJson(jsonMap) : null;
      debugPrint('노선 상세 정보 조회 결과: ${route?.routeNo ?? "없음"}');
      return route;
    } catch (e) {
      debugPrint('노선 상세 정보 조회 오류: $e');
      return null;
    }
  }

  // 노선별 도착 정보 조회
  static Future<BusArrival?> getBusArrivalByRouteId(
      String stationId, String routeId) async {
    if (stationId.isEmpty || routeId.isEmpty) {
      debugPrint('정류장 ID 또는 노선 ID가 비어 있습니다.');
      return null;
    }

    try {
      debugPrint('노선별 도착 정보 조회 시작: stationId="$stationId", routeId="$routeId"');
      final dynamic response = await _busApiChannel.invokeMethod(
        'getBusArrivalByRouteId',
        {
          'stationId': stationId,
          'routeId': routeId,
        },
      );

      final jsonMap = _parseMapResponse(response);
      final arrival = jsonMap.isNotEmpty ? BusArrival.fromJson(jsonMap) : null;
      debugPrint('노선별 도착 정보 조회 결과: ${arrival?.routeNo ?? "없음"}');
      return arrival;
    } catch (e) {
      debugPrint('노선별 도착 정보 조회 오류: $e');
      return null;
    }
  }
}
