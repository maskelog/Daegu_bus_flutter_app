import 'dart:async';
import 'package:flutter/services.dart';
import '../models/bus_arrival.dart';
import '../models/bus_stop.dart';
import '../models/bus_route.dart';

// 새로운 서비스 가져오기
import 'station_service.dart';
import 'route_service.dart';

/// 버스 API 서비스 (이전 버전과의 호환성 유지)
class ApiService {
  // 메소드 채널 추가
  static const MethodChannel _channel =
      MethodChannel('com.example.daegu_bus_app/api');

  // 싱글톤 패턴 적용
  static final ApiService _instance = ApiService._internal();

  // 정류장 서비스와 노선 서비스의 인스턴스
  final StationService _stationService;
  final RouteService _routeService;

  // 내부 생성자로 싱글톤 구현
  ApiService._internal()
      : _stationService = StationService(),
        _routeService = RouteService();

  // 싱글톤 인스턴스에 접근하기 위한 팩토리 생성자
  factory ApiService() => _instance;

  /// 정류장 검색 API
  static Future<List<BusStop>> searchStations(String searchText) async {
    return _instance._stationService.searchStations(searchText);
  }

  /// 로컬 DB에서 정류장 검색 API
  static Future<List<BusStop>> searchStationsLocal(String searchText) async {
    return _instance._stationService.searchStationsLocal(searchText);
  }

  /// 주변 정류장 검색 API
  static Future<List<BusStop>> findNearbyStations(
      double latitude, double longitude,
      {double radiusMeters = 500}) async {
    return _instance._stationService
        .findNearbyStations(latitude, longitude, radiusMeters: radiusMeters);
  }

  /// 정류장 도착 정보 조회 API
  static Future<List<BusArrival>> getStationInfo(String stationId) async {
    return _instance._stationService.getStationInfo(stationId);
  }

  /// 버스 노선 검색 API
  static Future<List<BusRoute>> searchBusRoutes(String searchText) async {
    return _instance._routeService.searchBusRoutes(searchText);
  }

  /// 버스 노선 상세 정보 조회 API
  static Future<BusRoute?> getBusRouteDetails(String routeId) async {
    return _instance._routeService.getBusRouteDetails(routeId);
  }

  /// 버스 위치 정보 조회 API
  static Future<List<dynamic>> getBusPositionInfo(String routeId) async {
    return _instance._routeService.getBusPositionInfo(routeId);
  }

  /// 노선별 버스 도착 정보 조회 API
  static Future<List<BusArrival>> getBusArrivalByRouteId(
      String stationId, String routeId) async {
    return _instance._routeService.getBusArrivalByRouteId(stationId, routeId);
  }

  /// 노선 정류장 목록 조회 API
  static Future<List<dynamic>> getRouteStations(String routeId) async {
    return _instance._routeService.getRouteStations(routeId);
  }

  /// bsId를 stationId로 변환 API
  static Future<String?> getStationIdFromBsId(String bsId) async {
    // StationService의 getStationIdFromBsId 메서드를 호출
    try {
      return await _instance._stationService.getStationIdFromBsId(bsId);
    } catch (e) {
      return null;
    }
  }

  /// 주변 정류장 검색 API - LocationService에서 사용
  static Future<List<BusStop>> getNearbyStations(
      double latitude, double longitude, double radiusMeters) async {
    return _instance._stationService.findNearbyStations(
      latitude,
      longitude,
      radiusMeters: radiusMeters,
    );
  }

  /// 네이티브 API를 직접 호출하는 메소드 (백그라운드 작업에서 안정적으로 동작)
  static Future<dynamic> callNativeApi(
      String method, Map<String, dynamic> params) async {
    try {
      final result = await _channel.invokeMethod(method, params);
      return result;
    } on PlatformException catch (e) {
      print('네이티브 API 호출 오류: ${e.message}');
      return null;
    }
  }

  /// 백그라운드에서 알림 표시 메소드
  static Future<bool> showBackgroundNotification({
    required int id,
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String? currentStation,
    String? routeId,
    bool isAutoAlarm = true,
  }) async {
    try {
      // 네이티브 코드에서 Integer 범위를 초과하는 ID를 처리하기 위한 로직
      final int safeNotificationId = id.abs() % 2147483647;

      final result = await callNativeApi('showNotification', {
        'id': safeNotificationId,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': currentStation ?? '자동 알람',
        'payload': routeId,
        'isAutoAlarm': isAutoAlarm,
        'isOngoing': true,
        'routeId': routeId,
        'notificationTime': DateTime.now().millisecondsSinceEpoch,
        'useTTS': true,
        'actions': ['cancel_alarm'],
      });

      return result == true;
    } catch (e) {
      print('백그라운드 알림 표시 오류: $e');
      return false;
    }
  }
}
