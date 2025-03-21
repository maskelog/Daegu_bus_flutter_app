import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/bus_stop.dart';
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

  // 위치 서비스 및 권한 확인 (context 필요)
  static Future<bool> checkLocationPermission(BuildContext context) async {
    // 위치 서비스가 활성화되어 있는지 확인
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // 위치 서비스가 비활성화된 경우 사용자에게 알림
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('위치 서비스가 비활성화되어 있습니다. 설정에서 활성화해주세요.'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: '설정',
              onPressed: () async {
                await Geolocator.openLocationSettings();
              },
            ),
          ),
        );
      }
      return false;
    }

    // 위치 권한 확인
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      // 권한이 거부된 경우, 사용자에게 권한 요청
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        // 사용자가 권한 요청을 거부한 경우
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('주변 정류장을 찾으려면 위치 권한이 필요합니다.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      // 사용자가 권한을 영구적으로 거부한 경우
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('위치 권한이 영구적으로 거부되었습니다. 설정에서 권한을 허용해주세요.'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: '설정',
              onPressed: () async {
                await openAppSettings();
              },
            ),
          ),
        );
      }
      return false;
    }

    // 권한이 허용된 경우
    return true;
  }

  // 주변 정류장 가져오기 (context 매개변수 추가)
  static Future<List<BusStop>> getNearbyStations(double maxDistanceInMeters,
      {BuildContext? context}) async {
    // context가 제공된 경우 권한 확인
    if (context != null) {
      bool hasPermission = await checkLocationPermission(context);
      if (!hasPermission) {
        return [];
      }
    }

    try {
      final Position? position = await getCurrentLocation();
      if (position == null) {
        debugPrint('위치를 가져올 수 없습니다.');
        return [];
      }

      debugPrint(
          '현재 GPS 위치: lat=${position.latitude}, lon=${position.longitude}');

      // ApiService의 새 메서드 사용
      return await ApiService.getNearbyStations(
          position.latitude, position.longitude, maxDistanceInMeters);
    } catch (e) {
      debugPrint('Error getting nearby stations: $e');
      return [];
    }
  }
}
