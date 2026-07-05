import 'package:flutter/services.dart';

import '../../main.dart' show logMessage, LogLevel;
import 'alarm_facade.dart';
import 'alarm_keys.dart';

/// 네이티브 → Flutter 알람 이벤트(MethodChannel) 처리.
///
/// 알람 상태는 facade를 통해 직접 조작하고, 저장·UI 갱신·자동알람 중단은
/// AlarmService가 주입한 콜백으로 위임한다.
class AlarmEventHandler {
  AlarmEventHandler({
    required AlarmFacade facade,
    required Future<void> Function() saveAlarms,
    required void Function() notifyListeners,
    required Future<bool> Function(
            String busNo, String stationName, String routeId)
        deactivateAutoAlarm,
    required bool Function(String alarmKey) isAutoAlarmDeactivationPending,
    required void Function() stopRealTimeBusUpdates,
  })  : _facade = facade,
        _saveAlarms = saveAlarms,
        _notifyListeners = notifyListeners,
        _deactivateAutoAlarm = deactivateAutoAlarm,
        _isAutoAlarmDeactivationPending = isAutoAlarmDeactivationPending,
        _stopRealTimeBusUpdates = stopRealTimeBusUpdates;

  final AlarmFacade _facade;
  final Future<void> Function() _saveAlarms;
  final void Function() _notifyListeners;
  final Future<bool> Function(String busNo, String stationName, String routeId)
      _deactivateAutoAlarm;
  final bool Function(String alarmKey) _isAutoAlarmDeactivationPending;
  final void Function() _stopRealTimeBusUpdates;

