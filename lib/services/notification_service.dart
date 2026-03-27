import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:daegu_bus_app/utils/simple_tts_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:daegu_bus_app/services/settings_service.dart';
import 'package:daegu_bus_app/main.dart' show logMessage, LogLevel;

/// NotificationService: 네이티브 BusAlertService와 통신하는 Flutter 서비스
class NotificationService extends ChangeNotifier {
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
    String? stationId,
  }) {
    stopAutoAlarmUpdates(); // 기존 타이머가 있다면 중지
    _currentAutoAlarmId = id;
    _currentBusNo = busNo;
    _currentStationName = stationName;
    _currentRouteId = routeId;
    _currentStationId = stationId;
    if (_currentStationId == null) {
      debugPrint('⚠️ 자동 알람 갱신 시작 실패: stationId가 없습니다');
      stopAutoAlarmUpdates();
      return;
    }
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
      MethodChannel('com.devground.daegubus/station_tracking');

  /// 실시간 버스 정보를 fetch하여 알림 갱신
  Future<void> _updateAutoAlarmNotification() async {
    if (_currentAutoAlarmId == null ||
        _currentBusNo == null ||
        _currentStationName == null ||
        _currentRouteId == null ||
        _currentStationId == null) {
      debugPrint('⚠️ 자동 알람 정보 부족으로 갱신 중단');
      stopAutoAlarmUpdates();
      return;
    }
    try {
      final result = await _stationTrackingChannel.invokeMethod('getBusInfo', {
        'routeId': _currentRouteId,
        'stationId': _currentStationId,
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

  static NotificationService? _instance;
  static NotificationService get instance =>
      _instance ??= NotificationService._internal();
  factory NotificationService() => instance;

  NotificationService._internal();

  static const MethodChannel _channel =
      MethodChannel('com.devground.daegubus/bus_api');
  final SettingsService _settingsService = SettingsService();

  /// 알림 서비스 초기화
  Future<void> initialize() async {
    try {
      // 네이티브 initialize 호출 제거 (구현되지 않음)
      // await _channel.invokeMethod('initialize');
      await SharedPreferences.getInstance();
      // setAlarmSound 네이티브 호출 제거 (구현되지 않음)
      // await setAlarmSound(soundFileName);
    } on PlatformException catch (e) {
      debugPrint('🔔 알림 서비스 초기화 오류:  [31m${e.message} [0m');
    }
  }

  Future<void> setAlarmSound(String? soundFileName) async {
    try {
      // 네이티브 setAlarmSound 호출 제거 (구현되지 않음)
      // await _channel.invokeMethod(
      //     'setAlarmSound', {'soundFileName': soundFileName ?? ''});
    } on PlatformException catch (e) {
      debugPrint('🔔 네이티브 알람음 설정 오류: ${e.message}');
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

      // 1. TTS 시도 (설정 확인)
      if (_settingsService.useTts) {
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
                "$busNo번 버스가 약 $remainingMinutes분 후 도착 예정입니다.");
          }
        } catch (e) {
          debugPrint('🔊 자동 알람 TTS 실행 오류: $e');
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

      // TTS 알림 - 설정 확인
      if (_settingsService.useTts) {
        try {
          await SimpleTTSHelper.speak(
              "$busNo번 버스가 $stationName 정류장에 곧 도착합니다. 탑승 준비하세요.");
          debugPrint('TTS 실행 요청: $busNo, $stationName');
        } catch (e) {
          debugPrint('🔊 자동 알람 TTS 실행 오류: $e');
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

  /// 지속적인 추적 알림 취소 - 완전히 개선된 버전
  Future<bool> cancelOngoingTracking() async {
    try {
      logMessage('🚌 [cancelOngoingTracking] 모든 추적 중지 시작',
          level: LogLevel.info);

      // 0. 실시간 버스 정보 업데이트 타이머 중지
      _stopRealTimeBusUpdates();
      logMessage('✅ 실시간 버스 업데이트 타이머 중지', level: LogLevel.debug);

      // 1. 자동 알람 업데이트 타이머도 중지
      stopAutoAlarmUpdates();
      logMessage('✅ 자동 알람 업데이트 타이머 중지', level: LogLevel.debug);

      // 2. 네이티브 서비스에 모든 추적 중지 요청 (가장 확실한 방법)
      //    이 메서드는 네이티브에서 포그라운드 서비스, 알림, TTS 등을 모두 중지해야 함
      try {
        await _channel.invokeMethod(
            'stopAllBusTracking'); // New or existing robust native method
        logMessage('✅ 네이티브 stopAllBusTracking 호출 완료', level: LogLevel.debug);
      } catch (e) {
        logMessage('⚠️ 네이티브 stopAllBusTracking 호출 실패 (무시): $e',
            level: LogLevel.warning);
      }

      // 3. 모든 알림 강제 취소 (혹시 모를 잔여 알림 제거)
      try {
        await _channel.invokeMethod('cancelAllNotifications');
        logMessage('✅ 모든 알림 강제 취소 완료', level: LogLevel.debug);
      } catch (e) {
        logMessage('⚠️ 모든 알림 강제 취소 오류 (무시): $e', level: LogLevel.warning);
      }

      logMessage('✅ 모든 지속적인 추적 알림 취소 완료', level: LogLevel.info);
      return true; // Assuming success if no exceptions
    } on PlatformException catch (e) {
      logMessage('❌ 지속적인 추적 알림 취소 오류: ${e.message}', level: LogLevel.error);
      return false;
    } catch (e) {
      logMessage('❌ 추적 알림 취소 중 예외 발생: ${e.toString()}', level: LogLevel.error);
      return false;
    }
  }

  /// 모든 알림 취소 메소드
  Future<bool> cancelAllNotifications() async {
    try {
      try {
        final bool result =
            await _channel.invokeMethod('cancelAllNotifications');
        debugPrint('🔔 모든 알림 취소');
        return result;
      } catch (e) {
        debugPrint('🔔 모든 알림 취소 오류 (무시): ${e.toString()}');
        return false;
      }
    } catch (e) {
      debugPrint('🔔 모든 알림 취소 중 예외 발생: ${e.toString()}');
      return false;
    }
  }

  /// 버스 도착 임박 알림 (중요도 높음) - TTS 발화와 함께 실행
  Future<bool> showOngoingBusTracking({
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    required String currentStation,
    required String routeId,
    required String stationId,
  }) async {
    logMessage(
        '🔔 [Flutter] showOngoingBusTracking 호출: $busNo, $stationName, $remainingMinutes, $currentStation, $routeId',
        level: LogLevel.info);
    try {
      // 통합 추적 알림용 고정 ID 사용 (ONGOING_NOTIFICATION_ID = 1)
      const int notificationId =
          1; // BusAlertService.ONGOING_NOTIFICATION_ID와 동일

      // 실시간 버스 정보 업데이트를 위한 타이머 시작 (더 짧은 간격으로 변경)
      _startRealTimeBusUpdates(
        busNo: busNo,
        stationName: stationName,
        routeId: routeId,
        stationId: stationId,
      );

      // 1. 메인 채널을 통해 Foreground 서비스 시작 - 통합 추적 알림으로 설정
      final bool result =
          await _channel.invokeMethod('showOngoingBusTracking', {
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': currentStation,
        'routeId': routeId,
        'stationId': stationId,
        'notificationId': notificationId, // 통합 알림 ID
        'isUpdate': false, // 새로운 추적 시작
        'isIndividualAlarm': false, // 개별 알람이 아님 (통합 추적 알림)
        'action': 'com.devground.daegubus.action.START_TRACKING_FOREGROUND',
      });

      // 2. 추가: bus_tracking 채널을 통해 직접 updateBusTrackingNotification 호출
      try {
        await const MethodChannel('com.devground.daegubus/bus_tracking')
            .invokeMethod(
          'updateBusTrackingNotification',
          {
            'busNo': busNo,
            'stationName': stationName,
            'remainingMinutes': remainingMinutes,
            'currentStation': currentStation,
            'routeId': routeId,
          },
        );
        logMessage('✅ bus_tracking 채널을 통한 알림 업데이트 성공', level: LogLevel.debug);
      } catch (e) {
        logMessage('⚠️ bus_tracking 채널 호출 오류: $e', level: LogLevel.error);
      }

      // 3. 즉시 실시간 업데이트 시작 (지연 없이)
      _updateBusInfo();

      return result;
    } catch (e) {
      logMessage('❌ 지속적인 버스 추적 알림 표시 오류: $e', level: LogLevel.error);
      return false;
    }
  }

// 실시간 버스 정보 업데이트 타이머 시작 (내부 메서드) - 주기 단축
  void _startRealTimeBusUpdates({
    required String busNo,
    required String stationName,
    String? routeId,
    required String stationId,
  }) {
    // 기존 타이머 중지
    _stopRealTimeBusUpdates();

    // 정보 저장
    _currentBusNo = busNo;
    _currentStationName = stationName;
    _currentRouteId = routeId;
    _currentStationId = stationId;

    // 즉시 한 번 업데이트하고, 이후에는 남은 시간에 따라 적응형 주기로 스케줄링
    _updateBusInfo();
    // 최초 스케줄 (초기값 30초)
    _scheduleNextBusUpdate(remainingMinutes: null);

    logMessage('🚌 실시간 버스 정보 업데이트 타이머 시작: $busNo, $stationName',
        level: LogLevel.info);
  }

// 실시간 버스 정보 업데이트 - 강화된 업데이트 메커니즘 (적응형 주기)
  Future<void> _updateBusInfo() async {
    if (_currentBusNo == null ||
        _currentStationName == null ||
        _currentRouteId == null ||
        _currentStationId == null) {
      logMessage('⚠️ 버스 정보 업데이트 실패: 필요한 정보가 없습니다', level: LogLevel.warning);
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
      String currentStation = info['currentStation'] ?? '위치 정보 없음';

      logMessage('[DEBUG] _updateBusInfo: $remainingMinutes분, $currentStation',
          level: LogLevel.debug);

      // 주요 업데이트 방법만 사용 (중복 제거)
      List<Future> updateMethods = [];

      // 1. bus_tracking 채널을 통한 알림 업데이트 (가장 직접적인 방법)
      updateMethods.add(
          const MethodChannel('com.devground.daegubus/bus_tracking')
              .invokeMethod(
        'updateBusTrackingNotification',
        {
          'busNo': _currentBusNo!,
          'stationName': _currentStationName!,
          'remainingMinutes': remainingMinutes,
          'currentStation': currentStation,
          'routeId': _currentRouteId!,
        },
      ).then((_) {
        logMessage('✅ bus_tracking 채널로 알림 업데이트 요청 완료', level: LogLevel.debug);
      }).catchError((e) {
        logMessage('⚠️ bus_tracking 채널 호출 오류: $e', level: LogLevel.error);
      }));

      // 모든 방법 병렬 실행
      await Future.wait(updateMethods);

      logMessage(
          '✅ 실시간 버스 추적 알림 업데이트 완료: $_currentBusNo, $remainingMinutes분, 현재 위치: $currentStation',
          level: LogLevel.info);
      // 다음 업데이트 스케줄링 (남은 시간 기반)
      _scheduleNextBusUpdate(remainingMinutes: remainingMinutes);
    } catch (e) {
      logMessage('❌ 버스 정보 업데이트 오류: $e', level: LogLevel.error);
      // 오류 발생 시 보수적으로 주기를 늘려 재시도
      _scheduleNextBusUpdate(remainingMinutes: null);
    }
  }

  /// 실시간 버스 정보 업데이트 타이머 시작 (외부에서 호출 가능한 공개 메서드)
  void startRealTimeBusUpdates({
    required String busNo,
    required String stationName,
    String? routeId,
    required String stationId,
  }) {
    _startRealTimeBusUpdates(
      busNo: busNo,
      stationName: stationName,
      routeId: routeId,
      stationId: stationId,
    );
  }

  // 실시간 버스 정보 업데이트 타이머 중지 (public으로 변경)
  void stopRealTimeBusUpdates() {
    _busUpdateTimer?.cancel();
    _busUpdateTimer = null;
    _currentBusNo = null;
    _currentStationName = null;
    _currentRouteId = null;
    _currentStationId = null;
    debugPrint('🚌 실시간 버스 정보 업데이트 타이머 중지');
  }

  // 내부용 별칭 (기존 코드 호환성 유지)
  void _stopRealTimeBusUpdates() {
    stopRealTimeBusUpdates();
  }

  /// 실시간 버스 추적 알림을 즉시 갱신 (패널 등에서 호출)
  Future<void> updateBusTrackingNotification({
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    required String currentStation,
    required String routeId,
    required String stationId,
  }) async {
    try {
      logMessage(
          '🚌 버스 추적 알림 업데이트 요청: $busNo, $remainingMinutes분, 현재 위치: $currentStation',
          level: LogLevel.debug);

      // 주요 업데이트 방법만 사용 (중복 제거)
      List<Future> updateMethods = [];

      // 1. bus_tracking 채널을 통한 알림 업데이트 (가장 직접적인 방법)
      updateMethods.add(
          const MethodChannel('com.devground.daegubus/bus_tracking')
              .invokeMethod(
        'updateBusTrackingNotification',
        {
          'busNo': busNo,
          'stationName': stationName,
          'remainingMinutes': remainingMinutes,
          'currentStation': currentStation,
          'routeId': routeId,
        },
      ).then((_) {
        logMessage('✅ bus_tracking 채널로 알림 업데이트 요청 완료', level: LogLevel.debug);
      }).catchError((e) {
        logMessage('⚠️ bus_tracking 채널 호출 오류: $e', level: LogLevel.error);
      }));

      // showOngoingBusTracking 및 updateNotification 호출 제거 - 중복 알림 방지

      // 모든 방법 병렬 실행
      await Future.wait(updateMethods);

      // 현재 정보 저장 (다음 업데이트를 위해)
      _currentBusNo = busNo;
      _currentStationName = stationName;
      _currentRouteId = routeId;
      _currentStationId = stationId;
      // 지연 백업 업데이트 제거 (중복 호출 방지)

      logMessage(
          '✅ 실시간 버스 추적 알림 업데이트 완료: $busNo, $remainingMinutes분, 현재 위치: $currentStation',
          level: LogLevel.info);
    } catch (e) {
      logMessage('❌ updateBusTrackingNotification 오류: $e',
          level: LogLevel.error);
    }
  }

  // 남은 시간에 따라 다음 업데이트를 적응형으로 스케줄링
  void _scheduleNextBusUpdate({int? remainingMinutes}) {
    // 기존 타이머 취소
    _busUpdateTimer?.cancel();

    // 기본 주기 (오류/정보없음 시): 60초
    Duration nextInterval = const Duration(seconds: 60);

    if (remainingMinutes != null) {
      if (remainingMinutes <= 3 && remainingMinutes >= 0) {
        nextInterval = const Duration(seconds: 10);
      } else if (remainingMinutes <= 10 && remainingMinutes > 3) {
        nextInterval = const Duration(seconds: 20);
      } else if (remainingMinutes > 10) {
        nextInterval = const Duration(seconds: 60);
      }
    }

    _busUpdateTimer = Timer(nextInterval, () {
      _updateBusInfo();
    });
    logMessage('⏱️ 다음 실시간 업데이트 예약: ${nextInterval.inSeconds}s 후',
        level: LogLevel.debug);
  }
} // <-- Add this closing brace to end the class

// 버스 도착 메시지 포맷터 (앱 전체에서 통일 사용)
String getBusArrivalMessage(String busNo, int remainingMinutes) {
  if (remainingMinutes <= 0) return '$busNo번 버스가 곧 도착합니다.';
  if (remainingMinutes == 1) return '$busNo번 버스가 약 1분 후 도착 예정입니다.';
  return '$busNo번 버스가 약 $remainingMinutes분 후 도착 예정입니다.';
}

// 버스 도착(정류장 기준) 안내 메시지
String getBusArrivedMessage(String busNo, String stationName) {
  return '$busNo번 버스가 $stationName 정류장에 곧 도착합니다. 탑승 준비하세요.';
}

// 버스 운행종료 메시지
String getBusOutOfServiceMessage(String busNo) {
  return '$busNo번 버스는 운행이 종료되었습니다.';
}

// 버스 TTS 안내 메시지 (도착/곧 도착/운행종료 등 상황별)
String getBusTtsMessage(String busNo, String stationName, int remainingMinutes,
    {bool outOfService = false}) {
  if (outOfService) return getBusOutOfServiceMessage(busNo);
  if (remainingMinutes <= 0) return '$busNo번 버스가 $stationName 정류장에 곧 도착합니다.';
  if (remainingMinutes == 1) {
    return '$busNo번 버스가 $stationName 정류장에 약 1분 후 도착 예정입니다.';
  }
  return '$busNo번 버스가 $stationName 정류장에 약 $remainingMinutes분 후 도착 예정입니다.';
}
