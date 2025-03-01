import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';

class ApiService {
  // API 서버 URL (실제 사용 시 서버 주소로 변경)
  static const String baseUrl =
      'http://10.0.2.2:8080'; // Android 에뮬레이터용 localhost 접근 주소

  // 정류장 검색 - stations.json 파일을 활용하는 서버 API 사용
  static Future<List<BusStop>> searchStations(String query) async {
    if (query.isEmpty) return [];

    try {
      final url = Uri.parse('$baseUrl/station/search/$query');
      final response = await http.get(url);

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

// 모든 정류장 정보 가져오기
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

  // 정류장 도착 정보 조회 - 정류장 ID 사용
  static Future<List<BusArrival>> getStationInfo(String stationId) async {
    try {
      final url = Uri.parse('$baseUrl/station/$stationId');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => BusArrival.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load station info: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error loading station info: $e');
    }
  }

  // 정류장 도착 정보 조회 (쿼리 방식) - stations.json 데이터를 서버에서 사용
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

  // 노선 검색
  static Future<List<Map<String, dynamic>>> searchRoutes(String query) async {
    if (query.isEmpty) return [];

    try {
      final url = Uri.parse('$baseUrl/route/search/$query');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to search routes: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error searching routes: $e');
    }
  }

  // 노선 정보 조회
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
