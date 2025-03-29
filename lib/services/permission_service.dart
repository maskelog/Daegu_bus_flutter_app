import 'dart:io';
import 'package:daegu_bus_app/main.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:device_info_plus/device_info_plus.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class PermissionService {
  /// 알림 권한 요청 (Android 13 이상만 요청)
  static Future<void> requestNotificationPermission() async {
    if (!Platform.isAndroid) return;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkVersion = androidInfo.version.sdkInt;

    if (sdkVersion >= 33) {
      final status = await Permission.notification.request();

      if (status.isGranted) {
        log('🔔 알림 권한 승인됨', level: LogLevel.info);
      } else if (status.isPermanentlyDenied) {
        log('⚠️ 알림 권한 영구 거부 → 설정 페이지 유도', level: LogLevel.warning);
        openAppSettings();
      } else {
        log('❌ 알림 권한 거부됨', level: LogLevel.warning);
      }

      // flutter_local_notifications에서도 확인
      final androidPlugin =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final bool? granted =
          await androidPlugin?.requestNotificationsPermission();

      log('flutter_local_notifications 권한 상태: ${granted == true ? "OK" : "거부"}',
          level: LogLevel.info);
    } else {
      log('ℹ️ Android 12 이하 → 알림 권한 요청 생략됨 (SDK: $sdkVersion)',
          level: LogLevel.debug);
    }
  }

  /// 위치 권한 요청 (Foreground)
  static Future<void> requestLocationPermission() async {
    final status = await Permission.locationWhenInUse.request();

    if (status.isGranted) {
      log('📍 위치 권한 승인됨', level: LogLevel.info);
    } else if (status.isPermanentlyDenied) {
      log('📍 위치 권한 영구 거부 → 설정으로 이동', level: LogLevel.warning);
      openAppSettings();
    } else {
      log('📍 위치 권한 거부됨', level: LogLevel.warning);
    }
  }

  /// 백그라운드 위치 권한 (필요시)
  static Future<void> requestBackgroundLocationPermission() async {
    final status = await Permission.locationAlways.request();

    if (status.isGranted) {
      log('📡 백그라운드 위치 권한 승인됨', level: LogLevel.info);
    } else if (status.isPermanentlyDenied) {
      log('📡 백그라운드 위치 영구 거부됨 → 설정 이동 필요', level: LogLevel.warning);
      openAppSettings();
    } else {
      log('📡 백그라운드 위치 권한 거부됨', level: LogLevel.warning);
    }
  }

  /// 필요한 모든 권한 요청 일괄 실행 (초기 실행 시 사용)
  static Future<void> requestAllPermissions() async {
    await requestNotificationPermission();
    await requestLocationPermission();
    // await requestBackgroundLocationPermission(); // 필요시 활성화
  }
}
