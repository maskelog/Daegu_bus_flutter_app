import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/bus_stop.dart';
import '../utils/coordinate_converter.dart';
import 'api_service.dart';

class LocationService {
  // 위치 권한 요청
  static Future<bool> requestLocationPermission() async {
    // 위치 권한 상태 확인
    final status = await Permission.location.status;
    if (status.isDenied) {
      // 권한 요청
      final result = await Permission.location.request();
      return result.isGranted;
    }
    if (status.isPermanentlyDenied) {
      // 사용자가 권한을 영구적으로 거부한 경우 설정 화면으로 이동
      return false;
    }
    return status.isGranted;
  }

  // 현재 위치 가져오기
  static Future<Position?> getCurrentLocation() async {
    final hasPermission = await requestLocationPermission();
    if (!hasPermission) {
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 100, // 100미터마다 위치 업데이트
        ),
      );
    } catch (e) {
      debugPrint('Error getting current location: $e');
      return null;
    }
  }

  // 두 위치 사이의 거리 계산 (미터 단위)
  static double calculateDistance(
      double lat1, double lon1, double lat2, double lon2) {
    return Geolocator.distanceBetween(lat1, lon1, lat2, lon2);
  }

  // 주변 정류장 가져오기
  static Future<List<BusStop>> getNearbyStations(
      double maxDistanceInMeters) async {
    final Position? position = await getCurrentLocation();
    if (position == null) {
      return [];
    }
    try {
      // API 서비스를 통해 모든 정류장 정보 가져오기
      final allStations = await ApiService.getAllStations();

      // 현재 위치 기준으로 정렬
      final nearbyStations = allStations.where((station) {
        // NGISXPos와 NGISYPos가 있는 정류장만 대상으로 함
        if (station.ngisXPos == null || station.ngisYPos == null) {
          return false;
        }
        try {
          // NGIS 좌표를 위도/경도로 변환
          final double ngisX = double.parse(station.ngisXPos!);
          final double ngisY = double.parse(station.ngisYPos!);

          // 좌표 변환
          final convertedCoords =
              CoordinateConverter.convertNGISToLatLon(ngisX, ngisY);
          final double stationLat = convertedCoords[0];
          final double stationLon = convertedCoords[1];

          // 거리 계산
          final distance = calculateDistance(
              position.latitude, position.longitude, stationLat, stationLon);

          // 거리 정보 추가
          station.copyWith(distance: distance.toStringAsFixed(0));

          // 최대 거리 이내의 정류장만 반환
          return distance <= maxDistanceInMeters;
        } catch (e) {
          debugPrint('Error converting or calculating distance: $e');
          return false;
        }
      }).toList();

      // 거리 순으로 정렬
      nearbyStations.sort((a, b) {
        final distanceA = double.tryParse(a.distance ?? '0') ?? 0;
        final distanceB = double.tryParse(b.distance ?? '0') ?? 0;
        return distanceA.compareTo(distanceB);
      });

      return nearbyStations;
    } catch (e) {
      debugPrint('Error getting nearby stations: $e');
      return [];
    }
  }
}
