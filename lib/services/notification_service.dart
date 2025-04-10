import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:daegu_bus_app/utils/simple_tts_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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
          '🔔 자동 알람 알림 표시 시작: $busNo, $stationName, $remainingMinutes분 전, ID: $id, ${DateTime.now().toString()}');

      // 현재 시간과 알림 시간 비교
      final now = DateTime.now();

      // 알림 시간이 매개변수로 전달된 경우 (WorkManager에서 설정한 시간)
      int? notificationTimeMs;
      if (routeId != null && routeId.isNotEmpty) {
        try {
          final Map<String, dynamic> data =
              await _getStoredAlarmData(busNo, stationName, routeId);
          if (data.containsKey('notificationTime')) {
            notificationTimeMs = data['notificationTime'] as int?;
            if (notificationTimeMs != null) {
              final scheduledTime =
                  DateTime.fromMillisecondsSinceEpoch(notificationTimeMs);
              debugPrint('🔔 저장된 알림 예약 시간: ${scheduledTime.toString()}');

              // 현재 시간과 예약 시간의 차이가 5분 이상이면 알림 표시하지 않음
              final difference = now.difference(scheduledTime).inMinutes.abs();
              if (difference > 5) {
                debugPrint('⏭️ 알림 시간 불일치, 표시하지 않음. 차이: $difference분');
                return false;
              }
            }
          }
        } catch (e) {
          debugPrint('🔔 저장된 알림 시간 확인 실패: $e');
        }
      }

      final notificationTime = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
      );

      // 자동 알람의 경우 isOngoing을 true로 설정하여 지속적인 알림으로 표시
      final bool result = await _channel.invokeMethod('showNotification', {
        'id': id,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': '자동 알람', // 자동 알람임을 표시
        'payload': routeId, // 필요시 routeId를 페이로드로 전달
        'isAutoAlarm': true, // 자동 알람 식별자
        'isOngoing': true, // 지속적인 알림으로 설정
        'routeId': routeId, // routeId 추가
        'notificationTime': notificationTimeMs ??
            notificationTime.millisecondsSinceEpoch, // 알림 시간 추가
      });

      debugPrint('🔔 자동 알람 알림 표시 완료: $id');
      return result;
    } catch (e) {
      debugPrint('🔔 자동 알람 알림 표시 오류: ${e.toString()}');
      return false;
    }
  }

  // 저장된 알람 데이터 가져오기
  Future<Map<String, dynamic>> _getStoredAlarmData(
      String busNo, String stationName, String routeId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarms = prefs.getStringList('auto_alarms') ?? [];

      for (var json in alarms) {
        try {
          final data = jsonDecode(json);
          if (data['routeNo'] == busNo &&
              data['stationName'] == stationName &&
              data['routeId'] == routeId) {
            return data;
          }
        } catch (e) {
          debugPrint('🔔 알람 데이터 파싱 오류: $e');
        }
      }
      return {};
    } catch (e) {
      debugPrint('🔔 알람 데이터 조회 오류: $e');
      return {};
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
    String? routeId,
    bool isAutoAlarm = false, // 자동 알람 여부 추가
    int? notificationTime, // 알림 시간 추가
    String? allBusesSummary, // 모든 버스 정보 요약 (allBuses 모드에서만 사용)
  }) async {
    try {
      debugPrint(
          '🔔 알림 표시 시도: $busNo, $stationName, $remainingMinutes분, ID: $id, isOngoing: $isOngoing, routeId: $routeId, isAutoAlarm: $isAutoAlarm');

      final bool result = await _channel.invokeMethod('showNotification', {
        'id': id,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': currentStation,
        'payload': payload,
        'isOngoing': isOngoing,
        'routeId': routeId,
        'isAutoAlarm': isAutoAlarm,
        'notificationTime':
            notificationTime ?? DateTime.now().millisecondsSinceEpoch,
        'allBusesSummary': allBusesSummary, // 모든 버스 정보 요약 추가
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

      // TTS 알림
      await SimpleTTSHelper.speak(
          "$busNo번 버스가 $stationName 정류장에 곧 도착합니다. 탑승 준비하세요.");
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