  Future<dynamic> handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onAlarmCanceledFromNotification':
          return _onAlarmCanceledFromNotification(call);
        case 'onAllAlarmsCanceled':
          return _onAllAlarmsCanceled();
        case 'stopAutoAlarmFromBroadcast':
          return _onStopAutoAlarmFromBroadcast(call);
        case 'onAutoAlarmStarted':
          final Map<String, dynamic> args =
              Map<String, dynamic>.from(call.arguments);
          logMessage(
            '✅ [네이티브] 자동 알람 시작: ${args['busNo']}, ${args['stationName']}',
            level: LogLevel.info,
          );
          return true;
        case 'onAutoAlarmStopped':
          final Map<String, dynamic> stoppedArgs =
              Map<String, dynamic>.from(call.arguments);
          logMessage(
            '🛑 [네이티브] 자동 알람 종료: ${stoppedArgs['busNo']}, ${stoppedArgs['stationName']}',
            level: LogLevel.info,
          );
          return true;
        default:
          logMessage(
            'Unhandled method call: ${call.method}',
            level: LogLevel.warning,
          );
          return null;
      }
    } catch (e) {
      logMessage('메서드 채널 핸들러 오류 (${call.method}): $e', level: LogLevel.error);
      return null;
    }
  }

  Future<bool> _onAlarmCanceledFromNotification(MethodCall call) async {
    final Map<String, dynamic> args =
        Map<String, dynamic>.from(call.arguments);
    final String busNo = args['busNo'] ?? '';
    final String routeId = args['routeId'] ?? '';
    final String stationName = args['stationName'] ?? '';
    final int? timestamp = args['timestamp'];

    // 중복 이벤트 방지 체크
    final String eventKey =
        AlarmKeys.cancellationEvent(busNo, stationName, routeId);
    if (_isDuplicateEvent(eventKey, timestamp)) return true;

    logMessage(
      '🔔 [노티피케이션] 네이티브에서 특정 알람 취소 이벤트 수신: $busNo번, $stationName, $routeId',
      level: LogLevel.info,
    );

    // 즉시 Flutter 측 상태 동기화 (낙관적 업데이트)
    final String alarmKey = AlarmKeys.alarm(busNo, stationName, routeId);
    final removedAlarm = _facade.activeAlarmsMap.remove(alarmKey);

    if (removedAlarm != null) {
      await _cleanupAfterRemoval(removedKey: alarmKey, routeId: routeId, busNo: busNo);
      return true;
    }

    // 키로 찾지 못한 경우 routeId로 검색하여 제거 (안전장치)
    final fallbackKey = _facade.activeAlarmsMap.keys.firstWhere(
      (k) => _facade.activeAlarmsMap[k]?.routeId == routeId,
      orElse: () => '',
    );

    if (fallbackKey.isNotEmpty) {
      _facade.activeAlarmsMap.remove(fallbackKey);
      logMessage(
        '🔔 [노티피케이션] 알람 취소 감지 및 제거 (RouteId 기반): $fallbackKey',
        level: LogLevel.info,
      );
      await _cleanupAfterRemoval(
          removedKey: fallbackKey, routeId: routeId, busNo: busNo);
      return true;
    }

    // 자동 알람 목록에서 확인
    logMessage(
        '🔍 [Debug] 자동 알람 검색 시작: busNo=$busNo, stationName=$stationName, routeId=$routeId');

    final autoAlarmIndex = _facade.autoAlarmsList.indexWhere(
      (a) =>
          a.busNo == busNo &&
          a.stationName == stationName &&
          a.routeId == routeId,
    );

    if (autoAlarmIndex != -1) {
      logMessage(
        '🔔 [노티피케이션] 자동 알람 취소 감지: $busNo번, $stationName',
        level: LogLevel.info,
      );
      if (_isAutoAlarmDeactivationPending(alarmKey)) {
        logMessage(
          '🛑 자동 알람 중단 요청 무시(이미 처리 중): $alarmKey',
          level: LogLevel.debug,
        );
      } else {
        await _deactivateAutoAlarm(busNo, stationName, routeId);
      }
    } else {
      logMessage(
        '⚠️ 해당 알람($alarmKey)이 Flutter에 없음 - 상태 정리 및 강제 UI 업데이트 수행',
        level: LogLevel.warning,
      );

      // 상태 정리
      if (_facade.activeAlarmsMap.isEmpty && _facade.isTrackingMode) {
        _facade.isTrackingMode = false;
        _facade.trackedRouteId = null;
        logMessage('🛑 추적 모드 비활성화 (상태 정리)', level: LogLevel.info);
      }

      // UI 강제 업데이트
      _notifyListeners();
    }
    return true;
  }

  /// 3초 이내 같은 취소 이벤트는 무시하고, 30초 지난 기록은 청소한다.
  bool _isDuplicateEvent(String eventKey, int? timestamp) {
    final timestamps = _facade.state.processedEventTimestamps;

    if (timestamp != null && timestamps.containsKey(eventKey)) {
      final timeDiff = timestamp - timestamps[eventKey]!;
      if (timeDiff < 3000) {
        logMessage(
          '⚠️ [중복방지] 이벤트 무시: $eventKey (${timeDiff}ms 전에 처리됨)',
          level: LogLevel.warning,
        );
        return true;
      }
    }

    if (timestamp != null) {
      timestamps[eventKey] = timestamp;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    timestamps.removeWhere((_, value) => now - value > 30000);
    return false;
  }

  /// 알람 제거 후 공통 정리: 캐시 삭제, 추적 상태 갱신, 저장, UI 알림.
  Future<void> _cleanupAfterRemoval({
    required String removedKey,
    required String routeId,
    required String busNo,
  }) async {
    // 캐시 정리
    _facade.removeCachedBusInfoByKey(AlarmKeys.cache(busNo, routeId));

    // 추적 상태 업데이트
    if (_facade.trackedRouteId == routeId) {
      _facade.trackedRouteId = null;
      if (_facade.activeAlarmsMap.isEmpty) {
        _facade.isTrackingMode = false;
        logMessage(
          '🛑 추적 모드 비활성화 (취소된 알람이 추적 중이던 알람)',
          level: LogLevel.info,
        );
      }
    } else if (_facade.activeAlarmsMap.isEmpty) {
      _facade.isTrackingMode = false;
      _facade.trackedRouteId = null;
      logMessage('🛑 추적 모드 비활성화 (모든 알람 취소됨)', level: LogLevel.info);
    }

    // 상태 저장 및 UI 업데이트
    await _saveAlarms();
    _notifyListeners();

    logMessage(
      '✅ 네이티브 이벤트에 따른 Flutter 알람 동기화 완료: $removedKey',
      level: LogLevel.info,
    );
  }

  Future<bool> _onAllAlarmsCanceled() async {
    logMessage(
      '🛑🛑🛑 네이티브에서 모든 알람 취소 이벤트 수신 - 사용자가 "추적 중지" 버튼을 눌렀습니다!',
      level: LogLevel.warning,
    );

    // 🛑 실시간 버스 업데이트 타이머 중지 (중요!)
    try {
      _stopRealTimeBusUpdates();
      logMessage('🛑 실시간 버스 업데이트 타이머 강제 중지 완료', level: LogLevel.info);
    } catch (e) {
      logMessage('❌ 실시간 버스 업데이트 타이머 중지 오류: $e', level: LogLevel.error);
    }

    // 모든 활성 알람 제거
    if (_facade.activeAlarmsMap.isNotEmpty) {
      _facade.activeAlarmsMap.clear();
      _facade.clearCachedBusInfo();
      _facade.isTrackingMode = false;
      _facade.trackedRouteId = null;
      await _saveAlarms();
      logMessage('✅ 모든 알람 취소 완료 (네이티브 이벤트에 의해)', level: LogLevel.info);
      _notifyListeners();
    }

    return true;
  }

  Future<bool> _onStopAutoAlarmFromBroadcast(MethodCall call) async {
    final Map<String, dynamic> args =
        Map<String, dynamic>.from(call.arguments);
    final String busNo = args['busNo'] ?? '';
    final String stationName = args['stationName'] ?? '';
    final String routeId = args['routeId'] ?? '';

    logMessage(
      '🔔 네이티브에서 자동알람 중지 브로드캐스트 수신: $busNo, $stationName, $routeId',
      level: LogLevel.info,
    );

    try {
      final result = await _deactivateAutoAlarm(busNo, stationName, routeId);
      if (result) {
        logMessage(
          '✅ 자동알람 중지 완료 (브로드캐스트에 의해): $busNo번',
          level: LogLevel.info,
        );
      } else {
        logMessage(
          '❌ 자동알람 중지 실패 (브로드캐스트에 의해): $busNo번',
          level: LogLevel.error,
        );
      }
    } catch (e) {
      logMessage('❌ 자동알람 중지 처리 오류: $e', level: LogLevel.error);
    }

    return true;
  }
}
