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
  // JSON 응답을 파싱하는 유틸리티 메서드
  static List<dynamic> _parseJsonResponse(dynamic response) {
    try {
      if (response is String) {
        // 응답 로깅 추가
        debugPrint('문자열 응답 받음 (길이: ${response.length})');
        if (response.length > 500) {
          debugPrint('응답 미리보기: ${response.substring(0, 500)}...');
        } else {
          debugPrint('응답 전체: $response');
        }

        return json.decode(response) as List<dynamic>;
      } else if (response is List) {
        debugPrint('리스트 응답 받음 (${response.length}개 항목)');
        return response;
      } else {
        debugPrint('예상치 못한 응답 타입: ${response.runtimeType}');
        if (response == null) {
          return [];
        }

        // Map 타입인 경우 리스트로 변환 시도
        if (response is Map) {
          debugPrint('Map을 List로 변환 시도');
          return [response];
        }

        throw Exception('예상치 못한 응답 타입: ${response.runtimeType}');
      }
    } catch (e) {
      debugPrint('응답 파싱 오류: $e');
      rethrow;
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

      // 로컬 DB에서 정류장 정보 조회
      // (실제 구현에서는 DB 조회 코드로 대체)

      // 임시로 하드코딩된 매핑 사용
      final Map<String, String> stationIdMapping = {
        '22086': '7041065000', // 한실공원앞
        '10369': '7011011000', // 고곡리
        // 필요한 다른 매핑 추가
      };

      // 매핑된 stationId가 있으면 반환
      if (stationIdMapping.containsKey(bsId)) {
        return BusStop(
          id: bsId,
          name: '매핑된 정류장',
          stationId: stationIdMapping[bsId],
        );
      }

      // 없으면 Native 코드 호출하여 검색
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

    try {
      // stationId 형식 확인 (7로 시작하는 10자리 숫자면 바로 사용)
      String finalStationId = stationId;
      if (!stationId.startsWith('7') || stationId.length != 10) {
        debugPrint('유효한 stationId 형식이 아닙니다. 매핑 시도: $stationId');

        // 매핑 시도
        final mappedStation = await getStationById(stationId);
        if (mappedStation != null && mappedStation.stationId != null) {
          finalStationId = mappedStation.stationId!;
          debugPrint('매핑된 stationId: $finalStationId');
        }
      }

      debugPrint('정류장 도착 정보 조회 시작: stationId="$finalStationId"');
      final dynamic response = await _busApiChannel.invokeMethod(
        'getStationInfo',
        {'stationId': finalStationId},
      );

      // 디버깅용 로그
      debugPrint('정류장 도착 정보 원본 응답: $response');

      // 응답 처리 코드는 동일하게 유지
      if (response is String) {
        debugPrint('응답이 문자열 형식입니다. 길이: ${response.length}');
        if (response.length > 500) {
          debugPrint('응답 미리보기: ${response.substring(0, 500)}...');
        } else {
          debugPrint('응답 전체: $response');
        }

        try {
          final jsonList = json.decode(response) as List<dynamic>;
          debugPrint('JSON 파싱 성공. 항목 수: ${jsonList.length}');

          if (jsonList.isNotEmpty && jsonList[0] is Map) {
            debugPrint('첫 번째 항목의 키: ${(jsonList[0] as Map).keys.join(', ')}');
          }

          final arrivals = jsonList.map((json) {
            if (json is Map && !json.containsKey('stationId')) {
              json['stationId'] = finalStationId;
            }
            return BusArrival.fromJson(json as Map<String, dynamic>);
          }).toList();

          debugPrint('정류장 도착 정보 조회 결과: ${arrivals.length}개');
          return arrivals;
        } catch (parseError) {
          debugPrint('JSON 파싱 실패: $parseError');
          rethrow;
        }
      } else {
        debugPrint('응답이 문자열이 아닌 ${response.runtimeType} 형식입니다.');
        final jsonList = _parseJsonResponse(response);
        final arrivals = jsonList.map((json) {
          if (json is Map && !json.containsKey('stationId')) {
            json['stationId'] = finalStationId;
          }
          return BusArrival.fromJson(json as Map<String, dynamic>);
        }).toList();

        debugPrint('정류장 도착 정보 조회 결과: ${arrivals.length}개');
        return arrivals;
      }
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
