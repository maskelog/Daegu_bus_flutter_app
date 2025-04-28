import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:daegu_bus_app/utils/simple_tts_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daegu_bus_app/services/settings_service.dart';
import 'package:daegu_bus_app/utils/tts_switcher.dart' show TtsSwitcher;

/// NotificationService: 네이티브 BusAlertService와 통신하는 Flutter 서비스
class NotificationService {
  // ===== [실시간 자동 알람 갱신용 상태 및 Timer 추가] =====
  Timer? _autoAlarmTimer;
  int? _currentAutoAlarmId;

  // 실시간 버스 정보 업데이트를 위한 타이머
  Timer? _busUpdateTimer;
  String? _currentBusNo;
  String? _currentStationName;
  String? _currentRouteId;
  String? _currentStationId;

  /// 1분마다 실시간 버스 정보를 가져와 알림을 갱신하는 주기적 타이머 시작
  void startAutoAlarmUpdates({
    required int id,
    required String busNo,
    required String stationName,
    required String routeId,
  }) {
    stopAutoAlarmUpdates(); // 기존 타이머가 있다면 중지
    _currentAutoAlarmId = id;
    _currentBusNo = busNo;
    _currentStationName = stationName;
    _currentRouteId = routeId;
    // 즉시 1회 실행 후 1분마다 반복
    _updateAutoAlarmNotification();
    _autoAlarmTimer = Timer.periodic(const Duration(minutes: 1), (_) async {
      await _updateAutoAlarmNotification();
    });
    debugPrint('🔄 실시간 자동 알람 갱신 타이머 시작: $busNo ($stationName)');
  }

  /// 실시간 자동 알람 갱신 타이머 중지
  void stopAutoAlarmUpdates() {
    _autoAlarmTimer?.cancel();
    _autoAlarmTimer = null;
    _currentAutoAlarmId = null;
    _currentBusNo = null;
    _currentStationName = null;
    _currentRouteId = null;
    debugPrint('⏹️ 실시간 자동 알람 갱신 타이머 중지');
  }

  static const MethodChannel _stationTrackingChannel =
      MethodChannel('com.example.daegu_bus_app/station_tracking');

  /// 실시간 버스 정보를 fetch하여 알림 갱신
  Future<void> _updateAutoAlarmNotification() async {
    if (_currentAutoAlarmId == null ||
        _currentBusNo == null ||
        _currentStationName == null ||
        _currentRouteId == null) {
      debugPrint('⚠️ 자동 알람 정보 부족으로 갱신 중단');
      stopAutoAlarmUpdates();
      return;
    }
    try {
      final result = await _stationTrackingChannel.invokeMethod('getBusInfo', {
        'routeId': _currentRouteId,
        'stationName': _currentStationName,
      });
      Map<String, dynamic> info;
      if (result is String) {
        info = Map<String, dynamic>.from(jsonDecode(result));
      } else {
        info = Map<String, dynamic>.from(result);
      }
      int updatedRemainingMinutes = info['remainingMinutes'] ?? 0;
      String? updatedCurrentStation = info['currentStation'];

      await showAutoAlarmNotification(
        id: _currentAutoAlarmId!,
        busNo: _currentBusNo!,
        stationName: _currentStationName!,
        remainingMinutes: updatedRemainingMinutes,
        routeId: _currentRouteId,
        isAutoAlarm: true,
        currentStation: updatedCurrentStation,
      );
      debugPrint('🔄 실시간 자동 알람 노티 갱신 완료');
    } catch (e) {
      debugPrint('❌ 실시간 자동 알람 갱신 오류: $e');
    }
  }
  // ===== [END: 실시간 자동 알람 갱신용 추가] =====

  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static const MethodChannel _channel =
      MethodChannel('com.example.daegu_bus_app/notification');
  final SettingsService _settingsService = SettingsService();

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
    // 알림이 취소되었으면 실시간 갱신도 중단
    final prefs = await SharedPreferences.getInstance();
    final isAlarmCancelled = prefs.getBool('alarm_cancelled_$id') ?? false;
    if (isAlarmCancelled) {
      stopAutoAlarmUpdates();
    }

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

