import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/auto_alarm.dart';
import '../models/alarm_data.dart' as alarm_model;
import 'alarm/alarm_keys.dart';
import '../utils/simple_tts_helper.dart';
import 'notification_service.dart';
import 'settings_service.dart';
import '../main.dart' show logMessage, LogLevel;
import '../utils/database_helper.dart';
import 'alarm/alarm_event_handler.dart';
import 'alarm/alarm_facade.dart';
import 'alarm/alarm_repository.dart';
import 'alarm/auto_alarm_arrival_parser.dart';
import 'alarm/auto_alarm_validator.dart';
import 'alarm/cached_bus_info.dart';
import 'alarm/station_id_resolver.dart';

class AlarmService extends ChangeNotifier {
  final NotificationService _notificationService;
  final SettingsService _settingsService;
  final AlarmRepository _repository = AlarmRepository();
  late final AlarmFacade _alarmFacade;
  late final AlarmEventHandler _eventHandler;

  bool get _useTTS => _settingsService.useTts;
  Timer? _alarmCheckTimer;
  bool _initialized = false;
  MethodChannel? _methodChannel;
  DateTime _lastRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);
  final Set<String> _pendingAutoAlarmDeactivations = <String>{};
  static const Duration _alarmRefreshInterval = Duration(minutes: 2);
  static const int _restartPreventionDuration = 3000; // 3초간 재시작 방지
  @visibleForTesting
  int get restartPreventionDurationMs => _restartPreventionDuration;

  List<alarm_model.AlarmData> get activeAlarms {
    final allAlarms = <alarm_model.AlarmData>{};
    allAlarms.addAll(
      _alarmFacade.activeAlarms.where((alarm) => !alarm.isAutoAlarm),
    ); // 일반 알람만 추가
    allAlarms.addAll(
      _alarmFacade.autoAlarms.where((alarm) => alarm.isAutoAlarm),
    ); // 활성화된 자동 알람만 추가
    return allAlarms.toList();
  }

  List<alarm_model.AlarmData> get autoAlarms => _alarmFacade.autoAlarms;
  bool get isInTrackingMode => _alarmFacade.isInTrackingMode;

  AlarmService({
    required NotificationService notificationService,
    required SettingsService settingsService,
  })  : _notificationService = notificationService,
        _settingsService = settingsService {
    _alarmFacade = AlarmFacade(
      validateRequiredFields: validateAutoAlarmFields,
      resolveStationId: resolveStationIdFromName,
    );
    _setupMethodChannel();
  }

  void _setupMethodChannel() {
    _methodChannel = const MethodChannel('com.devground.daegubus/bus_api');
    _eventHandler = AlarmEventHandler(
      facade: _alarmFacade,
      saveAlarms: _saveAlarms,
      notifyListeners: notifyListeners,
      deactivateAutoAlarm: deactivateAutoAlarm,
      isAutoAlarmDeactivationPending: _pendingAutoAlarmDeactivations.contains,
      stopRealTimeBusUpdates: _notificationService.stopRealTimeBusUpdates,
    );
    _methodChannel?.setMethodCallHandler(_eventHandler.handleMethodCall);
    _alarmFacade.setMethodChannel(_methodChannel);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true; // 초기화 시작을 먼저 표시

    try {
      await _notificationService.initialize();

      // 데이터 로딩을 비동기적으로 처리하여 앱 시작을 막지 않음
      _loadDataInBackground();

      _alarmCheckTimer?.cancel();
      // 5초 → 15초로 완화하여 불필요한 빈번한 작업 감소
      _alarmCheckTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
        final now = DateTime.now();
        if (now.difference(_lastRefreshAt) >= _alarmRefreshInterval) {
          _lastRefreshAt = now;
          refreshAlarms();
        }
      });

      logMessage('✅ AlarmService 초기화 시작 (데이터는 백그라운드 로딩)');
    } catch (e) {
      logMessage('❌ AlarmService 초기화 오류: $e', level: LogLevel.error);
    }
  }

  Future<void> _loadDataInBackground() async {
    await loadAlarms();
    await loadAutoAlarms();
  }

  @override
  void dispose() {
    _initialized = false;
    _alarmCheckTimer?.cancel();
    super.dispose();
  }

  // 자동 알람 일시 정지/재개 메서드
  void pauseAutoAlarms() {
    _alarmFacade.state.autoAlarmEnabled = false;
    logMessage('⏸️ 자동 알람 일시 정지', level: LogLevel.info);
  }

  void resumeAutoAlarms() {
    _alarmFacade.state.autoAlarmEnabled = true;
    logMessage('▶️ 자동 알람 재개', level: LogLevel.info);
  }




  Future<void> loadAlarms() async {
    try {
      final loaded = await _repository.loadActiveAlarms();
      _alarmFacade.activeAlarmsMap
        ..clear()
        ..addAll(loaded);

      logMessage('✅ 알람 로드 완료: ${_alarmFacade.activeAlarmsMap.length}개');
      notifyListeners();
    } catch (e) {
      logMessage('알람 로드 중 오류 발생: $e', level: LogLevel.error);
    }
  }

  Future<void> loadAutoAlarms() async {
    try {
      final autoAlarms = await _repository.loadAutoAlarms();
      _alarmFacade.autoAlarmsList.clear();

      // 구버전 alarmId로 등록된 잔여 네이티브 알람 정리 (앱 업데이트 후 1회)
      if (await _repository.shouldCleanLegacyAlarmIds()) {
        for (final autoAlarm in autoAlarms) {
          await cancelScheduledAutoAlarm(autoAlarm.id);
        }
        logMessage('✅ 구버전 alarmId 잔여 알람 정리 완료 (${autoAlarms.length}건)');
      }

      // 다음 알람 시간 계산에 쓸 공휴일·예외 날짜 (HolidayService가 캐싱)
      final allHolidays = await _getUpcomingExclusionDates();

      for (var autoAlarm in autoAlarms) {
        try {
          if (!autoAlarm.isActive) {
            await cancelScheduledAutoAlarm(autoAlarm.id);
            logMessage(
              '⏸️ 비활성화된 자동 알람 예약 정리: ${autoAlarm.routeNo}',
              level: LogLevel.info,
            );
            continue;
          }

          final nextAlarmTime =
              autoAlarm.getNextAlarmTime(holidays: allHolidays);
          if (nextAlarmTime == null) {
            logMessage(
              '⚠️ 자동 알람 다음 시간 계산 실패: ${autoAlarm.routeNo}',
              level: LogLevel.warning,
            );
            continue;
          }

          final alarm = alarm_model.AlarmData(
            id: autoAlarm.id,
            busNo: autoAlarm.routeNo,
            stationName: autoAlarm.stationName,
            remainingMinutes: 0,
            routeId: autoAlarm.routeId,
            scheduledTime: nextAlarmTime, // 올바른 다음 알람 시간 사용
            useTTS: autoAlarm.useTTS,
            isAutoAlarm: true,
            isCommuteAlarm: autoAlarm.isCommuteAlarm,
            repeatDays: autoAlarm.repeatDays,
          );

          _alarmFacade.autoAlarmsList.add(alarm);
          await _alarmFacade.scheduleAutoAlarm(autoAlarm, nextAlarmTime);
          logMessage(
            '✅ 자동 알람 로드: ${alarm.busNo}, ${alarm.stationName}, 다음 시간: ${nextAlarmTime.toString()}',
          );
        } catch (e) {
          logMessage('❌ 자동 알람 파싱 오류: $e', level: LogLevel.error);
          continue;
        }
      }

      logMessage('✅ 자동 알람 로드 완료: ${_alarmFacade.autoAlarmsList.length}개');
      notifyListeners();
    } catch (e) {
      logMessage('❌ 자동 알람 로드 실패: $e', level: LogLevel.error);
    }
  }

  /// 이번 달·다음 달 공휴일 + 사용자 지정 예외 날짜.
  /// 네이티브 재스케줄 경로(AlarmReceiver/BootReceiver)에서도 같은 판단을
  /// 할 수 있도록 결과를 prefs(excluded_dates)로 내려둔다.
  Future<List<DateTime>> _getUpcomingExclusionDates() async {
    final now = DateTime.now();
    final currentMonthHolidays = await getHolidays(now.year, now.month);
    final nextTargetMonth = now.month == 12 ? 1 : now.month + 1;
    final nextTargetYear = now.month == 12 ? now.year + 1 : now.year;
    final nextMonthHolidays =
        await getHolidays(nextTargetYear, nextTargetMonth);
    final dates = [
      ...currentMonthHolidays,
      ...nextMonthHolidays,
      ...SettingsService().customExcludeDates,
    ];
    await _repository.saveExcludedDates(dates);
    return dates;
  }

  Future<bool> startBusMonitoringService({
    required String stationId,
    required String stationName,
    required String routeId,
    required String busNo,
  }) async {
    try {
      // routeId가 비어있으면 기본값 설정
      final String effectiveRouteId =
          routeId.isEmpty ? '${busNo}_$stationName' : routeId;

      await _alarmFacade.nativeBridge.startBusMonitoringService(
        stationId: stationId,
        stationName: stationName,
        routeId: effectiveRouteId,
        busNo: busNo,
      );
      _alarmFacade.isTrackingMode = true;
      _alarmFacade.trackedRouteId = effectiveRouteId;
      logMessage(
        '\ud83d\ude8c \ubc84\uc2a4 \ucd94\uc801 \uc2dc\uc791: $_alarmFacade.trackedRouteId',
      );
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('🚌 버스 모니터링 서비스 시작 오류: $e');
      rethrow;
    }
  }

  Future<bool> stopBusMonitoringService() async {
    try {
      debugPrint('🚌 버스 모니터링 서비스 중지 시작');

      bool stopSuccess = false;

      // 1. 메서드 채널을 통한 중지 시도
      try {
        final result = await _alarmFacade.nativeBridge.stopBusMonitoringService();
        if (result == true) {
          stopSuccess = true;
          debugPrint('🚌 버스 모니터링 서비스 중지 성공 (result: $result)');
        } else {
          debugPrint('🚌 버스 모니터링 서비스 중지 실패 (result: $result)');
        }
      } catch (e) {
        debugPrint('🚌 버스 모니터링 서비스 중지 메서드 호출 오류: $e');
      }

      // 2. TTS 추적 중지 시도
      try {
        await _alarmFacade.nativeBridge.stopTtsTracking();
        debugPrint('🚌 TTS 추적 중지 성공');
      } catch (e) {
        debugPrint('🚌 TTS 추적 중지 오류: $e');
      }

      // 3. 알림 취소 시도
      try {
        await NotificationService().cancelOngoingTracking();
        debugPrint('🚌 진행 중인 추적 알림 취소 성공');

        // 모든 알림도 추가로 취소 시도
        await NotificationService().cancelAllNotifications();
        debugPrint('🚌 모든 알림 취소 성공');
      } catch (e) {
        debugPrint('🚌 알림 취소 시도 오류: $e');
      }

      // 4. 캐시 데이터 정리
      try {
        _alarmFacade.state.processedNotifications.clear();
        debugPrint('🚌 처리된 알림 캐시 정리 완료');
      } catch (e) {
        debugPrint('🚌 캐시 정리 오류: $e');
      }

      // 5. 마지막으로 상태 변경
      _alarmFacade.isTrackingMode = false;
      _alarmFacade.trackedRouteId = null;
      logMessage(
        '\ud83d\ude8c \ubc84\uc2a4 \ucd94\uc801 \uc911\uc9c0: \ucd94\uc801 \uc544\uc774\ub514 \ucd08\uae30\ud654',
      );
      notifyListeners();

      // 6. TTS로 알림 중지 알림
      try {
        // 이어폰 연결 시에만 TTS 발화
        await SimpleTTSHelper.speak("버스 추적이 중지되었습니다.", earphoneOnly: true);
      } catch (e) {
        debugPrint('🚌 TTS 알림 오류: $e');
      }

      debugPrint('🚌 모니터링 서비스 중지 완료, 추적 모드: $_alarmFacade.isTrackingMode');
      return stopSuccess || !_alarmFacade.isTrackingMode;
    } catch (e) {
      debugPrint('🚌 버스 모니터링 서비스 중지 오류: $e');

      // 오류 발생해도 강제로 상태 변경
      _alarmFacade.isTrackingMode = false;
      _alarmFacade.state.processedNotifications.clear();
      notifyListeners();

      return false;
    }
  }

  CachedBusInfo? getCachedBusInfo(String busNo, String routeId) {
    return _alarmFacade.getCachedBusInfo(busNo, routeId);
  }

  Map<String, dynamic>? getTrackingBusInfo() {
    return _alarmFacade.getTrackingBusInfo();
  }

  void updateBusInfoCache(
    String busNo,
    String routeId,
    dynamic busInfo,
    int remainingMinutes,
  ) {
    _alarmFacade.updateBusInfoCache(busNo, routeId, busInfo, remainingMinutes);
  }

  Future<void> refreshAlarms() async {
    await loadAlarms();
    await loadAutoAlarms();
    notifyListeners();
  }

  void removeFromCacheBeforeCancel(
    String busNo,
    String stationName,
    String routeId,
  ) {
    _alarmFacade.removeFromCacheBeforeCancel(busNo, stationName, routeId);
    notifyListeners();
  }


  Future<List<DateTime>> getHolidays(int year, int month) async {
    return _alarmFacade.getHolidays(year, month);
  }

  /// 알람 시작
  Future<void> startAlarm(
    String busNo,
    String stationName,
    int remainingMinutes, {
    bool isAutoAlarm = false,
    bool isCommuteAlarm = false,
  }) async {
    try {
      // TTS 발화
      if (_useTTS) {
        await SimpleTTSHelper.speakBusAlert(
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          earphoneOnly: !isCommuteAlarm,
          isAutoAlarm: isAutoAlarm, // 🔊 자동 알람 플래그 전달
          forceSpeaker: isCommuteAlarm,
        );
      }

      // 알람 해제 시에도 설정된 모드 유지
      await _notificationService.showBusArrivingSoon(
        busNo: busNo,
        stationName: stationName,
      );
    } catch (e) {
      logMessage('❌ 알람 시작 오류: $e', level: LogLevel.error);
    }
  }

  /// 자동 알람 중지 메서드 추가
  Future<bool> deactivateAutoAlarm(
    String busNo,
    String stationName,
    String routeId,
  ) async {
    final alarmKey = AlarmKeys.alarm(busNo, stationName, routeId);
    _pendingAutoAlarmDeactivations.add(alarmKey);

    try {
      logMessage(
        '📋 자동 알람 실행 중단 요청(스케줄 유지): $busNo번, $stationName',
        level: LogLevel.info,
      );

      final result = await cancelAlarmByRoute(busNo, stationName, routeId);
      if (!result) {
        logMessage(
          '⚠️ 자동 알람 실행 중단 중 네이티브 동기화 실패: $busNo번',
          level: LogLevel.warning,
        );
        return false;
      }

      logMessage(
        '✅ 자동 알람 실행 중단 완료(스케줄 유지): $busNo번',
        level: LogLevel.info,
      );
      return true;
    } catch (e) {
      logMessage('❌ 자동 알람 실행 중단 오류: $e', level: LogLevel.error);
      return false;
    } finally {
      _pendingAutoAlarmDeactivations.remove(alarmKey);
    }
  }

  Future<void> cancelScheduledAutoAlarm(String alarmId) async {
    final uniqueAlarmId = 'auto_alarm_$alarmId';

    // 현행 ID (결정적 해시 — 스케줄 등록과 동일)
    await _alarmFacade.nativeBridge
        .cancelNativeAutoAlarm(AlarmKeys.autoAlarmNativeId(alarmId));

    // 구버전 잔여 알람 정리:
    // ① 과거 Flutter가 쓰던 Dart String.hashCode 기반 ID
    // ② 과거 BootReceiver가 쓰던 Math.abs(Java hash(id)) 기반 ID
    final legacyDartId = uniqueAlarmId.hashCode;
    final legacyBootId = AlarmKeys.javaStringHashCode(alarmId).abs();
    for (final legacyId in {legacyDartId, legacyBootId}) {
      if (legacyId != AlarmKeys.autoAlarmNativeId(alarmId)) {
        await _alarmFacade.nativeBridge.cancelNativeAutoAlarm(legacyId);
      }
    }

    await _repository.removeScheduledAlarmMarker(uniqueAlarmId);
  }

  /// 자동 알람 스케줄 삭제(실행 중 추적은 중단 후 스케줄 제거)
  Future<bool> deleteAutoAlarm(
    String busNo,
    String stationName,
    String routeId,
  ) async {
    try {
      logMessage(
        '🗑️ 자동 알람 스케줄 삭제 요청: $busNo번, $stationName',
        level: LogLevel.info,
      );

      // 실행 중인 추적이 있다면 먼저 정리
      final stopped = await deactivateAutoAlarm(busNo, stationName, routeId);
      if (!stopped) {
        logMessage(
          '⚠️ 실행 중 추적 정리 실패했지만 스케줄 삭제는 계속 진행: $busNo번',
          level: LogLevel.warning,
        );
      }

      final removedCount = _alarmFacade.autoAlarmsList.length;
      final alarmsToDelete = _alarmFacade.autoAlarmsList
          .where(
            (alarm) =>
                alarm.busNo == busNo &&
                alarm.stationName == stationName &&
                alarm.routeId == routeId,
          )
          .toList();
      for (final alarm in alarmsToDelete) {
        await cancelScheduledAutoAlarm(alarm.id);
      }

      _alarmFacade.autoAlarmsList.removeWhere(
        (alarm) =>
            alarm.busNo == busNo &&
            alarm.stationName == stationName &&
            alarm.routeId == routeId,
      );
      final isDeleted =
          removedCount > _alarmFacade.autoAlarmsList.length;

      if (isDeleted) {
        await _alarmFacade.saveAutoAlarms();
        await _saveAlarms();
        notifyListeners();
      }

      if (isDeleted) {
        logMessage('✅ 자동 알람 스케줄 삭제 완료: $busNo번', level: LogLevel.info);
      } else {
        logMessage(
          '⚠️ 삭제 대상 자동 알람이 없어 변경 없음: $busNo번',
          level: LogLevel.warning,
        );
      }
      return true;
    } catch (e) {
      logMessage('❌ 자동 알람 스케줄 삭제 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  /// 기존 stopAutoAlarm은 하위 호환성용 유지.
  /// - 실행 중단: deactivateAutoAlarm
  /// - 영구 삭제: deleteAutoAlarm
  Future<bool> stopAutoAlarm(
    String busNo,
    String stationName,
    String routeId,
  ) async =>
      deactivateAutoAlarm(busNo, stationName, routeId);

  /// 알람 해제
  Future<void> stopAlarm(
    String busNo,
    String stationName, {
    bool isAutoAlarm = false,
  }) async {
    try {
      // TTS로 알람 해제 안내
      if (_useTTS) {
        await SimpleTTSHelper.speak(
          "$busNo번 버스 알람이 해제되었습니다.",
          earphoneOnly: !isAutoAlarm, // 일반 알람은 이어폰 전용, 자동 알람은 설정된 모드 사용
        );
      }

      // 알림 제거
      await _notificationService.cancelOngoingTracking();
    } catch (e) {
      logMessage('❌ 알람 해제 오류: $e', level: LogLevel.error);
    }
  }

  bool hasAlarm(String busNo, String stationName, String routeId) {
    // 일반 승차 알람만 확인 (자동 알람 제외)
    final bool hasRegularAlarm = _alarmFacade.activeAlarmsMap.values.any(
      (alarm) =>
          alarm.busNo == busNo &&
          alarm.stationName == stationName &&
          alarm.routeId == routeId,
    );

    // 자동 알람 여부 확인
    final bool hasAutoAlarm = _alarmFacade.autoAlarmsList.any(
      (alarm) =>
          alarm.busNo == busNo &&
          alarm.stationName == stationName &&
          alarm.routeId == routeId,
    );

    // 추적 중인지 여부 확인
    final bool isTracking = isInTrackingMode;
    bool isThisBusTracked = false;
    if (isTracking && _alarmFacade.trackedRouteId != null) {
      // 현재 추적 중인 버스와 동일한지 확인
      isThisBusTracked = _alarmFacade.trackedRouteId == routeId;
    }

    // 자동 알람이 있으면 승차 알람은 비활성화
    return hasRegularAlarm &&
        !hasAutoAlarm &&
        (!isTracking || isThisBusTracked);
  }

  bool hasAutoAlarm(String busNo, String stationName, String routeId) {
    return _alarmFacade.autoAlarmsList.any(
      (alarm) =>
          alarm.busNo == busNo &&
          alarm.stationName == stationName &&
          alarm.routeId == routeId,
    );
  }

  alarm_model.AlarmData? getAutoAlarm(
    String busNo,
    String stationName,
    String routeId,
  ) {
    try {
      return _alarmFacade.autoAlarmsList.firstWhere(
        (alarm) =>
            alarm.busNo == busNo &&
            alarm.stationName == stationName &&
            alarm.routeId == routeId,
      );
    } catch (e) {
      debugPrint('자동 알람을 찾을 수 없음: $busNo, $stationName, $routeId');
      return null;
    }
  }

  alarm_model.AlarmData? findAlarm(
    String busNo,
    String stationName,
    String routeId,
  ) {
    try {
      return _alarmFacade.activeAlarmsMap.values.firstWhere(
        (alarm) =>
            alarm.busNo == busNo &&
            alarm.stationName == stationName &&
            alarm.routeId == routeId,
      );
    } catch (e) {
      try {
        return _alarmFacade.autoAlarmsList.firstWhere(
          (alarm) =>
              alarm.busNo == busNo &&
              alarm.stationName == stationName &&
              alarm.routeId == routeId,
        );
      } catch (e) {
        return null;
      }
    }
  }

  Future<bool> setOneTimeAlarm(
    String busNo,
    String stationName,
    int remainingMinutes, {
    String routeId = '',
    String stationId = '',
    bool useTTS = true,
    bool isImmediateAlarm = true,
    bool? earphoneOnlyOverride,
    bool? vibrateOverride,
    String? currentStation,
  }) async {
    try {
      logMessage(
        '🚌 일반 알람 설정 시작: $busNo번 버스, $stationName, $remainingMinutes분',
      );

      final id = AlarmKeys.alarm(busNo, stationName, routeId);

      // 알람 데이터 생성
      final alarmData = alarm_model.AlarmData(
        id: id,
        busNo: busNo,
        stationName: stationName,
        remainingMinutes: remainingMinutes,
        routeId: routeId,
        scheduledTime: DateTime.now().add(Duration(minutes: remainingMinutes)),
        currentStation: currentStation,
        useTTS: useTTS,
        isAutoAlarm: false,
        isCommuteAlarm: false,
      );

      // 알람 저장 (키는 알람의 고유 ID 문자열 사용)
      _alarmFacade.activeAlarmsMap[alarmData.id] = alarmData;
      await _saveAlarms();

      final settingsService = SettingsService();
      await settingsService.initialize();

      // TTS 알림 시작 (승차알람은 항상 TTS 발화 - 사용자가 직접 버튼 클릭)
      // isImmediateAlarm이 true이면 무조건 TTS 발화
      if (isImmediateAlarm || useTTS) {
        try {
          await SimpleTTSHelper.initialize();
          await SimpleTTSHelper.setVolume(1.0);

          final shouldVibrate = vibrateOverride ??
              ((earphoneOnlyOverride == true) &&
                  settingsService.vibrate &&
                  settingsService.earphoneAlarmVibrate);
          if (shouldVibrate) {
            HapticFeedback.vibrate();
          }

          logMessage(
            '🔊 일반 알람 TTS 발화 시도: $busNo번 버스, $remainingMinutes분 후',
            level: LogLevel.info,
          );

          // 사용자의 스피커 모드 설정 확인
          final speakerMode = settingsService.speakerMode;
          final isSpeakerMode = speakerMode == SettingsService.speakerModeSpeaker;

          logMessage(
            '🔊 스피커 모드: ${settingsService.getSpeakerModeName(speakerMode)}',
            level: LogLevel.info,
          );

          // 승차알람은 사용자가 직접 설정한 것이므로 강제로 발화
          // 스피커 모드인 경우 force=true로 설정하여 무조건 발화
          // isImmediateAlarm이 true이면 force=true로 설정 (중복 체크 무시)
          final success = await SimpleTTSHelper.speak(
            "$busNo번 버스가 약 $remainingMinutes분 후 도착 예정입니다.",
            force: isImmediateAlarm || isSpeakerMode, // 승차알람이거나 스피커 모드면 강제 발화
            earphoneOnly: earphoneOnlyOverride ??
                (speakerMode == SettingsService.speakerModeHeadset), // 이어폰 전용 모드만 true
          );

          if (success) {
            logMessage(
              '✅ 일반 알람 TTS 발화 완료 (모드: ${settingsService.getSpeakerModeName(speakerMode)})',
              level: LogLevel.info,
            );
          } else {
            logMessage(
              '❌ 일반 알람 TTS 발화 실패',
              level: LogLevel.warning,
            );
          }
        } catch (e) {
          logMessage('❌ 일반 알람 TTS 발화 오류: $e', level: LogLevel.error);
        }
      }

      // 실시간 버스 추적 서비스 시작
      if (stationId.isNotEmpty) {
        try {
          await startBusMonitoringService(
            stationId: stationId,
            stationName: stationName,
            routeId: routeId,
            busNo: busNo,
          );
          logMessage(
            '✅ 버스 추적 서비스 시작: $busNo번 버스',
            level: LogLevel.info,
          );
        } catch (e) {
          logMessage('❌ 버스 추적 서비스 시작 오류: $e', level: LogLevel.error);
        }
      } else {
        logMessage(
          '⚠️ stationId가 없어서 실시간 추적을 시작할 수 없습니다',
          level: LogLevel.warning,
        );
      }

      logMessage('✅ 알람 설정 완료: $busNo번 버스');
      notifyListeners();
      return true;
    } catch (e) {
      logMessage('❌ 알람 설정 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  Future<void> _saveAlarms() async {
    await _repository.saveActiveAlarms(_alarmFacade.activeAlarmsMap.values);
  }

  // 특정 추적 중지 메서드 추가
  Future<bool> stopSpecificTracking({
    required String busNo,
    required String stationName,
    required String routeId,
  }) async {
    try {
      logMessage('🐛 [DEBUG] 특정 추적 중지 요청: $busNo번 버스, $stationName, $routeId');

      // 1. 네이티브 서비스에 특정 추적 중지 요청
      await _alarmFacade.nativeBridge.stopSpecificTracking(
        busNo: busNo,
        routeId: routeId,
        stationName: stationName,
      );

      // 2. Flutter 측 상태 업데이트
      await cancelAlarmByRoute(busNo, stationName, routeId);

      logMessage('🐛 [DEBUG] ✅ 특정 추적 중지 완료: $busNo번 버스');
      return true;
    } catch (e) {
      logMessage('❌ [ERROR] 특정 추적 중지 실패: $e', level: LogLevel.error);
      return false;
    }
  }

  // 모든 추적 중지 메서드 개선
  Future<bool> stopAllTracking() async {
    try {
      logMessage('🐛 [DEBUG] 모든 추적 중지 요청: ${_alarmFacade.activeAlarmsMap.length}개');

      // 1. 네이티브 서비스 완전 중지
      await _notificationService.cancelOngoingTracking();

      // 2. TTS 추적 중지
      try {
        await _alarmFacade.nativeBridge.stopTtsTracking();
        logMessage('✅ stopTtsTracking 호출 완료', level: LogLevel.debug);
      } catch (e) {
        logMessage('⚠️ stopTtsTracking 실패 (무시): $e', level: LogLevel.warning);
      }

      // 3. 모든 알림 취소
      try {
        await _notificationService.cancelAllNotifications();
        logMessage('✅ cancelAllNotifications 호출 완료', level: LogLevel.debug);
      } catch (e) {
        logMessage(
          '⚠️ cancelAllNotifications 실패 (무시): $e',
          level: LogLevel.warning,
        );
      }

      // 4. Flutter 측 상태 완전 정리
      _alarmFacade.activeAlarmsMap.clear();
      _alarmFacade.clearCachedBusInfo();
      _alarmFacade.isTrackingMode = false;
      _alarmFacade.trackedRouteId = null;
      _alarmFacade.state.processedNotifications.clear();

      // 5. 상태 저장 및 UI 업데이트
      await _saveAlarms();
      notifyListeners();

      logMessage('🐛 [DEBUG] ✅ 모든 추적 중지 완료');
      return true;
    } catch (e) {
      logMessage('❌ [ERROR] 모든 추적 중지 실패: $e', level: LogLevel.error);
      return false;
    }
  }

  /// 알람 취소 메서드
  Future<bool> cancelAlarmByRoute(
    String busNo,
    String stationName,
    String routeId,
  ) async {
    logMessage(
      '🚌 [Request] 알람 취소 요청: $busNo번 버스, $stationName, routeId: $routeId',
    );

    final String alarmKey = AlarmKeys.alarm(busNo, stationName, routeId);
    final String cacheKey = AlarmKeys.cache(busNo, routeId);
    bool shouldForceStopNative = false;

    try {
      // --- Perform Flutter state update immediately ---
      final alarmToRemove = _alarmFacade.activeAlarmsMap[alarmKey];

      if (alarmToRemove != null) {
        // 알람을 완전히 제거
        _alarmFacade.activeAlarmsMap.remove(alarmKey);
        logMessage(
          '[${alarmToRemove.busNo}] Flutter activeAlarms 목록에서 완전 제거',
          level: LogLevel.debug,
        );
      } else {
        logMessage(
          '⚠️ 취소 요청한 알람($alarmKey)이 Flutter 활성 알람 목록에 없음 (취소 전).',
          level: LogLevel.warning,
        );
      }

      _alarmFacade.removeCachedBusInfoByKey(cacheKey);
      logMessage('[$cacheKey] 버스 정보 캐시 즉시 제거', level: LogLevel.debug);

      // Check if the route being cancelled is the one being tracked OR if it's the last alarm
      if (_alarmFacade.trackedRouteId == routeId) {
        _alarmFacade.trackedRouteId = null;
        logMessage('추적 Route ID 즉시 초기화됨 (취소된 알람과 일치)', level: LogLevel.debug);
        if (_alarmFacade.activeAlarmsMap.isEmpty) {
          _alarmFacade.isTrackingMode = false;
          shouldForceStopNative = true;
          logMessage('추적 모드 즉시 비활성화 (활성 알람 없음)', level: LogLevel.debug);
        } else {
          _alarmFacade.isTrackingMode = true;
          logMessage('다른 활성 알람 존재, 추적 모드 유지', level: LogLevel.debug);
        }
      } else if (_alarmFacade.activeAlarmsMap.isEmpty) {
        _alarmFacade.isTrackingMode = false;
        _alarmFacade.trackedRouteId = null;
        shouldForceStopNative = true;
        logMessage('마지막 알람 취소됨, 추적 모드 비활성화', level: LogLevel.debug);
      }

      await _saveAlarms(); // Persist the removal immediately
      notifyListeners(); // Update UI immediately
      logMessage(
        '[$alarmKey] Flutter 상태 즉시 업데이트 및 리스너 알림 완료',
        level: LogLevel.debug,
      );
      // --- End immediate Flutter state update ---

      // --- Send request to Native ---
      try {
        if (shouldForceStopNative) {
          logMessage('✅ 마지막 알람 취소 - 추적 완전 종료', level: LogLevel.warning);
          
          // 1. 네이티브 추적 강제 중지
          try {
            await _alarmFacade.nativeBridge.forceStopTracking();
            logMessage('✅ 네이티브 추적 완전 정지 완료', level: LogLevel.warning);
          } catch (e) {
            logMessage('❌ 네이티브 추적 정지 실패: $e', level: LogLevel.error);
          }
          
          // 2. TTS 완전 정지
          try {
            await _alarmFacade.nativeBridge.stopAllTts();
            logMessage('✅ TTS 완전 정지 완료', level: LogLevel.warning);
          } catch (e) {
            logMessage('❌ TTS 정지 실패 (무시): $e', level: LogLevel.warning);
          }
          
          // 3. 알림 모두 제거
          try {
            await _notificationService.cancelOngoingTracking();
            logMessage('✅ 알림 제거 완료', level: LogLevel.debug);
          } catch (e) {
            logMessage('❌ 알림 제거 실패 (무시): $e', level: LogLevel.warning);
          }
        } else {
          // If not the last alarm, just cancel the specific notification/route tracking
          logMessage(
            '다른 알람 존재, 네이티브 특정 알람($routeId) 취소 요청',
            level: LogLevel.debug,
          );
          await _alarmFacade.nativeBridge.cancelAlarmNotification(
            routeId: routeId,
            busNo: busNo,
            stationName: stationName,
          );
          logMessage('✅ 네이티브 특정 알람 취소 요청 전송 완료', level: LogLevel.debug);
        }
      } catch (nativeError) {
        logMessage('❌ 네이티브 요청 전송 오류: $nativeError', level: LogLevel.error);
        return false; // Indicate that the native part failed
      }
      // --- End Native request ---

      return true; // Return true as the action was initiated and Flutter state updated.
    } catch (e) {
      logMessage('❌ 알람 취소 처리 중 오류 (Flutter 업데이트): $e', level: LogLevel.error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> refreshAutoAlarmBusInfo(AutoAlarm alarm) async {
    try {
      if (!alarm.isActive) {
        logMessage('비활성화된 알람은 정보를 업데이트하지 않습니다', level: LogLevel.debug);
        return false;
      }

      logMessage(
        '🔄 자동 알람 버스 정보 업데이트 시작: [36m${alarm.routeNo}번, ${alarm.stationName}[0m',
        level: LogLevel.debug,
      );

      // ✅ stationId 보정 로직 개선 (DB 실패 시 매핑 사용)
      String effectiveStationId = alarm.stationId;
      if (effectiveStationId.isEmpty ||
          effectiveStationId.length < 10 ||
          !effectiveStationId.startsWith('7')) {
        // 먼저 매핑을 통해 stationId 가져오기
        effectiveStationId = resolveStationIdFromName(
          alarm.stationName,
          alarm.routeId,
        );

        // DB를 통한 추가 보정 시도 (선택사항)
        try {
          final dbHelper = DatabaseHelper();
          final resolvedStationId = await dbHelper.getStationIdFromWincId(
            alarm.stationName,
          );
          if (resolvedStationId != null && resolvedStationId.isNotEmpty) {
            effectiveStationId = resolvedStationId;
            logMessage(
              '✅ 자동 알람 DB stationId 보정: ${alarm.stationName} → $effectiveStationId',
              level: LogLevel.debug,
            );
          } else {
            logMessage(
              '⚠️ DB stationId 보정 실패, 매핑값 사용: ${alarm.stationName} → $effectiveStationId',
              level: LogLevel.debug,
            );
          }
        } catch (e) {
          logMessage(
            '❌ DB stationId 보정 중 오류, 매핑값 사용: $e → $effectiveStationId',
            level: LogLevel.warning,
          );
        }

        // 매핑도 실패한 경우에만 오류 처리
        if (effectiveStationId.isEmpty || effectiveStationId == alarm.routeId) {
          logMessage(
            '❌ stationId 보정 완전 실패: ${alarm.stationName}',
            level: LogLevel.error,
          );
          return false;
        }
      }

      // ✅ API 호출을 통한 버스 실시간 정보 가져오기
      try {
        final result = await _alarmFacade.nativeBridge.getBusArrivalByRouteId(
          stationId: effectiveStationId,
          routeId: alarm.routeId,
        );

        logMessage(
          '🚌 [API 응답] 자동 알람 응답 수신: ${result?.runtimeType}',
          level: LogLevel.debug,
        );

        if (result != null) {
          final arrival = parseAutoAlarmArrival(
            result,
            routeNo: alarm.routeNo,
            routeId: alarm.routeId,
          );

          if (arrival != null) {
            // 캐시에 저장
            final cachedInfo = CachedBusInfo(
              remainingMinutes: arrival.remainingMinutes,
              currentStation: arrival.currentStation,
              stationName: alarm.stationName,
              busNo: alarm.routeNo,
              routeId: alarm.routeId,
              lastUpdated: DateTime.now(),
            );
            _alarmFacade.updateCachedBusInfo(cachedInfo);

            logMessage(
              '✅ 자동 알람 버스 정보 업데이트 완료: ${alarm.routeNo}번, ${arrival.remainingMinutes}분 후 도착, 위치: ${arrival.currentStation}',
              level: LogLevel.info,
            );

            // 버스 모니터링 서비스 시작 (10분 이내이고 아직 추적 중이 아닐 때만)
            if (arrival.remainingMinutes <= 10 &&
                arrival.remainingMinutes >= 0 &&
                _alarmFacade.trackedRouteId != alarm.routeId) {
              try {
                await startBusMonitoringService(
                  routeId: alarm.routeId,
                  stationId: effectiveStationId,
                  busNo: alarm.routeNo,
                  stationName: alarm.stationName,
                );
                logMessage(
                  '✅ 자동 알람 버스 모니터링 시작: ${alarm.routeNo}번 (${arrival.remainingMinutes}분 후 도착)',
                  level: LogLevel.info,
                );
              } catch (e) {
                logMessage(
                  '❌ 자동 알람 버스 모니터링 시작 실패: $e',
                  level: LogLevel.error,
                );
              }
            }

            // UI 업데이트
            notifyListeners();
            return true;
          }
        } else {
          logMessage('⚠️ API 응답이 null입니다', level: LogLevel.warning);
        }
      } catch (e) {
        logMessage('❌ 버스 API 호출 오류: $e', level: LogLevel.error);
      }

      return false;
    } catch (e) {
      logMessage('❌ 자동 알람 버스 정보 업데이트 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  Future<void> updateAutoAlarms(List<AutoAlarm> autoAlarms) async {
    try {
      AlarmRepository.ensureBackgroundMessenger('updateAutoAlarms');

      logMessage('🔄 자동 알람 업데이트 시작: ${autoAlarms.length}개');
      _alarmFacade.autoAlarmsList.clear();

      // 다음 알람 시간 계산에 쓸 공휴일·예외 날짜 (HolidayService가 캐싱)
      final allHolidays = await _getUpcomingExclusionDates();

      for (var alarm in autoAlarms) {
        logMessage('📝 알람 처리 중: ${alarm.routeNo}번, ${alarm.stationName}');

        await cancelScheduledAutoAlarm(alarm.id);

        if (!alarm.isActive) {
          logMessage('  ⚠️ 비활성화된 알람 예약 취소 후 건너뛰기');
          continue;
        }

        final now = DateTime.now();
        final DateTime? scheduledTime = alarm.getNextAlarmTime(holidays: allHolidays);

        if (scheduledTime == null) {
          logMessage(
            '  ⚠️ 유효한 다음 알람 시간을 찾지 못함: ${alarm.routeNo}',
            level: LogLevel.warning,
          );
          continue;
        }

        final timeUntilAlarm = scheduledTime.difference(now);
        logMessage('  ⏰ 다음 알람까지 ${timeUntilAlarm.inMinutes}분 남음');

        final alarmData = alarm_model.AlarmData(
          id: alarm.id,
          busNo: alarm.routeNo,
          stationName: alarm.stationName,
          remainingMinutes: 0,
          routeId: alarm.routeId,
          scheduledTime: scheduledTime,
          useTTS: alarm.useTTS,
          isAutoAlarm: true,
          isCommuteAlarm: alarm.isCommuteAlarm,
          repeatDays: alarm.repeatDays, // 반복 요일 정보 포함
        );
        _alarmFacade.autoAlarmsList.add(alarmData);
        logMessage('  ✅ 알람 데이터 생성 완료');

        await _alarmFacade.scheduleAutoAlarm(alarm, scheduledTime);
      }

      logMessage('✅ 자동 알람 업데이트 완료: ${_alarmFacade.autoAlarmsList.length}개');
    } catch (e) {
      logMessage('❌ 자동 알람 업데이트 오류: $e', level: LogLevel.error);
      logMessage('  - 스택 트레이스: ${e is Error ? e.stackTrace : "없음"}');
    }
  }
}
