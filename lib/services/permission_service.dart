import 'dart:io';
import 'package:daegu_bus_app/main.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/services.dart';

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
        logMessage('🔔 알림 권한 승인됨', level: LogLevel.info);
      } else if (status.isPermanentlyDenied) {
        logMessage('⚠️ 알림 권한 영구 거부 → 설정 페이지 유도', level: LogLevel.warning);
        openAppSettings();
      } else {
        logMessage('❌ 알림 권한 거부됨', level: LogLevel.warning);
      }

      // flutter_local_notifications에서도 확인
      final androidPlugin =
          flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final bool? granted =
          await androidPlugin?.requestNotificationsPermission();

      logMessage(
          'flutter_local_notifications 권한 상태: ${granted == true ? "OK" : "거부"}',
          level: LogLevel.info);
    } else {
      logMessage('ℹ️ Android 12 이하 → 알림 권한 요청 생략됨 (SDK: $sdkVersion)',
          level: LogLevel.debug);
    }
  }

  /// 위치 권한 요청 (Foreground)
  static Future<void> requestLocationPermission() async {
    final status = await Permission.locationWhenInUse.request();

    if (status.isGranted) {
      logMessage('📍 위치 권한 승인됨', level: LogLevel.info);
    } else if (status.isPermanentlyDenied) {
      logMessage('📍 위치 권한 영구 거부 → 설정으로 이동', level: LogLevel.warning);
      openAppSettings();
    } else {
      logMessage('📍 위치 권한 거부됨', level: LogLevel.warning);
    }
  }

  /// 백그라운드 위치 권한 (필요시)
  static Future<void> requestBackgroundLocationPermission() async {
    final status = await Permission.locationAlways.request();

    if (status.isGranted) {
      logMessage('📡 백그라운드 위치 권한 승인됨', level: LogLevel.info);
    } else if (status.isPermanentlyDenied) {
      logMessage('📡 백그라운드 위치 영구 거부됨 → 설정 이동 필요', level: LogLevel.warning);
      openAppSettings();
    } else {
      logMessage('📡 백그라운드 위치 권한 거부됨', level: LogLevel.warning);
    }
  }

  /// 정확한 알람 권한 요청 (Android 12+)
  static Future<void> requestExactAlarmPermission() async {
    if (!Platform.isAndroid) return;

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final sdkVersion = androidInfo.version.sdkInt;

      if (sdkVersion >= 31) {
        // Android 12+
        final status = await Permission.scheduleExactAlarm.request();

        if (status.isGranted) {
          logMessage('⏰ 정확한 알람 권한 승인됨', level: LogLevel.info);
        } else if (status.isPermanentlyDenied) {
          logMessage('⚠️ 정확한 알람 권한 영구 거부 → 설정 페이지 유도', level: LogLevel.warning);
          openAppSettings();
        } else {
          logMessage('❌ 정확한 알람 권한 거부됨', level: LogLevel.warning);
        }
      } else {
        logMessage('ℹ️ Android 11 이하 → 정확한 알람 권한 요청 생략됨',
            level: LogLevel.debug);
      }
    } catch (e) {
      logMessage('❌ 정확한 알람 권한 요청 오류: $e', level: LogLevel.error);
    }
  }

  /// 배터리 최적화 제외 요청
  static Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;

    try {
      const methodChannel =
          MethodChannel('com.example.daegu_bus_app/permission');

      // 먼저 현재 상태 확인
      final bool isIgnored =
          await methodChannel.invokeMethod('isIgnoringBatteryOptimizations');

      if (isIgnored) {
        logMessage('🔋 이미 배터리 최적화에서 제외됨', level: LogLevel.info);
        return;
      }

      // 배터리 최적화 제외 요청
      final bool result =
          await methodChannel.invokeMethod('requestIgnoreBatteryOptimizations');

      if (result) {
        logMessage('🔋 배터리 최적화 제외 요청 성공', level: LogLevel.info);
      } else {
        logMessage('⚠️ 배터리 최적화 제외 요청 실패', level: LogLevel.warning);
      }
    } catch (e) {
      logMessage('❌ 배터리 최적화 요청 오류: $e', level: LogLevel.error);

      // 폴백: permission_handler 사용
      try {
        final status = await Permission.ignoreBatteryOptimizations.request();
        if (status.isGranted) {
          logMessage('🔋 배터리 최적화 제외 승인됨 (폴백)', level: LogLevel.info);
        } else {
          logMessage('⚠️ 배터리 최적화 제외 거부됨 (폴백)', level: LogLevel.warning);
        }
      } catch (e2) {
        logMessage('❌ 배터리 최적화 폴백 요청 오류: $e2', level: LogLevel.error);
      }
    }
  }

  /// 자동 시작 권한 확인 및 안내
  static Future<void> checkAutoStartPermission() async {
    if (!Platform.isAndroid) return;

    try {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      final manufacturer = androidInfo.manufacturer.toLowerCase();

      // 제조사별 자동 시작 설정 안내
      if (manufacturer.contains('xiaomi') || manufacturer.contains('redmi')) {
        logMessage('📱 Xiaomi/Redmi 기기: 자동 시작 허용을 수동으로 설정해주세요',
            level: LogLevel.info);
      } else if (manufacturer.contains('huawei') ||
          manufacturer.contains('honor')) {
        logMessage('📱 Huawei/Honor 기기: 앱 시작 관리에서 수동 관리로 설정해주세요',
            level: LogLevel.info);
      } else if (manufacturer.contains('oppo')) {
        logMessage('📱 Oppo 기기: 개인정보 보호 권한에서 자동 시작 허용해주세요',
            level: LogLevel.info);
      } else if (manufacturer.contains('vivo')) {
        logMessage('📱 Vivo 기기: 백그라운드 앱 새로고침을 허용해주세요', level: LogLevel.info);
      } else if (manufacturer.contains('samsung')) {
        logMessage('📱 Samsung 기기: 배터리 설정에서 앱을 최적화하지 않음으로 설정해주세요',
            level: LogLevel.info);
      }
    } catch (e) {
      logMessage('❌ 자동 시작 권한 확인 오류: $e', level: LogLevel.error);
    }
  }

  /// 필요한 모든 권한 요청 일괄 실행 (초기 실행 시 사용)
  static Future<void> requestAllPermissions() async {
    logMessage('필요한 모든 권한 요청 시작', level: LogLevel.info);
    await requestNotificationPermission();
    await requestLocationPermission();
    // await requestBackgroundLocationPermission(); // 필요시 활성화
    await requestExactAlarmPermission();
    await requestIgnoreBatteryOptimizations();
    await checkAutoStartPermission();
  }
}
