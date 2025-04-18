import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:daegu_bus_app/utils/simple_tts_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NotificationService: 네이티브 BusAlertService와 통신하는 Flutter 서비스
class NotificationService {
  static const MethodChannel _channel =
      MethodChannel('com.example.daegu_bus_app/notification');

  // 싱글톤 패턴 구현
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  // 알림 ID 생성 헬퍼 메소드
  int _generateNotificationId(String busNo, String stationName) {
    return ('${busNo}_$stationName').hashCode.abs();
  }

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
    bool isAutoAlarm = true, // 기본값은 true로 설정
    String? currentStation, // 버스 현재 위치 정보 추가
  }) async {
    try {
      debugPrint(
          '🔔 자동 알람 알림 표시 시도: $busNo, $stationName, $remainingMinutes분, ID: $id');

      // 알람 취소 상태 확인
      final prefs = await SharedPreferences.getInstance();
      final isAlarmCancelled = prefs.getBool('alarm_cancelled_$id') ?? false;

      if (isAlarmCancelled) {
        debugPrint('🔔 알람이 취소된 상태입니다. 알림을 표시하지 않습니다. ID: $id');
        return false;
      }

      final now = DateTime.now();
      int? notificationTimeMs;

      // 현재 시간 기준으로 알림 정보 생성
      final notificationTime = DateTime(
        now.year,
        now.month,
        now.day,
        now.hour,
        now.minute,
      );

      // 네이티브 코드에서 Integer 범위를 초과하는 ID를 처리하기 위한 로직
      final int safeNotificationId = id.abs() % 2147483647;

      // 1. 먼저 TTS로 알림 시도 (자동 알람 플래그 명시)
      try {
        await SimpleTTSHelper.initialize();

        // 시스템 볼륨 최대화 요청 (자동 알람이므로)
        await SimpleTTSHelper.setVolume(1.0);

        // 스피커 모드 강제 설정 (자동 알람이므로)
        await SimpleTTSHelper.setAudioOutputMode(1); // 스피커 모드(1)

        if (remainingMinutes <= 0) {
          await SimpleTTSHelper.speak("$busNo번 버스가 $stationName 정류장에 곧 도착합니다.");
        } else {
          await SimpleTTSHelper.speak(
              "$busNo번 버스가 $stationName 정류장에 약 $remainingMinutes분 후 도착 예정입니다.");
        }
      } catch (e) {
        debugPrint('🔊 자동 알람 TTS 실행 오류: $e');
      }

      // 2. 자동 알람용 알림 표시 (isAutoAlarm 파라미터로부터 값 사용)
      final Map<String, dynamic> params = {
        'id': safeNotificationId,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': currentStation ?? '자동 알람', // 버스 현재 위치 또는 '자동 알람' 표시
        'payload': routeId, // 필요시 routeId를 페이로드로 전달
        'isAutoAlarm': isAutoAlarm, // 파라미터에서 값 사용
        'isOngoing': true, // 지속적인 알림으로 설정
        'routeId': routeId, // routeId 추가
        'notificationTime': notificationTimeMs ??
            notificationTime.millisecondsSinceEpoch, // 알림 시간 추가
        'useTTS': true, // TTS 사용 플래그
        'actions': ['cancel_alarm'], // 알람 취소 액션 추가
      };

      debugPrint('자동 알람 파라미터: $params');

      // 네이티브 메서드 호출
      final bool result =
          await _channel.invokeMethod('showNotification', params);

      debugPrint('🔔 자동 알람 알림 표시 완료: $id (안전 ID: $safeNotificationId)');
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
    String? routeId,
    bool isAutoAlarm = false,
    int? notificationTime,
    String? allBusesSummary,
  }) async {
    try {
      debugPrint(
          '🔔 알림 표시 시도: $busNo, $stationName, $remainingMinutes분, ID: $id, isOngoing: $isOngoing');

      // 네이티브 코드에서 Integer 범위를 초과하는 ID를 처리하기 위한 로직
      final int safeNotificationId = id.abs() % 2147483647;

      // 알림 표시 시도
      final bool result = await _channel.invokeMethod('showNotification', {
        'id': safeNotificationId,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': currentStation,
        'payload': payload ?? routeId,
        'isOngoing': isOngoing,
        'routeId': routeId,
        'isAutoAlarm': isAutoAlarm,
        'notificationTime':
            notificationTime ?? DateTime.now().millisecondsSinceEpoch,
        'allBusesSummary': allBusesSummary,
      });

      if (result) {
        debugPrint('🔔 알림 표시 성공: $id (안전 ID: $safeNotificationId)');
      } else {
        debugPrint('🔔 알림 표시 실패: $id');
      }
      return result;
    } on PlatformException catch (e) {
      debugPrint('🔔 알림 표시 오류: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('🔔 알림 표시 중 예외 발생: $e');
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

  /// 이전 버전과의 호환성을 위한 메서드 별칭
  Future<bool> cancel(int id) => cancelNotification(id);

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

  /// 버스 도착 임박 알림 (중요도 높음) - TTS 발화와 함께 실행
  Future<bool> showOngoingBusTracking({
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String? currentStation,
    String? routeId,
    String? allBusesSummary,
  }) async {
    try {
      debugPrint(
          '🔔 지속적인 버스 추적 알림 표시 시도: $busNo, $stationName, $remainingMinutes분, routeId: $routeId');

      // 알림 ID 생성 (버스 번호와 정류장 이름으로)
      final int notificationId = _generateNotificationId(busNo, stationName);

      final bool result =
          await _channel.invokeMethod('showOngoingBusTracking', {
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': currentStation,
        'routeId': routeId,
        'allBusesSummary': allBusesSummary,
        'id': notificationId,
        'isUpdate': false,
      });

      if (result) {
        debugPrint(
            '🔔 지속적인 버스 추적 알림 표시 완료 (ID: $notificationId, routeId: $routeId)');
      } else {
        debugPrint('🔔 지속적인 버스 추적 알림 표시 실패');
      }
      return result;
    } on PlatformException catch (e) {
      debugPrint('🔔 지속적인 버스 추적 알림 표시 오류: ${e.message}');
      return false;
    }
  }
}
