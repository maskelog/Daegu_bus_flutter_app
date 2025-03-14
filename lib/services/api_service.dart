import 'dart:async';
import 'dart:convert';
import 'package:daegu_bus_app/models/bus_route.dart';
import 'package:daegu_bus_app/models/route_station.dart';
import 'package:daegu_bus_app/models/bus_stop.dart';
import 'package:daegu_bus_app/models/bus_arrival.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';

class ApiService {
  // 네이티브에서 API 호출 관련 메서드들은 "bus_api" 채널에 등록되어 있습니다.
  static const MethodChannel _busApiChannel =
      MethodChannel('com.example.daegu_bus_app/bus_api');
  // 나머지 기능(예: getRouteStations, getStationInfo 등)은 기존 "methods" 채널 사용
  static const MethodChannel _methodChannel =
      MethodChannel('com.example.daegu_bus_app/methods');

  // API 서버 URL (Android 에뮬레이터용 localhost 접근 주소)
  static const String baseUrl = 'http://10.0.2.2:8080';

  // 정류장 검색 - HTTP 요청
  static Future<List<BusStop>> searchStations(String query) async {
    if (query.isEmpty) return [];

    try {
      final url = Uri.parse('$baseUrl/station/search/$query');
      final response = await http.get(url).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('서버 응답 시간이 너무 깁니다.');
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => BusStop.fromJson(json)).toList();
      } else {
        throw Exception('Failed to search stations: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error searching stations: $e');
    }
  }

  // 모든 정류장 정보 가져오기 (HTTP 요청)
  static Future<List<BusStop>> getAllStations() async {
    try {
      final url = Uri.parse('$baseUrl/station/search/%20');
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => BusStop.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load all stations: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error loading all stations: $e');
    }
  }

  // 정류장 도착 정보 조회 (네이티브 연동)
  static Future<List<BusArrival>> getStationInfo(String stationId) async {
    try {
      final dynamic response = await _methodChannel
          .invokeMethod('getStationInfo', {'stationId': stationId});
      List<dynamic> jsonList;
      if (response is String) {
        jsonList = json.decode(response);
      } else if (response is List) {
        jsonList = response;
      } else {
        throw Exception('Unexpected response type: ${response.runtimeType}');
      }
      return jsonList.map((json) => BusArrival.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Error loading station info: $e');
    }
  }

  // 노선 검색 (네이티브 연동) - "searchBusRoutes"는 bus_api 채널에 등록되어 있음
  static Future<List<BusRoute>> searchBusRoutes(String query) async {
    try {
      final List<BusRoute> routes = [];
      final dynamic response = await _busApiChannel
          .invokeMethod('searchBusRoutes', {'searchText': query});

      List<dynamic> responseList;
      if (response is String) {
        responseList = json.decode(response);
      } else if (response is List) {
        responseList = response;
      } else {
        throw Exception('Unexpected response type: ${response.runtimeType}');
      }

      for (var item in responseList) {
        // 네이티브에서 검색 결과의 노선 ID는 "id" 키로 전달됨
        final routeId = item['id'];
        final routeDetails = await getRouteDetails(routeId);
        routes.add(routeDetails ?? BusRoute.fromJson(item));
      }

      return routes;
    } catch (e) {
      debugPrint('Error searching bus routes: $e');
      return [];
    }
  }

  // 노선 상세 정보 조회 (네이티브 연동)
  static Future<BusRoute?> getRouteDetails(String routeId) async {
    try {
      final dynamic response = await _busApiChannel
          .invokeMethod('getBusRouteDetails', {'routeId': routeId});

      Map<String, dynamic> jsonMap;
      if (response is String) {
        jsonMap = json.decode(response);
      } else if (response is Map) {
        jsonMap = response.cast<String, dynamic>();
      } else {
        throw Exception('Unexpected response type: ${response.runtimeType}');
      }

      return jsonMap.isNotEmpty ? BusRoute.fromJson(jsonMap) : null;
    } catch (e) {
      debugPrint('Error getting route details: $e');
      return null;
    }
  }

// 노선별 정류장 목록 조회 (네이티브 연동)
  static Future<List<RouteStation>> getRouteStations(String routeId) async {
    try {
      // 수정: 'getBusRouteMap' → 'getRouteStations'
      final dynamic response = await _methodChannel
          .invokeMethod('getRouteStations', {'routeId': routeId});

      List<dynamic> jsonList;
      if (response is String) {
        jsonList = json.decode(response);
      } else if (response is List) {
        jsonList = response;
      } else {
        throw Exception('Unexpected response type: ${response.runtimeType}');
      }

      final List<RouteStation> stations =
          jsonList.map((json) => RouteStation.fromJson(json)).toList();

      stations.sort((a, b) => a.sequenceNo.compareTo(b.sequenceNo));
      return stations;
    } catch (e) {
      debugPrint('Error getting route stations: $e');
      return [];
    }
  }

  // 노선 정보 조회 (HTTP 요청)
  static Future<Map<String, dynamic>> getRouteInfo(String routeId) async {
    try {
      final url = Uri.parse('$baseUrl/route/$routeId');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load route info: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error loading route info: $e');
    }
  }
}
