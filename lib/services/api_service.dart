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
  static const MethodChannel _methodChannel =
      MethodChannel('com.example.daegu_bus_app/methods');
  // API 서버 URL (실제 사용 시 서버 주소로 변경)
  static const String baseUrl =
      'http://10.0.2.2:8080'; // Android 에뮬레이터용 localhost 접근 주소

  // 정류장 검색 - stations.json 파일을 활용하는 서버 API 사용 (HTTP 요청)
  static Future<List<BusStop>> searchStations(String query) async {
    if (query.isEmpty) return [];

    try {
      final url = Uri.parse('$baseUrl/station/search/$query');
      final response = await http.get(url).timeout(
        const Duration(seconds: 10), // 10초 이상 응답이 없으면 타임아웃
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

  // 정류장 도착 정보 조회 (네이티브 BusApiService와 MethodChannel 연동)
  static Future<List<BusArrival>> getStationInfo(String stationId) async {
    try {
      // 네이티브 코드에서 getStationInfo를 호출하여 JSON 문자열(혹은 List<Map>) 반환받음
      final dynamic response = await _methodChannel
          .invokeMethod('getStationInfo', {'stationId': stationId});

      // 네이티브에서 반환한 값이 JSON 문자열일 경우 파싱
      List<dynamic> jsonList;
      if (response is String) {
        jsonList = json.decode(response);
      } else if (response is List) {
        jsonList = response;
      } else {
        throw Exception('Unexpected response type: ${response.runtimeType}');
      }

      // BusArrival.fromJson() 생성자를 통해 모델 변환
      return jsonList.map((json) => BusArrival.fromJson(json)).toList();
    } catch (e) {
      throw Exception('Error loading station info: $e');
    }
  }

  // 정류장 도착 정보 조회 (쿼리 방식) - stations.json 데이터를 서버에서 사용 (HTTP 요청)
  static Future<Map<String, dynamic>> getStationArrivalByQuery({
    String? bsNm,
    String? wincId,
  }) async {
    if (bsNm == null && wincId == null) {
      throw Exception('At least one of bsNm or wincId must be provided');
    }

    try {
      final queryParams = <String, String>{};
      if (bsNm != null) queryParams['bsNm'] = bsNm;
      if (wincId != null) queryParams['wincId'] = wincId;

      final url = Uri.parse('$baseUrl/api/arrival')
          .replace(queryParameters: queryParams);
      final response = await http.get(url);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        throw Exception('Station not found');
      } else {
        throw Exception(
            'Failed to load station arrival info: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error loading station arrival info: $e');
    }
  }

  // 노선 검색 (네이티브 연동)
  static Future<List<BusRoute>> searchBusRoutes(String query) async {
    try {
      final List<BusRoute> routes = [];
      final dynamic response = await _methodChannel
          .invokeMethod('searchBusRoutes', {'query': query});

      if (response != null) {
        for (var item in response) {
          routes.add(BusRoute.fromJson(item));
        }
      }
      return routes;
    } catch (e) {
      debugPrint('Error searching bus routes: $e');
      return [];
    }
  }

  // 노선별 정류장 목록 조회 (네이티브 연동)
  static Future<List<RouteStation>> getRouteStations(String routeId) async {
    try {
      final List<RouteStation> stations = [];
      final dynamic response = await _methodChannel
          .invokeMethod('getRouteStations', {'routeId': routeId});

      if (response != null) {
        for (var item in response) {
          stations.add(RouteStation.fromJson(item));
        }
      }
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
