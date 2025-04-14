import 'dart:async';
import 'dart:convert';
import '../models/bus_arrival.dart';
import '../models/bus_info.dart';
import '../models/bus_route.dart';
import '../utils/dio_client.dart';
import '../main.dart' show logMessage, LogLevel;

/// 버스 노선 관련 API 서비스
class RouteService {
  static const String _methodChannel = 'com.example.daegu_bus_app/bus_api';
  static const int _defaultTimeout = 15; // seconds

  // 사용하는 DioClient 인스턴스
  final DioClient _dioClient;

  // 생성자
  RouteService({DioClient? dioClient}) : _dioClient = dioClient ?? DioClient();

  /// 버스 노선 검색 API
  Future<List<BusRoute>> searchBusRoutes(String searchText) async {
    try {
      if (searchText.isEmpty) {
        logMessage('검색어가 비어있습니다', level: LogLevel.warning);
        return [];
      }

      final result = await _callNativeMethod(
          'searchBusRoutes', {'searchText': searchText});

      if (result == null) {
        return [];
      }

      return _parseBusRouteResult(result);
    } catch (e) {
      logMessage('노선 검색 오류: $e', level: LogLevel.error);
      return [];
    }
  }

  /// 버스 노선 상세 정보 조회 API
  Future<BusRoute?> getBusRouteDetails(String routeId) async {
    try {
      if (routeId.isEmpty) {
        logMessage('노선 ID가 비어있습니다', level: LogLevel.warning);
        return null;
      }

      final result =
          await _callNativeMethod('getBusRouteDetails', {'routeId': routeId});

      if (result == null) {
        return null;
      }

      final Map<String, dynamic> routeData = jsonDecode(result);
      return BusRoute.fromJson(routeData);
    } catch (e) {
      logMessage('노선 상세 정보 조회 오류: $e', level: LogLevel.error);
      return null;
    }
  }

  /// 버스 위치 정보 조회 API
  Future<List<dynamic>> getBusPositionInfo(String routeId) async {
    try {
      if (routeId.isEmpty) {
        logMessage('노선 ID가 비어있습니다', level: LogLevel.warning);
        return [];
      }

      final result =
          await _callNativeMethod('getBusPositionInfo', {'routeId': routeId});

      if (result == null) {
        return [];
      }

      return jsonDecode(result);
    } catch (e) {
      logMessage('버스 위치 정보 조회 오류: $e', level: LogLevel.error);
      return [];
    }
  }

  /// 노선별 버스 도착 정보 조회 API
  Future<List<BusArrival>> getBusArrivalByRouteId(
      String stationId, String routeId) async {
    try {
      if (stationId.isEmpty || routeId.isEmpty) {
        logMessage('정류장 ID 또는 노선 ID가 비어있습니다', level: LogLevel.warning);
        return [];
      }

      final result = await _callNativeMethod('getBusArrivalByRouteId',
          {'stationId': stationId, 'routeId': routeId});

      if (result == null) {
        return [];
      }

      // 단일 노선 정보만 포함된 응답을 파싱
      final Map<String, dynamic> data = jsonDecode(result);

      // 결과를 BusArrival 목록으로 변환
      final List<BusArrival> arrivals = [];

      if (data.containsKey('bus') && data['bus'] is List) {
        final List<dynamic> busInfoList = data['bus'];

        // 버스 정보 목록 생성
        final List<BusInfo> busInfos = [];

        for (var busInfo in busInfoList) {
          if (busInfo is Map<String, dynamic>) {
            // 저상 버스 여부 확인
            bool isLowFloor = false;
            String busNumber = busInfo['버스번호'] ?? '';
            if (busNumber.contains('저상')) {
              isLowFloor = true;
              busNumber = busNumber.replaceAll(RegExp(r'\(저상\)|\(일반\)'), '');
            }

            // 도착 예정 시간 처리 (그대로 전달)
            String estimatedTime = busInfo['도착예정소요시간'] ?? '';

            // 운행 종료 여부 확인
            bool isOutOfService = estimatedTime == '운행종료';

            final info = BusInfo(
              busNumber: busNumber,
              currentStation: busInfo['현재정류소'] ?? '',
              remainingStops: busInfo['남은정류소'] ?? '',
              estimatedTime: estimatedTime,
              isLowFloor: isLowFloor,
              isOutOfService: isOutOfService,
            );

            busInfos.add(info);
          }
        }

        // 버스 도착 정보 생성
        if (busInfos.isNotEmpty) {
          final arrival = BusArrival(
            routeNo: data['name'] ?? '',
            routeId: data['id'] ?? '',
            busInfoList: busInfos,
            direction: data['forward'] ?? '',
          );
          arrivals.add(arrival);

          // 디버그 로그 추가
          if (busInfos.isNotEmpty) {
            logMessage('버스 도착 정보: ${busInfos.first.estimatedTime}',
                level: LogLevel.debug);
          }
        }
      }

      return arrivals;
    } catch (e) {
      logMessage('노선별 버스 도착 정보 조회 오류: $e', level: LogLevel.error);
      return [];
    }
  }

  /// 노선 정류장 목록 조회 API
  Future<List<dynamic>> getRouteStations(String routeId) async {
    try {
      if (routeId.isEmpty) {
        logMessage('노선 ID가 비어있습니다', level: LogLevel.warning);
        return [];
      }

      final result =
          await _callNativeMethod('getRouteStations', {'routeId': routeId});

      if (result == null) {
        return [];
      }

      return jsonDecode(result);
    } catch (e) {
      logMessage('노선 정류장 목록 조회 오류: $e', level: LogLevel.error);
      return [];
    }
  }

  /// 네이티브 메서드 호출 공통 함수
  Future<String?> _callNativeMethod(
      String method, Map<String, dynamic> arguments) async {
    try {
      // DioClient 인스턴스를 통한 채널 호출
      final dynamic result = await _dioClient.callNativeMethod(
          _methodChannel, method, arguments,
          timeout: const Duration(seconds: _defaultTimeout));

      if (result == null) {
        logMessage('네이티브 메서드 응답 없음: $method', level: LogLevel.warning);
        return null;
      }

      return result.toString();
    } catch (e) {
      logMessage('네이티브 메서드 호출 오류: $method, $e', level: LogLevel.error);
      return null;
    }
  }

  /// 버스 노선 결과를 BusRoute 객체로 변환
  List<BusRoute> _parseBusRouteResult(String jsonString) {
    try {
      final List<dynamic> data = jsonDecode(jsonString);
      return data.map((route) => BusRoute.fromJson(route)).toList();
    } catch (e) {
      logMessage('노선 검색 결과 파싱 오류: $e', level: LogLevel.error);
      return [];
    }
  }
}
