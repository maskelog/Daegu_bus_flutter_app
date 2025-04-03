import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:daegu_bus_app/utils/tts_helper.dart';

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

  /// 자동 알람 알림 전송 (예약된 시간에 실행)
  Future<bool> showAutoAlarmNotification({
    required int id,
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String? routeId,
  }) async {
    try {
      // 초기화 확인
      await initialize();

      debugPrint(
          '🔔 자동 알람 알림 표시: $busNo, $stationName, $remainingMinutes분 전, ID: $id');

      // Show the initial notification with isOngoing set to true
      final bool result = await _channel.invokeMethod('showNotification', {
        'id': id,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': '자동 알람', // 자동 알람임을 표시
        'payload': routeId, // 필요시 routeId를 페이로드로 전달
        'isAutoAlarm': true, // 자동 알람 식별자
        'isOngoing': true, // Set isOngoing to true for the initial notification
      });

      debugPrint('🔔 자동 알람 알림 표시 완료: $id');
      return result;
    } catch (e) {
      debugPrint('🔔 자동 알람 알림 표시 오류: ${e.toString()}');
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
    bool isOngoing = false,
    String? routeId, // Add routeId parameter
  }) async {
    try {
      debugPrint(
          '🔔 알림 표시 시도: $busNo, $stationName, $remainingMinutes분, ID: $id, isOngoing: $isOngoing, routeId: $routeId');

      final bool result = await _channel.invokeMethod('showNotification', {
        'id': id,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': currentStation,
        'payload': payload,
        'isOngoing': isOngoing,
        'routeId': routeId, // Pass routeId to the native side
      });

      debugPrint('🔔 알림 표시 완료: $id');
      return result;
    } on PlatformException catch (e) {
      debugPrint('🔔 알림 표시 오류: ${e.message}');
      return false;
    }
  }

  /// 버스 도착 임박 알림 (중요도 높음) - TTS 발화와 함께 실행
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

      // TTS 발화를 통해 버스 도착 임박 메시지를 음성으로 안내
      await TTSHelper.speakBusAlert(
        busNo: busNo,
        stationName: stationName,
        remainingMinutes: 0, // 도착 임박이므로 0분으로 처리
        currentStation: currentStation,
        priority: true,
      );
      debugPrint('TTS 실행 요청: $busNo, $stationName');

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
}
