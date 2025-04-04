import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:daegu_bus_app/models/bus_route.dart';
import 'package:daegu_bus_app/models/route_station.dart';
import 'package:daegu_bus_app/models/bus_stop.dart';
import 'package:daegu_bus_app/models/bus_arrival.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// 캐시된 데이터를 위한 클래스
class CachedData {
  final dynamic data;
  final DateTime timestamp;

  CachedData(this.data, this.timestamp);

  bool get isExpired =>
      DateTime.now().difference(timestamp) > const Duration(minutes: 1);
}

class ApiService {
  static const MethodChannel _busApiChannel =
      MethodChannel('com.example.daegu_bus_app/bus_api');

  static const String baseUrl = 'https://businfo.daegu.go.kr:8095/dbms_web_api';

  // 캐시 설정
  static final Map<String, CachedData> _cache = {};

  // 캐시 관리 메서드
  static T? _getFromCache<T>(String key) {
    final cached = _cache[key];
    if (cached != null && !cached.isExpired) {
      return cached.data as T;
    }
    _cache.remove(key);
    return null;
  }

  static void _setCache(String key, dynamic data) {
    _cache[key] = CachedData(data, DateTime.now());
  }

  // JSON 응답을 파싱하는 유틸리티 메서드
  static List<dynamic> _parseJsonResponse(dynamic response) {
    if (response == null) {
      debugPrint('응답이 null입니다.');
      return [];
    }
    if (response is String) {
      debugPrint('문자열 응답 받음 (길이: ${response.length})');
      if (response.isEmpty) {
        debugPrint('빈 문자열 응답');
        return [];
      }
      try {
        final decoded = jsonDecode(response);
        if (decoded is List) {
          return decoded;
        } else {
          debugPrint('응답이 리스트 형식이 아님: $decoded');
          return [];
        }
      } on FormatException catch (e) {
        debugPrint('JSON 파싱 오류: $e');
        return [];
      }
    } else if (response is List) {
      return response;
    } else {
      debugPrint('예상치 못한 응답 타입: ${response.runtimeType}');
      return [];
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

      // 요청 전 파라미터 로깅
      final requestArgs = {
        'searchText': query,
        'searchType': searchType, // 'web' 또는 'local'
      };
      debugPrint('요청 파라미터: $requestArgs');

      final dynamic response = await _busApiChannel.invokeMethod(
        'searchStations',
        requestArgs,
      );

      // 응답 로깅
      debugPrint('응답 타입: ${response.runtimeType}');
      debugPrint('원본 응답: $response');

      final jsonList = _parseJsonResponse(response);
      debugPrint('파싱된 JSON 리스트 길이: ${jsonList.length}');
      if (jsonList.isNotEmpty) {
        debugPrint('첫 번째 항목 미리보기: ${jsonList.first}');
      }

      final stations = jsonList.map((json) => BusStop.fromJson(json)).toList();
      debugPrint('정류장 검색 결과: ${stations.length}개');
      if (stations.isNotEmpty) {
        debugPrint(
            '첫 번째 정류장: id=${stations.first.id}, name=${stations.first.name}');
      }

      return stations;
    } catch (e) {
      debugPrint('정류장 검색 오류: $e');
      debugPrint('스택 트레이스: ${StackTrace.current}');
      throw Exception('정류장 검색 중 오류 발생: $e');
    }
  }

// 주변 정류장 검색 (getNearbyStations)
  static Future<List<BusStop>> getNearbyStations(
      double latitude, double longitude, double radiusMeters) async {
    try {
      debugPrint(
          '주변 정류장 검색 시작: latitude=$latitude, longitude=$longitude, radius=${radiusMeters}m');
      final dynamic response = await _busApiChannel.invokeMethod(
        'findNearbyStations', // Android에서 정의된 메서드 이름과 일치
        {
          'latitude': latitude,
          'longitude': longitude,
          'radiusMeters': radiusMeters, // 미터 단위로 직접 전달
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

  static Future<List<BusRoute>> searchBusRoutes(String query) async {
    debugPrint('Flutter에서 전달된 검색어: "$query"');

    final String encodedQuery = Uri.encodeComponent(query);
    final response = await _busApiChannel.invokeMethod(
      'searchBusRoutes',
      {'searchText': encodedQuery},
    );

    debugPrint('네이티브 응답: $response');

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

      debugPrint('응답 타입: ${response.runtimeType}');
      debugPrint('응답 내용: $response');

      List<dynamic> jsonList;
      if (response is String) {
        jsonList = json.decode(response) as List<dynamic>;
      } else if (response is List) {
        jsonList = response;
      } else {
        debugPrint('예상치 못한 응답 형식: ${response.runtimeType}');
        return [];
      }

      final routes = jsonList
          .map((item) {
            if (item is Map) {
              return BusRoute.fromJson(item.cast<String, dynamic>());
            }
            debugPrint('무시된 항목: $item (${item.runtimeType})');
            return null;
          })
          .where((route) => route != null && route.id.isNotEmpty)
          .cast<BusRoute>()
          .toList();

      debugPrint('노선 검색 결과: ${routes.length}개');
      return routes;
    } catch (e) {
      debugPrint('노선 검색 오류: $e');
      return [];
    }
  }

  // 노선 정류장 조회 (MethodChannel 사용)
  static Future<List<RouteStation>> getRouteStations(String routeId) async {
    if (routeId.isEmpty) {
      debugPrint('노선 ID가 비어있습니다.');
      return [];
    }

    try {
      debugPrint('노선 정류장 조회 시작: routeId=$routeId');
      final dynamic response = await _busApiChannel.invokeMethod(
        'getRouteStations',
        {'routeId': routeId},
      );

      // 응답 디버깅
      debugPrint('응답 타입: ${response.runtimeType}');

      // 문자열 응답 처리
      if (response is String) {
        try {
          // JSON 문자열을 디코딩하고 안전하게 파싱
          final List<dynamic> jsonList = json.decode(response) as List<dynamic>;
          final stations = jsonList
              .map((item) {
                if (item is Map) {
                  return RouteStation.fromJson(item);
                } else {
                  debugPrint('무시된 항목: $item (${item.runtimeType})');
                  return null;
                }
              })
              .where((station) => station != null)
              .cast<RouteStation>()
              .toList();

          debugPrint('노선 정류장 조회 결과: ${stations.length}개');
          return stations;
        } catch (e) {
          debugPrint('JSON 파싱 오류: $e');
          throw Exception('노선 정류장 정보 파싱 중 오류 발생: $e');
        }
      }

      // 리스트 응답 처리
      else if (response is List) {
        final stations = response
            .map((item) {
              if (item is Map) {
                return RouteStation.fromJson(item);
              } else {
                debugPrint('무시된 항목: $item (${item.runtimeType})');
                return null;
              }
            })
            .where((station) => station != null)
            .cast<RouteStation>()
            .toList();

        debugPrint('노선 정류장 조회 결과: ${stations.length}개');
        return stations;
      }

      // 기타 응답 형식 처리
      else {
        debugPrint('예상치 못한 응답 형식: ${response.runtimeType}');
        throw Exception('예상치 못한 응답 형식: ${response.runtimeType}');
      }
    } catch (e) {
      debugPrint('노선 정류장 조회 오류: $e');
      throw Exception('노선 정류장 조회 중 오류 발생: $e');
    }
  }

  // API 호출용 stationId로 정류장 정보 조회
  static Future<BusStop?> getStationById(String bsId) async {
    try {
      debugPrint('정류장 정보 조회 시작: bsId="$bsId"');

      // Native 코드 호출하여 stationId 조회
      final stationId = await _busApiChannel.invokeMethod(
        'getStationIdFromBsId',
        {'bsId': bsId},
      );

      if (stationId != null && stationId.toString().isNotEmpty) {
        debugPrint(
            'bsId "$bsId"에 대한 stationId "${stationId.toString()}" 조회 성공');
        return BusStop(
          id: bsId,
          name: '조회된 정류장',
          stationId: stationId.toString(),
        );
      }

      debugPrint('bsId "$bsId"에 대한 stationId 조회 실패');
      return null;
    } catch (e) {
      debugPrint('정류장 정보 조회 오류: $e');
      return null;
    }
  }

// 정류장 도착 정보 조회
  static Future<List<BusArrival>> getStationInfo(String stationId) async {
    if (stationId.isEmpty) {
      debugPrint('정류장 ID가 비어 있습니다.');
      return [];
    }

    // 캐시 확인
    final cacheKey = 'station_info_$stationId';
    final cached = _getFromCache<List<BusArrival>>(cacheKey);
    if (cached != null) {
      debugPrint('캐시된 정류장 정보 사용: $stationId');
      return cached;
    }

    try {
      String finalStationId = stationId;
      if (!stationId.startsWith('7') || stationId.length != 10) {
        final mappedStation = await getStationById(stationId);
        if (mappedStation?.stationId != null) {
          finalStationId = mappedStation!.stationId!;
        } else {
          throw Exception('정류장 ID 매핑 실패: $stationId');
        }
      }

      final response = await _busApiChannel.invokeMethod(
        'getStationInfo',
        {'stationId': finalStationId},
      );

      final arrivals = _processStationInfoResponse(response, finalStationId);

      // 결과 캐싱
      _setCache(cacheKey, arrivals);

      return arrivals;
    } catch (e) {
      debugPrint('정류장 도착 정보 조회 오류: $e');
      return [];
    }
  }

  // 응답 처리 최적화
  static List<BusArrival> _processStationInfoResponse(
      dynamic response, String stationId) {
    if (response == null) return [];

    try {
      final jsonData = response is String ? json.decode(response) : response;

      if (jsonData is Map && jsonData.containsKey('error')) {
        debugPrint('API 오류 응답: ${jsonData['error']}');
        return [];
      }

      final List<dynamic> jsonList = jsonData is List ? jsonData : [jsonData];

      return jsonList
          .map((json) {
            try {
              if (json is Map && !json.containsKey('stationId')) {
                json['stationId'] = stationId;
              }
              return BusArrival.fromJson(json as Map<String, dynamic>);
            } catch (e) {
              debugPrint('항목 파싱 오류: $e');
              return null;
            }
          })
          .where((arrival) => arrival != null)
          .cast<BusArrival>()
          .toList();
    } catch (e) {
      debugPrint('응답 처리 오류: $e');
      return [];
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

  // 버스 실시간 정보 가져오기
  Future<Map<String, dynamic>> fetchRealtimeBusInfo(
      String routeId, String stationId) async {
    try {
      const platform = MethodChannel('com.example.daegu_bus_app/bus_api');

      // 실시간 버스 도착 정보 요청
      final arrivalInfoJson =
          await platform.invokeMethod('getBusArrivalByRouteId', {
        'stationId': stationId,
        'routeId': routeId,
      });

      debugPrint(
          '실시간 버스 도착 정보 수신: ${arrivalInfoJson.substring(0, min(100, arrivalInfoJson.length as int))}...');

      final arrivalInfo = json.decode(arrivalInfoJson);
      int remainingMinutes = 0;
      String currentStation = "";

      if (arrivalInfo != null &&
          arrivalInfo['bus'] != null &&
          arrivalInfo['bus'].isNotEmpty) {
        final busInfo = arrivalInfo['bus'][0];
        remainingMinutes = _parseRemainingTime(busInfo['estimatedTime']);
        currentStation = busInfo['currentStation'] ?? "";

        debugPrint('실시간 정보: 남은 시간: $remainingMinutes분, 현재 위치: $currentStation');

        return {
          'remainingMinutes': remainingMinutes,
          'currentStation': currentStation,
          'success': true
        };
      }

      return {'success': false};
    } catch (e) {
      debugPrint('실시간 버스 정보 가져오기 오류: $e');
      return {'success': false};
    }
  }

  // 도착 시간 문자열을 분 단위로 변환
  int _parseRemainingTime(String timeStr) {
    if (timeStr.isEmpty) return 0;
    if (timeStr == "전") return 1;
    if (timeStr.contains("분")) {
      final regex = RegExp(r'(\d+)');
      final match = regex.firstMatch(timeStr);
      if (match != null) {
        return int.parse(match.group(1)!);
      }
    }
    return 0;
  }
}
