import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/bus_arrival.dart';
import '../models/bus_info.dart';

class BusApiService {
  static const MethodChannel _channel =
      MethodChannel('com.example.daegu_bus_app/bus_api');

  // 싱글톤 패턴 구현
  static final BusApiService _instance = BusApiService._internal();

  factory BusApiService() => _instance;

  BusApiService._internal();

  // 정류장 검색 메소드
  Future<List<StationSearchResult>> searchStations(String searchText) async {
    try {
      final String jsonResult = await _channel.invokeMethod('searchStations', {
        'searchText': searchText,
      });

      final List<dynamic> decoded = jsonDecode(jsonResult);
      return decoded
          .map((station) => StationSearchResult.fromJson(station))
          .toList();
    } on PlatformException catch (e) {
      debugPrint('정류장 검색 오류: ${e.message}');
      return [];
    } catch (e) {
      debugPrint('예상치 못한 오류: $e');
      return [];
    }
  }

  // 정류장 도착 정보 조회 메소드
  Future<List<BusArrival>> getStationInfo(String stationId) async {
    try {
      final String jsonResult = await _channel.invokeMethod('getStationInfo', {
        'stationId': stationId,
      });

      final List<dynamic> decoded = jsonDecode(jsonResult);
      // 디버그 모드에서만 로그 출력
      assert(() {
        debugPrint('정류장 도착 정보 조회 성공: ${decoded.length}개 버스');
        return true;
      }());

      return decoded
          .map((info) =>
              convertToBusArrival(BusArrivalInfo.fromJson(info), stationId))
          .toList();
    } on PlatformException catch (e) {
      debugPrint('정류장 정보 조회 오류: ${e.message}');
      return [];
    } catch (e) {
      debugPrint('예상치 못한 오류: $e');
      return [];
    }
  }

