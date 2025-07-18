import 'dart:async';
import 'dart:convert';
import '../models/bus_arrival.dart';
import '../models/bus_info.dart';
import '../models/bus_stop.dart';
import '../utils/dio_client.dart';
import '../main.dart' show logMessage, LogLevel;

/// 버스 정류장 관련 API 서비스
class StationService {
  static const String _methodChannel = 'com.example.daegu_bus_app/bus_api';
  static const int _defaultTimeout = 15; // seconds

  // 사용하는 DioClient 인스턴스
  final DioClient _dioClient;

  // 생성자
  StationService({DioClient? dioClient})
      : _dioClient = dioClient ?? DioClient();

  /// 정류장 검색 API
  Future<List<BusStop>> searchStations(String searchText) async {
    try {
      if (searchText.isEmpty) {
        logMessage('검색어가 비어있습니다', level: LogLevel.warning);
        return [];
      }

      // 네이티브 코드 호출
      final result = await _callNativeMethod(
          'searchStations', {'searchText': searchText, 'searchType': 'web'});

      if (result == null) {
        return [];
      }

      // JSON 변환 및 객체 생성
      return _parseStationSearchResult(result);
    } catch (e) {
      logMessage('정류장 검색 오류: $e', level: LogLevel.error);
      return [];
    }
  }

  /// 로컬 DB에서 정류장 검색 API
  Future<List<BusStop>> searchStationsLocal(String searchText) async {
    try {
      if (searchText.isEmpty) {
        return [];
      }

      final result = await _callNativeMethod(
          'searchStations', {'searchText': searchText, 'searchType': 'local'});

      if (result == null) {
        return [];
      }

      return _parseStationSearchResult(result);
    } catch (e) {
      logMessage('로컬 정류장 검색 오류: $e', level: LogLevel.error);
      return [];
    }
  }

  /// 주변 정류장 검색 API
  Future<List<BusStop>> findNearbyStations(double latitude, double longitude,
      {double radiusMeters = 500}) async {
    try {
      final result = await _callNativeMethod('findNearbyStations', {
        'latitude': latitude,
        'longitude': longitude,
        'radiusMeters': radiusMeters
      });

      if (result == null) {
        return [];
      }

      return _parseStationSearchResult(result);
    } catch (e) {
      logMessage('주변 정류장 검색 오류: $e', level: LogLevel.error);
      return [];
    }
  }

  /// 정류장 도착 정보 조회 API
  Future<List<BusArrival>> getStationInfo(String stationId) async {
    try {
      if (stationId.isEmpty) {
        logMessage('정류장 ID가 비어있습니다', level: LogLevel.warning);
        return [];
      }

      // 원래 ID 보존
      final originalStationId = stationId;

      // stationId 포맷 확인 및 변환
      if (!stationId.startsWith('7') || stationId.length != 10) {
        final convertedId = await getStationIdFromBsId(stationId);
        if (convertedId != null && convertedId.isNotEmpty) {
          stationId = convertedId;
          logMessage('정류장 ID 변환: $originalStationId -> $stationId');
        }
      }

      final result =
          await _callNativeMethod('getStationInfo', {'stationId': stationId});

      if (result == null) {
        return [];
      }

      return _parseBusArrivalResult(result);
    } catch (e) {
      logMessage('정류장 도착 정보 조회 오류: $e', level: LogLevel.error);
      return [];
    }
  }

  /// bsId(wincId)를 stationId로 변환
  Future<String?> getStationIdFromBsId(String bsId) async {
    try {
      if (bsId.isEmpty) {
        return null;
      }

      // 이미 올바른 형식이면 그대로 반환
      if (bsId.startsWith('7') && bsId.length == 10) {
        return bsId;
      }

      final result =
          await _callNativeMethod('getStationIdFromBsId', {'bsId': bsId});

      return result;
    } catch (e) {
      logMessage('정류장 ID 변환 오류: $e', level: LogLevel.error);
      return null;
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

  /// 정류장 검색 결과를 BusStop 객체로 변환
  List<BusStop> _parseStationSearchResult(String jsonString) {
    try {
      final List<dynamic> data = jsonDecode(jsonString);
      return data.map((station) => BusStop.fromJson(station)).toList();
    } catch (e) {
      logMessage('정류장 검색 결과 파싱 오류: $e', level: LogLevel.error);
      return [];
    }
  }

  /// 버스 도착 정보 결과를 BusArrival 객체로 변환 (v2)
  List<BusArrival> _parseBusArrivalResult(String jsonString) {
    try {
      final dynamic decodedData = jsonDecode(jsonString);
      final List<dynamic> routeList;

      // 데이터가 리스트가 아니면 리스트로 감싸줌
      if (decodedData is Map<String, dynamic>) {
        routeList = [decodedData];
      } else if (decodedData is List) {
        routeList = decodedData;
      } else {
        logMessage('도착 정보 형식이 올바르지 않습니다: ${decodedData.runtimeType}',
            level: LogLevel.error);
        return [];
      }

      final List<BusArrival> result = [];
      final Map<String, BusArrival> busArrivalMap = {};

      for (var routeData in routeList) {
        if (routeData is! Map<String, dynamic>) continue;

        final List<dynamic>? arrList = routeData['arrList'];
        if (arrList == null || arrList.isEmpty) continue;

        for (var arrivalData in arrList) {
          if (arrivalData is! Map<String, dynamic>) continue;

          final String routeId = arrivalData['routeId'] ?? '';
          final String routeNo = arrivalData['routeNo'] ?? routeData['routeNo'] ?? '';
          final String direction = arrivalData['moveDir'] ?? '';
          final String key = '$routeId-$direction';

          final busInfo = BusInfo(
            busNumber: arrivalData['vhcNo2'] ?? '',
            currentStation: arrivalData['bsNm'] ?? '정보 없음',
            remainingStops: (arrivalData['bsGap'] ?? 0).toString(),
            estimatedTime: arrivalData['arrState'] ?? '정보 없음',
            isLowFloor: arrivalData['busTCd2'] == '1',
            isOutOfService: arrivalData['busTCd3'] == '1',
          );

          if (busArrivalMap.containsKey(key)) {
            busArrivalMap[key]!.busInfoList.add(busInfo);
          } else {
            busArrivalMap[key] = BusArrival(
              routeId: routeId,
              routeNo: routeNo,
              direction: direction,
              busInfoList: [busInfo],
            );
          }
        }
      }

      result.addAll(busArrivalMap.values);

      if (result.isNotEmpty) {
        logMessage('${result.length}개의 노선 도착 정보 파싱 성공', level: LogLevel.debug);
      }

      return result;
    } catch (e) {
      logMessage('도착 정보 파싱 오류: $e', level: LogLevel.error);
      return [];
    }
  }
}