      // 1. TTS 시도 (설정 및 이어폰 연결 여부 확인)
      if (_settingsService.useTts) {
        final ttsSwitcher = TtsSwitcher();
        await ttsSwitcher.initialize();
        final headphoneConnected = await ttsSwitcher.isHeadphoneConnected();
        if (headphoneConnected) {
          try {
            await SimpleTTSHelper.initialize();
            // 시스템 볼륨 최대화 요청
            await SimpleTTSHelper.setVolume(1.0);
            // 스피커 모드 강제 설정
            await SimpleTTSHelper.setAudioOutputMode(1);
            if (remainingMinutes <= 0) {
              await SimpleTTSHelper.speak(
                  "$busNo번 버스가 $stationName 정류장에 곧 도착합니다.");
            } else {
              await SimpleTTSHelper.speak(
                  "$busNo번 버스가 $stationName 정류장에 약 $remainingMinutes분 후 도착 예정입니다.");
            }
          } catch (e) {
            debugPrint('🔊 자동 알람 TTS 실행 오류: $e');
          }
        } else {
          debugPrint('🎧 이어폰 미연결 - 자동 알람 TTS 건너뜀');
        }
      } else {
        debugPrint('🔇 자동 알람 TTS 비활성화 - 음성 알림 건너뜀');
      }

      // 2. 자동 알람용 알림 표시 (isAutoAlarm 파라미터로부터 값 사용)
      final Map<String, dynamic> params = {
        'id': id,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': currentStation ?? '자동 알람', // 버스 현재 위치 또는 '자동 알람' 표시
        'payload': routeId, // 필요시 routeId를 페이로드로 전달
        'isAutoAlarm': isAutoAlarm, // 파라미터에서 값 사용
        'isOngoing': true, // 지속적인 알림으로 설정
        'routeId': routeId, // routeId 추가
        'notificationTime': DateTime.now().millisecondsSinceEpoch, // 알림 시간 추가
        'useTTS': true, // TTS 사용 플래그
        'actions': ['cancel_alarm'], // 알람 취소 액션 추가
      };

      debugPrint('자동 알람 파라미터: $params');

      // 네이티브 메서드 호출
      final bool result =
          await _channel.invokeMethod('showNotification', params);

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

      // TTS 알림 - 설정 및 이어폰 연결 여부 확인
      if (_settingsService.useTts) {
        final ttsSwitcher = TtsSwitcher();
        await ttsSwitcher.initialize();
        final shouldUse = await ttsSwitcher.shouldUseNativeTts();
        if (shouldUse) {
          await SimpleTTSHelper.speak(
              "$busNo번 버스가 $stationName 정류장에 곧 도착합니다. 탑승 준비하세요.");
          debugPrint('TTS 실행 요청: $busNo, $stationName');
        } else {
          debugPrint('🔇 이어폰 미연결 또는 TTS 모드 비허용 - TTS 건너뜀');
        }
      } else {
        debugPrint('🔇 TTS 비활성화 상태: 음성 알림 건너뜀');
      }

