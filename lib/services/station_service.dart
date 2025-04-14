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

  /// 버스 도착 정보 결과를 BusArrival 객체로 변환
  List<BusArrival> _parseBusArrivalResult(String jsonString) {
    try {
      final List<dynamic> routeList = jsonDecode(jsonString);
      final List<BusArrival> result = [];

      for (var route in routeList) {
        try {
          final String routeNo = route['routeNo'] ?? '';
          final List<dynamic>? arrList = route['arrList'];

          if (arrList == null || arrList.isEmpty) continue;

          // 같은 노선ID의 버스 정보 리스트 수집
          final Map<String, List<BusInfo>> routeGroups = {};

          for (var arrival in arrList) {
            final String routeId = arrival['routeId'] ?? '';
            final String direction = arrival['moveDir'] ?? '';
            final String groupKey = '$routeId:$direction';

            if (!routeGroups.containsKey(groupKey)) {
              routeGroups[groupKey] = [];
            }

            // BusInfo 생성 전에 필드 변환
            final Map<String, dynamic> busInfoMap = {
              'busNumber': arrival['vhcNo2'] ?? '',
              'currentStation': arrival['bsNm'] ?? '',
              'remainingStops': arrival['bsGap']?.toString() ?? '0',
              'estimatedTime':
                  arrival['arrState'] ?? arrival['bsGap']?.toString() ?? '',
              'isLowFloor': arrival['busTCd2'] == '1',
              'isOutOfService': arrival['busTCd3'] == '1',
            };

            // 디버그 로그 추가
            logMessage('도착 정보 데이터: ${arrival['arrState']}',
                level: LogLevel.debug);

            routeGroups[groupKey]!.add(BusInfo.fromJson(busInfoMap));
          }

          // 그룹별로 BusArrival 객체 생성
          routeGroups.forEach((key, busInfoList) {
            final parts = key.split(':');
            final String routeId = parts[0];
            final String direction = parts.length > 1 ? parts[1] : '';

            result.add(BusArrival(
              routeNo: routeNo,
              routeId: routeId,
              busInfoList: busInfoList,
              direction: direction,
            ));

            // 로그로 확인
            if (busInfoList.isNotEmpty) {
              logMessage(
                  '버스 도착 정보: routeNo=$routeNo, estimatedTime=${busInfoList.first.estimatedTime}',
                  level: LogLevel.debug);
            }
          });
        } catch (e) {
          logMessage('도착 정보 개별 파싱 오류: $e', level: LogLevel.error);
        }
      }

      return result;
    } catch (e) {
      logMessage('도착 정보 파싱 오류: $e', level: LogLevel.error);
      return [];
    }
  }
}
