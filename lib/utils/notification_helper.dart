import 'dart:async';
import 'package:daegu_bus_app/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:daegu_bus_app/utils/tts_helper.dart';

/// NotificationService: 네이티브 BusAlertService와 통신하는 Flutter 서비스
class NotificationService {
  static const MethodChannel _channel =
      MethodChannel('com.example.daegu_bus_app/notification');

  // 싱글톤 패턴 구현
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  Timer? _trackingTimer; // 실시간 추적용 타이머

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

  /// 실시간 버스 추적 시작
  Future<void> startRealTimeTracking({
    required String busNo,
    required String stationName,
    required int initialRemainingMinutes,
    required String routeId,
    required String stationId,
    required Function(int) onUpdateRemainingTime, // 남은 시간 업데이트 콜백
    required VoidCallback onTrackingStopped, // 추적 종료 콜백
  }) async {
    int remainingTime = initialRemainingMinutes;
    _trackingTimer?.cancel(); // 기존 타이머 해제

    _trackingTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      try {
        // API 호출로 최신 버스 정보 가져오기
        final updatedBusArrival = await ApiService.getBusArrivalByRouteId(
          stationId,
          routeId,
        );

        if (updatedBusArrival != null && updatedBusArrival.buses.isNotEmpty) {
          remainingTime = updatedBusArrival.buses.first.getRemainingMinutes();
          String currentStation = updatedBusArrival.buses.first.currentStation;

          // 콜백으로 남은 시간 업데이트
          onUpdateRemainingTime(remainingTime);

          String message =
              '🚌 버스 추적 알림 시작: $busNo, $stationName, 남은 시간: $remainingTime 분, 현재 위치: $currentStation';
          debugPrint(message);

          // TTS 메시지 (이어폰/블루투스 전용)
          String ttsMessage =
              '$busNo번 버스 $stationName 도착 $remainingTime분 전입니다.';
          await TTSHelper.speakEarphoneOnly(ttsMessage);

          // "곧 도착" 시 진동 및 TTS
          if (remainingTime <= 1) {
            await _triggerVibration();
            await TTSHelper.speakEarphoneOnly('곧 도착합니다.');
            timer.cancel();
            onTrackingStopped();
          }
        } else {
          debugPrint('🚌 버스 정보 없음, 추적 중단');
          timer.cancel();
          onTrackingStopped();
        }
      } catch (e) {
        debugPrint('🚌 실시간 추적 오류: $e');
        timer.cancel();
        onTrackingStopped();
      }
    });
  }

  /// 진동 트리거 함수
  Future<void> _triggerVibration() async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(pattern: [500, 1000, 500, 1000]); // 진동 패턴
      debugPrint('진동 알람 실행');
    }
  }

  /// 실시간 추적 중단
  Future<void> stopRealTimeTracking() async {
    _trackingTimer?.cancel();
    debugPrint('🚌 실시간 추적 중단');
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
      await initialize();

      debugPrint(
          '🔔 자동 알람 알림 표시: $busNo, $stationName, $remainingMinutes분 전, ID: $id');

      final bool result = await _channel.invokeMethod('showNotification', {
        'id': id,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': '자동 알람',
        'payload': routeId,
        'isAutoAlarm': true,
      });

      await showOngoingBusTracking(
        busNo: busNo,
        stationName: stationName,
        remainingMinutes: remainingMinutes,
        currentStation: '자동 알람 작동 중',
      );

      debugPrint('🔔 자동 알림 표시 완료: $id');
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
      await TTSHelper.speakEarphoneOnly('$busNo번 버스 $stationName 곧 도착합니다.');
      await _triggerVibration();
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
      await stopRealTimeTracking(); // 실시간 추적 중단
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
      await stopRealTimeTracking(); // 실시간 추적 중단
      debugPrint('🔔 모든 알림 취소');
      return result;
    } on PlatformException catch (e) {
      debugPrint('🔔 모든 알림 취소 오류: ${e.message}');
      return false;
    }
  }
}
