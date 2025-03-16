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
  static const MethodChannel _busApiChannel =
      MethodChannel('com.example.daegu_bus_app/bus_api');

  static const String baseUrl = 'https://businfo.daegu.go.kr:8095/dbms_web_api';

  // 정류장 검색
  static Future<List<BusStop>> searchStations(String query) async {
    if (query.isEmpty) return [];
    try {
      final dynamic response = await _busApiChannel
          .invokeMethod('searchStations', {'searchText': query});
      List<dynamic> jsonList =
          response is String ? json.decode(response) : response;
      return jsonList.map((json) => BusStop.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error searching stations: $e');
      throw Exception('Error searching stations: $e');
    }
  }

  // 모든 정류장 가져오기
  static Future<List<BusStop>> getAllStations() async {
    try {
      debugPrint('모든 정류장 가져오기 시작');
      final dynamic response = await _busApiChannel
          .invokeMethod('searchStations', {'searchText': ''});
      List<dynamic> jsonList =
          response is String ? json.decode(response) : response;
      final stations = jsonList.map((json) => BusStop.fromJson(json)).toList();
      debugPrint('가져온 정류장 수: ${stations.length}');
      return stations;
    } catch (e) {
      debugPrint('Error getting all stations: $e');
      throw Exception('Error getting all stations: $e');
    }
  }

  // 노선 검색 (JSON 응답 처리)
  static Future<List<BusRoute>> searchBusRoutes(String query) async {
    try {
      debugPrint('노선 검색 시작: "$query"');
      final url = Uri.parse('$baseUrl/route/search?searchText=$query');
      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception('Failed to search bus routes: ${response.statusCode}');
      }

      debugPrint('API 응답: ${response.body}');

      if (response.body.isEmpty) {
        throw Exception('API 응답이 비어 있습니다');
      }

      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final success = jsonData['header']['success'] == true;
      if (!success) {
        throw Exception('API 요청 실패: ${jsonData['header']['resultMsg']}');
      }

      final body = jsonData['body'];
      final routes = (body as List<dynamic>)
          .map((item) => BusRoute(
                id: item['routeId'] as String,
                routeNo: item['routeNo'] as String,
                startPoint: null,
                endPoint: null,
                routeDescription: item['routeTCd'] as String?,
              ))
          .toList();

      debugPrint('노선 검색 결과 개수: ${routes.length}');
      return routes;
    } catch (e) {
      debugPrint('노선 검색 중 오류 발생: $e');
      throw Exception('노선 검색 중 오류 발생: $e');
    }
  }

  // 노선 정류장 조회 (JSON 응답 처리)
  static Future<List<RouteStation>> getRouteStations(String routeId) async {
    try {
      final url = Uri.parse('$baseUrl/bs/route?routeId=$routeId');
      final response = await http.get(url);

      if (response.statusCode != 200) {
        throw Exception(
            'Failed to load route stations: ${response.statusCode}');
      }

      final jsonData = json.decode(response.body) as Map<String, dynamic>;
      final success = jsonData['header']['success'] == true;
      if (!success) {
        throw Exception('API 요청 실패: ${jsonData['header']['resultMsg']}');
      }

      final List<dynamic> body = jsonData['body'];
      final stations = body.map((json) => RouteStation.fromJson(json)).toList();
      stations.sort((a, b) => a.sequenceNo.compareTo(b.sequenceNo));
      return stations;
    } catch (e) {
      debugPrint('Error getting route stations: $e');
      throw Exception('Error getting route stations: $e');
    }
  }

  // 정류장 도착 정보 조회
  static Future<List<BusArrival>> getStationInfo(String stationId) async {
    try {
      final dynamic response = await _busApiChannel
          .invokeMethod('getStationInfo', {'stationId': stationId});
      List<dynamic> jsonList =
          response is String ? json.decode(response) : response;
      return jsonList.map((json) => BusArrival.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error loading station info: $e');
      throw Exception('Error loading station info: $e');
    }
  }

  // 노선 상세 정보 조회
  static Future<BusRoute?> getRouteDetails(String routeId) async {
    try {
      final dynamic response = await _busApiChannel
          .invokeMethod('getBusRouteDetails', {'routeId': routeId});
      Map<String, dynamic> jsonMap =
          response is String ? json.decode(response) : response;
      return jsonMap.isNotEmpty ? BusRoute.fromJson(jsonMap) : null;
    } catch (e) {
      debugPrint('Error getting route details: $e');
      return null;
    }
  }

  // 노선별 도착 정보 조회
  static Future<BusArrival?> getBusArrivalByRouteId(
      String stationId, String routeId) async {
    try {
      final dynamic response = await _busApiChannel.invokeMethod(
          'getBusArrivalByRouteId',
          {'stationId': stationId, 'routeId': routeId});
      Map<String, dynamic> jsonMap =
          response is String ? json.decode(response) : response;
      return jsonMap.isNotEmpty ? BusArrival.fromJson(jsonMap) : null;
    } catch (e) {
      debugPrint('Error getting bus arrival by route ID: $e');
      return null;
    }
  }
}
