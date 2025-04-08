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

// 주변 정류장 가져오기 - 반경 단위를 미터로 직접 사용
  static Future<List<BusStop>> getNearbyStations(double radiusMeters,
      {BuildContext? context}) async {
    try {
      // 위치 권한 확인 먼저 수행
      bool hasPermission = await Permission.location.isGranted;
      if (!hasPermission) {
        debugPrint('위치 권한이 없습니다. 권한 수동 요청 완료된 화면으로 넘어갑니다.');
        
        // 전달하는 정보가 없는 경우 권한이 없음을 알리기 위한 확인
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('주변 정류장을 검색하려면 위치 권한이 필요합니다.')),
          );
        }
        
        // 권한이 없어도 앱이 멈추지 않도록 비어있는 리스트 반환
        return [];
      }
      
      final position = await getCurrentLocation();

      if (position == null) {
        if (context != null && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 정보를 가져올 수 없습니다. 위치 서비스를 확인해주세요.')),
          );
        }
        return [];
      }

      debugPrint(
          '좌표 검색 파라미터: lat=${position.latitude}, lon=${position.longitude}, radius=${radiusMeters}m');

      return await ApiService.getNearbyStations(
          position.latitude, position.longitude, radiusMeters);
    } catch (e) {
      debugPrint('주변 정류장을 가져오는 중 오류 발생: $e');
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('주변 정류장을 가져오는 중 오류가 발생했습니다: $e')),
        );
      }
      return [];
    }
  }
}
