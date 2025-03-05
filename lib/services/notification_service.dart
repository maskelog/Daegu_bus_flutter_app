import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// NotificationService: 네이티브 BusAlertService와 통신하는 Flutter 서비스
class NotificationService {
  static const MethodChannel _channel =
      MethodChannel('com.example.daegu_bus_app/notification');

  // 싱글톤 패턴 구현
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  /// 알림 서비스 초기화
  Future<bool> initialize() async {
    try {
      final bool result = await _channel.invokeMethod('initialize');
      debugPrint('🔔 알림 서비스 초기화 완료');
      return result;
    } on PlatformException catch (e) {
      debugPrint('🔔 알림 서비스 초기화 오류: ${e.message}');
      return false;
    }
  }

  /// 즉시 알림 전송
  Future<bool> showNotification({
    required int id,
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String? currentStation,
    String? payload,
  }) async {
    try {
      debugPrint(
          '🔔 알림 표시 시도: $busNo, $stationName, $remainingMinutes분, ID: $id');

      final bool result = await _channel.invokeMethod('showNotification', {
        'id': id,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': currentStation,
        'payload': payload,
      });

      debugPrint('🔔 알림 표시 완료: $id');
      return result;
    } on PlatformException catch (e) {
      debugPrint('🔔 알림 표시 오류: ${e.message}');
      return false;
    }
  }

  /// 지속적인 버스 위치 추적 알림 시작/업데이트
  Future<bool> showOngoingBusTracking({
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String? currentStation,
    bool isUpdate = false,
  }) async {
    try {
      final bool result =
          await _channel.invokeMethod('showOngoingBusTracking', {
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': currentStation,
        'isUpdate': isUpdate,
      });

      debugPrint(
          '🚌 버스 추적 알림 ${isUpdate ? "업데이트" : "시작"}: $busNo, $remainingMinutes분');
      return result;
    } on PlatformException catch (e) {
      debugPrint('🚌 버스 추적 알림 오류: ${e.message}');
      return false;
    }
  }

  /// 버스 도착 임박 알림 (중요도 높음)
  Future<bool> showBusArrivingSoon({
    required String busNo,
    required String stationName,
    String? currentStation,
  }) async {
    try {
      final bool result = await _channel.invokeMethod('showBusArrivingSoon', {
        'busNo': busNo,
        'stationName': stationName,
        'currentStation': currentStation,
      });

      debugPrint('🚨 버스 도착 임박 알림 표시: $busNo');
      return result;
    } on PlatformException catch (e) {
      debugPrint('🚨 버스 도착 임박 알림 오류: ${e.message}');
      return false;
    }
  }

  /// 알림 취소 메소드
  Future<bool> cancelNotification(int id) async {
    try {
      final bool result = await _channel.invokeMethod('cancelNotification', {
        'id': id,
      });

      debugPrint('🔔 알림 취소: $id');
      return result;
    } on PlatformException catch (e) {
      debugPrint('🔔 알림 취소 오류: ${e.message}');
      return false;
    }
  }

  /// 지속적인 추적 알림 취소
  Future<bool> cancelOngoingTracking() async {
    try {
      final bool result = await _channel.invokeMethod('cancelOngoingTracking');
      debugPrint('🚌 지속적인 추적 알림 취소');
      return result;
    } on PlatformException catch (e) {
      debugPrint('🚌 지속적인 추적 알림 취소 오류: ${e.message}');
      return false;
    }
  }

  /// 모든 알림 취소 메소드
  Future<bool> cancelAllNotifications() async {
    try {
      final bool result = await _channel.invokeMethod('cancelAllNotifications');
      debugPrint('🔔 모든 알림 취소');
      return result;
    } on PlatformException catch (e) {
      debugPrint('🔔 모든 알림 취소 오류: ${e.message}');
      return false;
    }
  }

  /// 테스트 알림 전송
  Future<bool> showTestNotification() async {
    try {
      final bool result = await _channel.invokeMethod('showTestNotification');
      debugPrint('🔔 테스트 알림 전송');
      return result;
    } on PlatformException catch (e) {
      debugPrint('🔔 테스트 알림 오류: ${e.message}');
      return false;
    }
  }
}
