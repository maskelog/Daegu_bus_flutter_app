import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import '../models/bus_arrival.dart';
import '../models/bus_info.dart';
import '../models/bus_route.dart';
import '../utils/dio_client.dart';
import '../main.dart' show logMessage, LogLevel;

/// 버스 노선 관련 API 서비스
class RouteService {
  static const String _methodChannel = 'com.devground.daegubus/bus_api';
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
    if (routeId.isEmpty) {
      logMessage('노선 ID가 비어있습니다', level: LogLevel.warning);
      return null;
    }

    final nativeFuture = _fetchRouteInfoNative(routeId);
    final directFuture = _fetchRouteInfoDirect(routeId);

    final direct = await directFuture;
    if (_routeHasCorridor(direct)) {
      unawaited(nativeFuture);
      return direct;
    }

    final native = await nativeFuture;
    return _routeHasCorridor(native) ? native : (direct ?? native);
  }

  Future<BusRoute?> _fetchRouteInfoNative(String routeId) async {
    try {
      final result =
          await _callNativeMethod('getBusRouteDetails', {'routeId': routeId});
      if (result == null) return null;
      return BusRoute.fromJson(jsonDecode(result));
    } catch (e) {
      logMessage('노선 상세 정보 네이티브 조회 오류: $e', level: LogLevel.warning);
      return null;
    }
  }

  bool _routeHasCorridor(BusRoute? r) {
    if (r == null) return false;
    final hasStart =
        r.startPoint.trim().isNotEmpty && r.startPoint != '출발지 정보 없음';
    final hasEnd = r.endPoint.trim().isNotEmpty && r.endPoint != '도착지 정보 없음';
    return hasStart && hasEnd;
  }

  Future<BusRoute?> _fetchRouteInfoDirect(String routeId) async {
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: {'User-Agent': 'okhttp/4.12.0'},
        responseType: ResponseType.plain,
      ));
      final resp = await dio.get(
        'https://businfo.daegu.go.kr:8095/dbms_web_api/route/info',
        queryParameters: {'routeId': routeId},
      );
      if (resp.statusCode != 200 || resp.data == null) return null;
      final decoded = jsonDecode(resp.data.toString());
      if (decoded is! Map<String, dynamic>) return null;
      final body = decoded['body'];
      Map<String, dynamic>? info;
      if (body is Map<String, dynamic>) {
        info = body;
      } else if (body is List && body.isNotEmpty && body.first is Map) {
        info = Map<String, dynamic>.from(body.first);
      }
      if (info == null) return null;

      final parts = <String>[];
      final avg = (info['avgTm'] ?? '').toString().trim();
      final comNm = (info['comNm'] ?? '').toString().trim();
      final first = (info['bsFtm'] ?? info['frTm'] ?? '').toString().trim();
      final last = (info['bsLtm'] ?? info['toTm'] ?? '').toString().trim();
      final trips = (info['nCnt'] ?? '').toString().trim();
      if (avg.isNotEmpty && avg != '정보 없음') parts.add('배차간격: $avg');
      if (comNm.isNotEmpty && comNm != '정보 없음') parts.add('업체: $comNm');
      if (first.isNotEmpty) parts.add('첫차: $first');
      if (last.isNotEmpty) parts.add('막차: $last');
      if (trips.isNotEmpty) parts.add('운행횟수: $trips');

      return BusRoute(
        id: (info['routeId'] ?? routeId).toString(),
        routeNo: (info['routeNo'] ?? '').toString(),
        routeTp: (info['routeTCd'] ?? info['routeTp'] ?? '').toString(),
        startPoint: (info['stNm'] ?? '').toString(),
        endPoint: (info['edNm'] ?? '').toString(),
        routeDescription: parts.isEmpty ? null : parts.join(' | '),
      );
    } catch (e) {
      logMessage('노선 상세 직접 조회 오류: $e', level: LogLevel.warning);
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

      // 단일 노선 정보만 포함된 응답을 파싱 (중첩된 JSON 문자열 처리 포함)
      dynamic decoded;
      try {
        decoded = jsonDecode(result);
        // 이중 인코딩된 경우 다시 파싱 시도
        if (decoded is String) {
          try {
            decoded = jsonDecode(decoded);
          } catch (_) {
            // 추가 파싱 실패 시 그대로 둠
          }
        }
      } catch (e) {
        logMessage('노선별 버스 도착 정보 응답 파싱 오류: $e', level: LogLevel.error);
        return [];
      }
      if (decoded is! Map<String, dynamic>) {
        logMessage('노선별 버스 도착 정보 예상치 못한 타입: ${decoded.runtimeType}',
            level: LogLevel.error);
        return [];
      }
      final Map<String, dynamic> data = decoded;

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
            bool isOutOfService =
                estimatedTime == '운행종료' || estimatedTime == '운행 종료';

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
