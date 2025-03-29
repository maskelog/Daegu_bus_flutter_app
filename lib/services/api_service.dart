import 'dart:async';
import 'dart:convert';
import 'dart:math';
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

    try {
      // stationId가 유효한 형식(7로 시작, 10자리)이 아닌 경우 bsId로 간주하고 변환 시도
      String finalStationId = stationId;
      if (!stationId.startsWith('7') || stationId.length != 10) {
        debugPrint('유효한 stationId 형식이 아닙니다. bsId로 간주하고 매핑 시도: $stationId');
        final mappedStation = await getStationById(stationId);
        if (mappedStation != null && mappedStation.stationId != null) {
          finalStationId = mappedStation.stationId!;
          debugPrint('매핑된 stationId: $finalStationId');
        } else {
          debugPrint('bsId "$stationId"에 대한 stationId 매핑 실패');
          throw Exception('정류장 ID 매핑 실패: $stationId');
        }
      }

      debugPrint('정류장 도착 정보 조회 시작: stationId="$finalStationId"');
      final dynamic response = await _busApiChannel.invokeMethod(
        'getStationInfo',
        {'stationId': finalStationId},
      );

      debugPrint('정류장 도착 정보 원본 응답: $response');

      if (response is String) {
        debugPrint('응답이 문자열 형식입니다. 길이: ${response.length}');
        if (response.length > 500) {
          debugPrint('응답 미리보기: ${response.substring(0, 500)}...');
        } else {
          debugPrint('응답 전체: $response');
        }

        try {
          // 응답이 오류 메시지를 포함하는지 확인
          if (response.contains('error')) {
            debugPrint('API 오류 응답 감지: $response');
            // 오류 메시지 대신 빈 리스트 반환
            return [];
          }

          dynamic jsonData = json.decode(response);

          // 응답이 객체인 경우 리스트로 변환
          if (jsonData is Map) {
            debugPrint('맵 형식 응답을 리스트로 변환');
            if (jsonData.containsKey('error')) {
              debugPrint('오류 응답: ${jsonData['error']}');
              return [];
            }
            // 테스트용 데이터 또는 다른 형식의 응답인 경우
            jsonData = [jsonData];
          }

          final jsonList = jsonData as List<dynamic>;
          debugPrint('JSON 파싱 성공. 항목 수: ${jsonList.length}');

          // 응답이 비어있는 경우 처리
          if (jsonList.isEmpty) {
            debugPrint('API 응답이 비어있습니다. 빈 목록 반환');
            return [];
          }

          final arrivals = jsonList
              .map((json) {
                if (json is Map && !json.containsKey('stationId')) {
                  json['stationId'] = finalStationId;
                }

                // 오류 발생 시 개별 항목 스킵
                try {
                  return BusArrival.fromJson(json as Map<String, dynamic>);
                } catch (itemError) {
                  debugPrint('항목 파싱 오류, 무시됨: $itemError');
                  debugPrint('오류 항목: $json');
                  return null;
                }
              })
              .where((arrival) => arrival != null) // null 항목 제거
              .cast<BusArrival>() // 타입 캐스팅
              .toList();

          debugPrint('정류장 도착 정보 조회 결과: ${arrivals.length}개');
          return arrivals;
        } catch (parseError) {
          debugPrint('JSON 파싱 실패: $parseError');
          // 파싱 오류 시 빈 리스트 반환
          return [];
        }
      } else if (response is List) {
        debugPrint('응답이 이미, 리스트 형식입니다. 항목 수: ${response.length}');

        final arrivals = response
            .map((item) {
              if (item is Map && !item.containsKey('stationId')) {
                item['stationId'] = finalStationId;
              }

              try {
                return BusArrival.fromJson(item as Map<String, dynamic>);
              } catch (itemError) {
                debugPrint('항목 파싱 오류, 무시됨: $itemError');
                return null;
              }
            })
            .where((arrival) => arrival != null)
            .cast<BusArrival>()
            .toList();

        debugPrint('정류장 도착 정보 조회 결과: ${arrivals.length}개');
        return arrivals;
      } else if (response == null) {
        debugPrint('응답이 null입니다. 빈 목록 반환');
        return [];
      } else {
        debugPrint('응답이 예상치 못한 형식입니다: ${response.runtimeType}');
        return [];
      }
    } catch (e) {
      debugPrint('정류장 도착 정보 조회 오류: $e');
      // 오류 발생 시 조용히 빈 리스트 반환 (앱 크래시 방지)
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