  // 특정 노선의 도착 정보 조회 메소드
  Future<BusArrivalInfo?> getBusArrivalByRouteId(
      String stationId, String routeId) async {
    try {
      // 입력 유효성 검사
      if (stationId.isEmpty || routeId.isEmpty) {
        debugPrint('❌ [ERROR] 정류장 ID 또는 노선 ID가 비어있습니다');
        return null;
      }

      debugPrint('🐛 [DEBUG] 자동 알람 버스 정보 업데이트 시도: $routeId, $stationId');

      final dynamic result =
          await _channel.invokeMethod('getBusArrivalByRouteId', {
        'stationId': stationId,
        'routeId': routeId,
      });

      // 응답 유형 확인 및 로깅
      if (result is String) {
        debugPrint('🐛 [DEBUG] API 응답이 String 형식입니다');

        // 빈 문자열이거나 유효하지 않은 경우 처리
        if (result.isEmpty || result == 'null' || result == '[]') {
          debugPrint('🐛 [DEBUG] 빈 응답이거나 정보가 없음: "$result"');
          return null;
        }

        try {
          final dynamic decoded = jsonDecode(result);

          // 배열 형식으로 온 경우 첫 번째 항목 사용
          if (decoded is List && decoded.isNotEmpty) {
            debugPrint('🐛 [DEBUG] 배열 형식의 응답, 첫 번째 항목 사용');
            return BusArrivalInfo.fromJson(decoded[0]);
          }

          // 객체 형식으로 온 경우
          if (decoded is Map<String, dynamic>) {
            // 자동 알람에서 오는 응답 형식 처리 (routeNo 필드가 있는 경우)
            if (decoded.containsKey('routeNo')) {
              debugPrint('🐛 [DEBUG] 자동 알람 응답 형식 감지됨');
              // 필요한 필드 구성
              final Map<String, dynamic> formattedResponse = {
                'name': decoded['routeNo'] ?? '',
                'sub': '',
                'id': routeId,
                'forward': decoded['moveDir'] ?? '알 수 없음',
                'bus': []
              };

              // arrList 필드가 있으면 처리
              if (decoded.containsKey('arrList') &&
                  decoded['arrList'] is List) {
                final List<dynamic> arrList = decoded['arrList'];
                final List<Map<String, dynamic>> busInfoList = [];

                for (var arr in arrList) {
                  if (arr is Map<String, dynamic>) {
                    busInfoList.add({
                      '버스번호': arr['vhcNo2'] ?? '',
                      '현재정류소': arr['bsNm'] ?? '',
                      '남은정류소': '${arr['bsGap'] ?? 0} 개소',
                      '도착예정소요시간': arr['arrState'] ?? '${arr['bsGap'] ?? 0}분',
                    });
                  }
                }

                formattedResponse['bus'] = busInfoList;
              }

              return BusArrivalInfo.fromJson(formattedResponse);
            }

            return BusArrivalInfo.fromJson(decoded);
          }

          debugPrint('❌ [ERROR] 예상치 못한 JSON 구조: ${decoded.runtimeType}');
          // 디버깅을 위해 원본 데이터 출력
          debugPrint('❌ [ERROR] 원본 데이터: $decoded');
          return null;
        } catch (e) {
          debugPrint('❌ [ERROR] JSON 파싱 오류: $e, 원본 문자열: "$result"');
          return null;
        }
      } else {
        // String이 아닌 경우 (이미 Map 등으로 파싱된 경우)
        debugPrint('🐛 [DEBUG] API 응답이 ${result.runtimeType} 형식입니다');
        if (result is Map<String, dynamic>) {
          return BusArrivalInfo.fromJson(result);
        } else {
          debugPrint('❌ [ERROR] 지원되지 않는 응답 형식: ${result.runtimeType}');
          return null;
        }
      }
    } on PlatformException catch (e) {
      debugPrint('❌ [ERROR] 노선별 도착 정보 조회 오류: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('❌ [ERROR] 예상치 못한 오류: $e');
      return null;
    }
  }

  // 버스 노선 정보 조회 메소드
  Future<Map<String, dynamic>?> getBusRouteInfo(String routeId) async {
    try {
      final String jsonResult = await _channel.invokeMethod('getBusRouteInfo', {
        'routeId': routeId,
      });

      return jsonDecode(jsonResult);
    } on PlatformException catch (e) {
      debugPrint('버스 노선 정보 조회 오류: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('예상치 못한 오류: $e');
      return null;
    }
  }

  // 실시간 버스 위치 정보 조회 메소드
  Future<Map<String, dynamic>?> getBusPositionInfo(String routeId) async {
    try {
      final String jsonResult =
          await _channel.invokeMethod('getBusPositionInfo', {
        'routeId': routeId,
      });

      return jsonDecode(jsonResult);
    } on PlatformException catch (e) {
      debugPrint('실시간 버스 위치 정보 조회 오류: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('예상치 못한 오류: $e');
      return null;
    }
  }

  // BusArrivalInfo를 BusArrival로 변환하는 헬퍼 메소드
  BusArrival convertToBusArrival(BusArrivalInfo info, String stationId) {
    List<BusInfo> busInfoList = info.bus.map((busInfo) {
      // 버스 번호에서 저상버스 정보 추출
      bool isLowFloor = busInfo.busNumber.contains('저상');
      String busNumber =
          busInfo.busNumber.replaceAll(RegExp(r'\(저상\)|\(일반\)'), '');

      // 남은 정류소에서 숫자만 추출
      String remainingStations = busInfo.remainingStations;

      // 도착 예정 시간 처리
      String estimatedTime = busInfo.estimatedTime;

      // 운행 종료 여부 확인
      bool isOutOfService = estimatedTime == '운행종료';

      return BusInfo(
        busNumber: busNumber,
        isLowFloor: isLowFloor,
        currentStation: busInfo.currentStation,
        remainingStops: remainingStations,
        estimatedTime: estimatedTime,
        isOutOfService: isOutOfService,
      );
    }).toList();

    return BusArrival(
      routeId: info.id,
      routeNo: info.name,
      direction: info.forward,
      busInfoList: busInfoList,
    );
  }
}

// 정류장 검색 결과 데이터 클래스
class StationSearchResult {
  final String bsId;
  final String bsNm;
  final double? latitude;
  final double? longitude;

  StationSearchResult({
    required this.bsId,
    required this.bsNm,
    this.latitude,
    this.longitude,
  });

  factory StationSearchResult.fromJson(Map<String, dynamic> json) {
    return StationSearchResult(
      bsId: json['bsId'] as String,
      // 네이티브 쪽에서는 컬럼명이 "stop_name"일 수 있으므로 fallback 처리
      bsNm: json['bsNm'] ?? json['stop_name'] ?? '',
      latitude: json['latitude'] != null
          ? (json['latitude'] as num).toDouble()
          : null,
      longitude: json['longitude'] != null
          ? (json['longitude'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bsId': bsId,
      'bsNm': bsNm,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}

// 버스 도착 정보 결과 데이터 클래스
class BusArrivalInfo {
  final String name; // 노선 이름
  final String sub; // 노선 부제목
  final String id; // 노선 ID
  final String forward; // 방면 (종점)
  final List<BusInfoData> bus; // 버스 목록

  BusArrivalInfo({
    required this.name,
    required this.sub,
    required this.id,
    required this.forward,
    required this.bus,
  });

  factory BusArrivalInfo.fromJson(Map<String, dynamic> json) {
    return BusArrivalInfo(
      name: json['name'],
      sub: json['sub'],
      id: json['id'],
      forward: json['forward'],
      bus: (json['bus'] as List)
          .map((bus) => BusInfoData.fromJson(bus))
          .toList(),
    );
  }
}

class BusInfoData {
  final String busNumber;
  final String currentStation;
  final String remainingStations;
  final String estimatedTime;

  BusInfoData({
    required this.busNumber,
    required this.currentStation,
    required this.remainingStations,
    required this.estimatedTime,
  });

  factory BusInfoData.fromJson(Map<String, dynamic> json) {
    // 자동 알람에서 오는 응답 형식 처리
    if (json.containsKey('vhcNo2') || json.containsKey('bsNm')) {
      return BusInfoData(
        busNumber: json['vhcNo2'] ?? '',
        currentStation: json['bsNm'] ?? '',
        remainingStations: '${json['bsGap'] ?? 0} 개소',
        estimatedTime: json['arrState'] ?? '${json['bsGap'] ?? 0}분',
      );
    }

    // 기본 형식 처리
    return BusInfoData(
      busNumber: json['버스번호'] ?? '',
      currentStation: json['현재정류소'] ?? '',
      remainingStations: json['남은정류소'] ?? '',
      estimatedTime: json['도착예정소요시간'] ?? '',
    );
  }
}
