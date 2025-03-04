import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/bus_arrival.dart';

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
  Future<List<BusArrivalInfo>> getStationInfo(String stationId) async {
    try {
      final String jsonResult = await _channel.invokeMethod('getStationInfo', {
        'stationId': stationId,
      });

      final List<dynamic> decoded = jsonDecode(jsonResult);
      return decoded.map((info) => BusArrivalInfo.fromJson(info)).toList();
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
      final String jsonResult =
          await _channel.invokeMethod('getBusArrivalByRouteId', {
        'stationId': stationId,
        'routeId': routeId,
      });

      final dynamic decoded = jsonDecode(jsonResult);
      return BusArrivalInfo.fromJson(decoded);
    } on PlatformException catch (e) {
      debugPrint('노선별 도착 정보 조회 오류: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('예상치 못한 오류: $e');
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
  BusArrival convertToBusArrival(BusArrivalInfo info) {
    List<BusInfo> buses = info.bus.map((busInfo) {
      // 버스 번호에서 저상버스 정보 추출
      bool isLowFloor = busInfo.busNumber.contains('저상');
      String busNumber =
          busInfo.busNumber.replaceAll(RegExp(r'\(저상\)|\(일반\)'), '');

      // 남은 정류소에서 숫자만 추출
      String remainingStations = busInfo.remainingStations;
      int remainingStops = int.tryParse(
            remainingStations.replaceAll(RegExp(r'[^0-9]'), ''),
          ) ??
          0;

      // 도착 예정 시간 처리
      String estimatedTime = busInfo.estimatedTime;
      String arrivalTime = estimatedTime;

      return BusInfo(
        busNumber: busNumber,
        isLowFloor: isLowFloor,
        currentStation: busInfo.currentStation,
        remainingStops: remainingStops.toString(),
        arrivalTime: arrivalTime,
      );
    }).toList();

    return BusArrival(
      routeId: info.id,
      routeNo: info.name,
      destination: info.forward,
      buses: buses,
    );
  }
}

// 정류장 검색 결과 데이터 클래스
class StationSearchResult {
  final String bsId;
  final String bsNm;

  StationSearchResult({
    required this.bsId,
    required this.bsNm,
  });

  factory StationSearchResult.fromJson(Map<String, dynamic> json) {
    return StationSearchResult(
      bsId: json['bsId'],
      bsNm: json['bsNm'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bsId': bsId,
      'bsNm': bsNm,
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
    return BusInfoData(
      busNumber: json['버스번호'] ?? '',
      currentStation: json['현재정류소'] ?? '',
      remainingStations: json['남은정류소'] ?? '',
      estimatedTime: json['도착예정소요시간'] ?? '',
    );
  }
}