      return result;
    } on PlatformException catch (e) {
      debugPrint('🚨 버스 도착 임박 알림 표시 오류: ${e.message}');
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
      // 0. 실시간 버스 정보 업데이트 타이머 중지
      _stopRealTimeBusUpdates();

      // 1. 기존 방식: 'cancelOngoingTracking' 메서드 호출
      final bool result = await _channel.invokeMethod('cancelOngoingTracking');

      // 2. 추가: 'stopStationTracking' 메서드 호출하여 정류장 추적 서비스도 확실하게 중지
      try {
        await const MethodChannel('com.example.daegu_bus_app/station_tracking')
            .invokeMethod('stopStationTracking');
        debugPrint('🚌 정류장 추적 서비스도 중지 요청 완료');
      } catch (e) {
        debugPrint('🚌 정류장 추적 서비스 중지 요청 중 오류: ${e.toString()}');
      }

      // 3. 추가: 'stopBusTracking' 메서드 호출하여 버스 추적 서비스 중지
      try {
        await const MethodChannel('com.example.daegu_bus_app/bus_tracking')
            .invokeMethod('stopBusTracking', {});
        debugPrint('🚌 버스 추적 서비스 중지 요청 완료');
      } catch (e) {
        debugPrint('🚌 버스 추적 서비스 중지 요청 중 오류: ${e.toString()}');
      }

      // 4. 자동 알람 업데이트 타이머도 중지
      stopAutoAlarmUpdates();

      debugPrint('🚌 모든 지속적인 추적 알림 취소 시도 완료');
      return result;
    } on PlatformException catch (e) {
      debugPrint('🚌 지속적인 추적 알림 취소 오류: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('🚌 추적 알림 취소 중 예외 발생: ${e.toString()}');
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
          '🔔 지속적인 버스 추적 알림 표시 시도: $busNo, $stationName, $remainingMinutes분, routeId: $routeId, 현재 위치: $currentStation');

      // 알림 ID 생성 (버스 번호와 정류장 이름으로)
      final int notificationId = _generateNotificationId(busNo, stationName);

      // 실시간 버스 정보 업데이트를 위한 타이머 시작
      _startRealTimeBusUpdates(
        busNo: busNo,
        stationName: stationName,
        routeId: routeId,
        stationId: routeId?.split('_').lastOrNull,
      );

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
        'action':
            'com.example.daegu_bus_app.action.START_TRACKING_FOREGROUND', // Foreground 서비스 시작을 위한 액션
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

  // 실시간 버스 정보 업데이트 관련 변수는 클래스 상단에 이미 선언되어 있음

  // 실시간 버스 정보 업데이트 타이머 시작
  void _startRealTimeBusUpdates({
    required String busNo,
    required String stationName,
    String? routeId,
    String? stationId,
  }) {
    // 기존 타이머 중지
    _stopRealTimeBusUpdates();

    // 정보 저장
    _currentBusNo = busNo;
    _currentStationName = stationName;
    _currentRouteId = routeId;
    _currentStationId = stationId;

    // 타이머 시작 (1분마다 업데이트)
    _busUpdateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _updateBusInfo();
    });

    // 즉시 한 번 업데이트
    _updateBusInfo();

    debugPrint('🚌 실시간 버스 정보 업데이트 타이머 시작: $busNo, $stationName');
  }

  // 실시간 버스 정보 업데이트 타이머 중지
  void _stopRealTimeBusUpdates() {
    _busUpdateTimer?.cancel();
    _busUpdateTimer = null;
    _currentBusNo = null;
    _currentStationName = null;
    _currentRouteId = null;
    _currentStationId = null;
    debugPrint('🚌 실시간 버스 정보 업데이트 타이머 중지');
  }

  // 실시간 버스 정보 업데이트
  Future<void> _updateBusInfo() async {
    if (_currentBusNo == null ||
        _currentStationName == null ||
        _currentRouteId == null ||
        _currentStationId == null) {
      debugPrint('⚠️ 버스 정보 업데이트 실패: 필요한 정보가 없습니다');
      return;
    }

    try {
      // 버스 정보 조회
      final result = await _stationTrackingChannel.invokeMethod('getBusInfo', {
        'routeId': _currentRouteId,
        'stationId': _currentStationId,
      });

      // 결과 파싱
      Map<String, dynamic> info;
      if (result is String) {
        info = Map<String, dynamic>.from(jsonDecode(result));
      } else {
        info = Map<String, dynamic>.from(result);
      }

      // 정보 추출
      int remainingMinutes = info['remainingMinutes'] ?? 0;
      String? currentStation = info['currentStation'];

      // 알림 업데이트
      await _channel.invokeMethod('showOngoingBusTracking', {
        'busNo': _currentBusNo,
        'stationName': _currentStationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': currentStation,
        'routeId': _currentRouteId,
        'isUpdate': true,
        'action': 'com.example.daegu_bus_app.action.UPDATE_TRACKING',
      });

      debugPrint(
          '🚌 버스 정보 업데이트 완료: $_currentBusNo, $remainingMinutes분, 현재 위치: $currentStation');
    } catch (e) {
      debugPrint('❌ 버스 정보 업데이트 오류: $e');
    }
  }
}
