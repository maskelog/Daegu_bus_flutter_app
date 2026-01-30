import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auto_alarm.dart';
import '../models/alarm_data.dart' as alarm_model;
import '../utils/simple_tts_helper.dart';
import 'notification_service.dart';
import 'settings_service.dart';
import '../main.dart' show logMessage, LogLevel;
import '../utils/database_helper.dart';
import 'alarm/alarm_facade.dart';
import 'alarm/cached_bus_info.dart';

class AlarmService extends ChangeNotifier {
  final NotificationService _notificationService;
  final SettingsService _settingsService;
  late final AlarmFacade _alarmFacade;

  bool get _useTTS => _settingsService.useTts;
  Timer? _alarmCheckTimer;
  bool _initialized = false;
  MethodChannel? _methodChannel;
  DateTime _lastRefreshAt = DateTime.fromMillisecondsSinceEpoch(0);
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
      validateRequiredFields: _validateRequiredFields,
      resolveStationId: _getStationIdFromName,
      startMonitoring: ({
        required String stationId,
        required String stationName,
        required String routeId,
        required String busNo,
      }) {
        return startBusMonitoringService(
          stationId: stationId,
          stationName: stationName,
          routeId: routeId,
          busNo: busNo,
        );
      },
      refreshBusInfo: refreshAutoAlarmBusInfo,
      saveAlarms: _saveAlarms,
      restartPreventionDurationMs: _restartPreventionDuration,
    );
    _setupMethodChannel();
  }

  void _setupMethodChannel() {
    _methodChannel = const MethodChannel('com.example.daegu_bus_app/bus_api');
    _methodChannel?.setMethodCallHandler(_handleMethodCall);
    _alarmFacade.setMethodChannel(_methodChannel);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onAlarmCanceledFromNotification':
          final Map<String, dynamic> args = Map<String, dynamic>.from(
            call.arguments,
          );
          final String busNo = args['busNo'] ?? '';
          final String routeId = args['routeId'] ?? '';
          final String stationName = args['stationName'] ?? '';
          final int? timestamp = args['timestamp'];

          // 중복 이벤트 방지 체크
          final String eventKey =
              "${busNo}_${routeId}_${stationName}_cancellation";
          if (timestamp != null &&
              _alarmFacade.state.processedEventTimestamps.containsKey(eventKey)) {
            final lastTimestamp = _alarmFacade.state.processedEventTimestamps[eventKey]!;
            final timeDiff = timestamp - lastTimestamp;
            if (timeDiff < 3000) {
              // 3초 이내 중복 이벤트 무시
              logMessage(
                '⚠️ [중복방지] 이벤트 무시: $eventKey (${timeDiff}ms 전에 처리됨)',
                level: LogLevel.warning,
              );
              return true;
            }
          }

          // 이벤트 시간 기록
          if (timestamp != null) {
            _alarmFacade.state.processedEventTimestamps[eventKey] = timestamp;
          }

          // 오래된 이벤트 정리 (30초 이전)
          final now = DateTime.now().millisecondsSinceEpoch;
          final expiredKeys = _alarmFacade.state.processedEventTimestamps.entries
              .where((entry) => now - entry.value > 30000)
              .map((entry) => entry.key)
              .toList();
          for (var key in expiredKeys) {
            _alarmFacade.state.processedEventTimestamps.remove(key);
          }

          logMessage(
            '🔔 [노티피케이션] 네이티브에서 특정 알람 취소 이벤트 수신: $busNo번, $stationName, $routeId',
            level: LogLevel.info,
          );

          // 즉시 Flutter 측 상태 동기화 (낙관적 업데이트)
          final String alarmKey = "${busNo}_${stationName}_$routeId";
          final removedAlarm = _alarmFacade.activeAlarmsMap.remove(alarmKey);

          if (removedAlarm != null) {
            // 수동으로 중지된 알람으로 표시 (자동 알람 재시작 방지)
            _alarmFacade.state.manuallyStoppedAlarms.add(alarmKey);
            _alarmFacade.state.manuallyStoppedTimestamps[alarmKey] = DateTime.now();
            logMessage('🚫 수동 중지 알람 추가: $alarmKey', level: LogLevel.info);

            // 캐시 정리
            final cacheKey = "${busNo}_$routeId";
            _alarmFacade.removeCachedBusInfoByKey(cacheKey);

            // 추적 상태 업데이트
            if (_alarmFacade.trackedRouteId == routeId) {
              _alarmFacade.trackedRouteId = null;
              if (_alarmFacade.activeAlarmsMap.isEmpty) {
                _alarmFacade.isTrackingMode = false;
                logMessage(
                  '🛑 추적 모드 비활성화 (취소된 알람이 추적 중이던 알람)',
                  level: LogLevel.info,
                );
              }
            } else if (_alarmFacade.activeAlarmsMap.isEmpty) {
              _alarmFacade.isTrackingMode = false;
              _alarmFacade.trackedRouteId = null;
              logMessage('🛑 추적 모드 비활성화 (모든 알람 취소됨)', level: LogLevel.info);
            }

            // 상태 저장 및 UI 업데이트
            await _saveAlarms();
            notifyListeners();

            logMessage(
              '✅ 네이티브 이벤트에 따른 Flutter 알람 동기화 완료: $alarmKey',
              level: LogLevel.info,
            );
          } else {
            // 키로 찾지 못한 경우 routeId로 검색하여 제거 (안전장치)
            final fallbackKey = _alarmFacade.activeAlarmsMap.keys.firstWhere(
              (k) => _alarmFacade.activeAlarmsMap[k]?.routeId == routeId,
              orElse: () => '',
            );

            if (fallbackKey.isNotEmpty) {
              final removedAlarm = _alarmFacade.activeAlarmsMap.remove(fallbackKey);
              logMessage(
                '🔔 [노티피케이션] 알람 취소 감지 및 제거 (RouteId 기반): $fallbackKey',
                level: LogLevel.info,
              );

              // 수동으로 중지된 알람으로 표시 (자동 알람 재시작 방지)
              _alarmFacade.state.manuallyStoppedAlarms.add(fallbackKey);
              _alarmFacade.state.manuallyStoppedTimestamps[fallbackKey] = DateTime.now();
              logMessage('🚫 수동 중지 알람 추가: $fallbackKey', level: LogLevel.info);

              // 캐시 정리
              final cacheKey = "${busNo}_$routeId";
              _alarmFacade.removeCachedBusInfoByKey(cacheKey);

              // 추적 상태 업데이트
              if (_alarmFacade.trackedRouteId == routeId) {
                _alarmFacade.trackedRouteId = null;
                if (_alarmFacade.activeAlarmsMap.isEmpty) {
                  _alarmFacade.isTrackingMode = false;
                  logMessage(
                    '🛑 추적 모드 비활성화 (취소된 알람이 추적 중이던 알람)',
                    level: LogLevel.info,
                  );
                }
              } else if (_alarmFacade.activeAlarmsMap.isEmpty) {
                _alarmFacade.isTrackingMode = false;
                _alarmFacade.trackedRouteId = null;
                logMessage('🛑 추적 모드 비활성화 (모든 알람 취소됨)', level: LogLevel.info);
              }

              // 상태 저장 및 UI 업데이트
              await _saveAlarms();
              notifyListeners();

              logMessage(
                '✅ 네이티브 이벤트에 따른 Flutter 알람 동기화 완료 (RouteId 기반): $fallbackKey',
                level: LogLevel.info,
              );
            } else {
              // 자동 알람 목록에서 확인
              logMessage(
                  '🔍 [Debug] 자동 알람 검색 시작: busNo=$busNo, stationName=$stationName, routeId=$routeId');

              final autoAlarmIndex = _alarmFacade.autoAlarmsList.indexWhere(
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
                await stopAutoAlarm(busNo, stationName, routeId);
              } else {
                // 일반 알람이 _activeAlarms에 없더라도, 혹시 모르니 강제로 키를 재구성해서 삭제 시도
                // (키 생성 로직이 다를 수 있으므로)
                logMessage(
                  '⚠️ 해당 알람($alarmKey)이 Flutter에 없음 - 상태 정리 및 강제 UI 업데이트 수행',
                  level: LogLevel.warning,
                );

                // 상태 정리
                if (_alarmFacade.activeAlarmsMap.isEmpty && _alarmFacade.isTrackingMode) {
                  _alarmFacade.isTrackingMode = false;
                  _alarmFacade.trackedRouteId = null;
                  logMessage('🛑 추적 모드 비활성화 (상태 정리)', level: LogLevel.info);
                }

                // UI 강제 업데이트
                notifyListeners();
              }
            }
          }

          return true; // Acknowledge event received
        case 'onAllAlarmsCanceled':
          // 모든 알람 취소 이벤트 처리
          logMessage(
            '🛑🛑🛑 네이티브에서 모든 알람 취소 이벤트 수신 - 사용자가 "추적 중지" 버튼을 눌렀습니다!',
            level: LogLevel.warning,
          );

          // 🛑 사용자 수동 중지 플래그 설정 (30초간 자동 알람 재시작 방지)
          _alarmFacade.state.userManuallyStopped = true;
          _alarmFacade.state.lastManualStopTime = DateTime.now().millisecondsSinceEpoch;
          logMessage(
            '🛑 Flutter 측 수동 중지 플래그 설정 - 30초간 자동 알람 재시작 방지',
            level: LogLevel.warning,
          );

          // 🛑 실시간 버스 업데이트 타이머 중지 (중요!)
          try {
            _notificationService.stopRealTimeBusUpdates();
            logMessage('🛑 실시간 버스 업데이트 타이머 강제 중지 완료', level: LogLevel.info);
          } catch (e) {
            logMessage('❌ 실시간 버스 업데이트 타이머 중지 오류: $e', level: LogLevel.error);
          }

          // 모든 활성 알람 제거
          if (_alarmFacade.activeAlarmsMap.isNotEmpty) {
            // 모든 활성 알람을 수동 중지 목록에 추가
            final now = DateTime.now();
            for (var alarmKey in _alarmFacade.activeAlarmsMap.keys) {
              _alarmFacade.state.manuallyStoppedAlarms.add(alarmKey);
              _alarmFacade.state.manuallyStoppedTimestamps[alarmKey] = now;
            }
            logMessage(
              '🚫 모든 알람을 수동 중지 목록에 추가: ${_alarmFacade.activeAlarmsMap.length}개',
              level: LogLevel.info,
            );

            _alarmFacade.activeAlarmsMap.clear();
            _alarmFacade.clearCachedBusInfo();
            _alarmFacade.isTrackingMode = false;
            _alarmFacade.trackedRouteId = null;
            await _saveAlarms();
            logMessage('✅ 모든 알람 취소 완료 (네이티브 이벤트에 의해)', level: LogLevel.info);
            notifyListeners();
          }

          return true;
        case 'stopAutoAlarmFromBroadcast':
          // 자동알람 중지 브로드캐스트 수신 처리
          final Map<String, dynamic> args = Map<String, dynamic>.from(
            call.arguments,
          );
          final String busNo = args['busNo'] ?? '';
          final String stationName = args['stationName'] ?? '';
          final String routeId = args['routeId'] ?? '';

          logMessage(
            '🔔 네이티브에서 자동알람 중지 브로드캐스트 수신: $busNo, $stationName, $routeId',
            level: LogLevel.info,
          );

          // stopAutoAlarm 메서드 호출
          try {
            final result = await stopAutoAlarm(busNo, stationName, routeId);
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

        case 'onAutoAlarmStarted':
          final Map<String, dynamic> args = Map<String, dynamic>.from(call.arguments);
          final String busNo = args['busNo'] ?? '';
          final String routeId = args['routeId'] ?? '';
          final String stationName = args['stationName'] ?? '';
          final int timestamp = args['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;

          final now = DateTime.fromMillisecondsSinceEpoch(timestamp);
          final alarmKey = "${busNo}_${stationName}_$routeId";
          final executionKey = "${alarmKey}_${now.hour}:${now.minute}";

          _alarmFacade.state.executedAlarms[executionKey] = now;
          logMessage('✅ [네이티브] 자동 알람 시작 감지: $executionKey', level: LogLevel.info);
          return true;

        case 'onAutoAlarmStopped':
          final Map<String, dynamic> args = Map<String, dynamic>.from(call.arguments);
          final String busNo = args['busNo'] ?? '';
          final String stationName = args['stationName'] ?? '';
          final String routeId = args['routeId'] ?? '';

          if (busNo.isNotEmpty && stationName.isNotEmpty && routeId.isNotEmpty) {
            final alarmKey = "${busNo}_${stationName}_$routeId";
            _alarmFacade.state.manuallyStoppedAlarms.add(alarmKey);
            _alarmFacade.state.manuallyStoppedTimestamps[alarmKey] = DateTime.now();
            logMessage('🚫 [네이티브] 자동 알람 종료 감지 -> 수동 중지 목록 추가 (당일 재실행 방지): $alarmKey', level: LogLevel.info);
          } else {
            logMessage('⚠️ [네이티브] 자동 알람 종료 감지되었으나 정보 부족', level: LogLevel.warning);
          }
          return true;

        default:
          // Ensure other method calls are still handled if any exist
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
        _alarmFacade.checkAutoAlarms(); // 자동 알람 체크 추가 (5초마다 정밀 체크)

        // 디버깅: 현재 자동 알람 상태 출력 (30초마다)
        if (timer.tick % 2 == 0) {
          _logAutoAlarmStatus();
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
    _alarmFacade.cancelRefreshTimer();
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

  void clearManuallyStoppedAlarms() {
    _alarmFacade.state.manuallyStoppedAlarms.clear();
    _alarmFacade.state.manuallyStoppedTimestamps.clear();
    logMessage('🧹 수동 중지 알람 목록 초기화', level: LogLevel.info);
  }

  void cleanupExecutedAlarms() {
    final now = DateTime.now();
    final cutoffTime = now.subtract(const Duration(hours: 2)); // 2시간 이전 기록 삭제

    final keysToRemove = <String>[];
    _alarmFacade.state.executedAlarms.forEach((key, executionTime) {
      if (executionTime.isBefore(cutoffTime)) {
        keysToRemove.add(key);
      }
    });

    for (var key in keysToRemove) {
      _alarmFacade.state.executedAlarms.remove(key);
    }

    if (keysToRemove.isNotEmpty) {
      logMessage(
        '🧹 실행 기록 정리: ${keysToRemove.length}개 제거',
        level: LogLevel.debug,
      );
    }
  }

  // 디버깅용: 자동 알람 상태 로그 출력
  void _logAutoAlarmStatus() {
    try {
      // 실행 기록 정리 (주기적으로)
      cleanupExecutedAlarms();

      final now = DateTime.now();
      final weekdays = ['일', '월', '화', '수', '목', '금', '토'];
      logMessage(
        '🕒 [자동알람 상태] 현재 시간: ${now.toString()} (${weekdays[now.weekday % 7]})',
      );
      logMessage('🕒 [자동알람 상태] 활성 자동 알람: ${_alarmFacade.autoAlarmsList.length}개');
      logMessage(
        '🕒 [자동알람 상태] 자동 알람 활성화: ${_alarmFacade.state.autoAlarmEnabled}',
      );
      logMessage('🕒 [자동알람 상태] 수동 중지된 알람: ${_alarmFacade.state.manuallyStoppedAlarms.length}개');
      logMessage('🕒 [자동알람 상태] 실행 기록: ${_alarmFacade.state.executedAlarms.length}개');

      for (var alarm in _alarmFacade.autoAlarmsList) {
        final timeUntilAlarm = alarm.scheduledTime.difference(now);
        final repeatDaysStr =
            alarm.repeatDays?.map((day) => weekdays[day % 7]).join(', ') ??
                '없음';
        logMessage(
          '  - ${alarm.busNo}번 (${alarm.stationName}): 예정 시간 ${alarm.scheduledTime.toString()}, ${timeUntilAlarm.inMinutes}분 후, 반복: $repeatDaysStr',
        );
      }

      if (_alarmFacade.autoAlarmsList.isEmpty) {
        logMessage('  - 설정된 자동 알람이 없습니다.');
      }

      if (_alarmFacade.state.manuallyStoppedAlarms.isNotEmpty) {
        logMessage('  - 수동 중지된 알람:');
        for (var alarmKey in _alarmFacade.state.manuallyStoppedAlarms) {
          final stoppedTime = _alarmFacade.state.manuallyStoppedTimestamps[alarmKey];
          if (stoppedTime != null) {
            final stoppedDate = DateTime(
              stoppedTime.year,
              stoppedTime.month,
              stoppedTime.day,
            );
            final currentDate = DateTime(now.year, now.month, now.day);
            final isToday = stoppedDate.isAtSameMomentAs(currentDate);
            logMessage(
              '    • $alarmKey (중지일: ${stoppedTime.month}/${stoppedTime.day}, ${isToday ? "오늘" : "과거"})',
            );
          }
        }
      }
    } catch (e) {
      logMessage('❌ 자동 알람 상태 로그 오류: $e', level: LogLevel.error);
    }
  }

  Future<void> loadAlarms() async {
    try {
      // 백그라운드 메신저 상태 확인 및 초기화
      if (!kIsWeb) {
        try {
          final rootIsolateToken = RootIsolateToken.instance;
          if (rootIsolateToken != null) {
            BackgroundIsolateBinaryMessenger.ensureInitialized(
              rootIsolateToken,
            );
            logMessage('✅ BackgroundIsolateBinaryMessenger 초기화 성공');
          } else {
            logMessage(
              '⚠️ RootIsolateToken이 null입니다. 메인 스레드에서 실행 중인지 확인하세요.',
              level: LogLevel.warning,
            );
          }
        } catch (e) {
          logMessage(
            '⚠️ BackgroundIsolateBinaryMessenger 초기화 오류 (무시): $e',
            level: LogLevel.warning,
          );
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final alarms = prefs.getStringList('alarms') ?? [];
      _alarmFacade.activeAlarmsMap.clear();

      for (var json in alarms) {
        try {
          final data = jsonDecode(json);
          final alarm = alarm_model.AlarmData.fromJson(data);
          if (_isAlarmValid(alarm)) {
            final key = "${alarm.busNo}_${alarm.stationName}_${alarm.routeId}";
            _alarmFacade.activeAlarmsMap[key] = alarm;
          }
        } catch (e) {
          logMessage('알람 데이터 파싱 오류: $e', level: LogLevel.error);
        }
      }

      logMessage('✅ 알람 로드 완료: ${_alarmFacade.activeAlarmsMap.length}개');
      notifyListeners();
    } catch (e) {
      logMessage('알람 로드 중 오류 발생: $e', level: LogLevel.error);
    }
  }

  bool _isAlarmValid(alarm_model.AlarmData alarm) {
    final now = DateTime.now();
    final difference = alarm.scheduledTime.difference(now);
    return difference.inMinutes > -5; // 5분 이상 지난 알람은 제외
  }

  Future<void> loadAutoAlarms() async {
    try {
      // 백그라운드 메신저 상태 확인 및 초기화
      if (!kIsWeb) {
        try {
          final rootIsolateToken = RootIsolateToken.instance;
          if (rootIsolateToken != null) {
            BackgroundIsolateBinaryMessenger.ensureInitialized(
              rootIsolateToken,
            );
            logMessage('✅ 자동 알람용 BackgroundIsolateBinaryMessenger 초기화 성공');
          } else {
            logMessage(
              '⚠️ 자동 알람 - RootIsolateToken이 null입니다',
              level: LogLevel.warning,
            );
          }
        } catch (e) {
          logMessage(
            '⚠️ 자동 알람 BackgroundIsolateBinaryMessenger 초기화 오류 (무시): $e',
            level: LogLevel.warning,
          );
        }
      }

      final prefs = await SharedPreferences.getInstance();
      final alarms = prefs.getStringList('auto_alarms') ?? [];
      logMessage('자동 알람 데이터 로드 시작: ${alarms.length}개');

      _alarmFacade.autoAlarmsList.clear();

      for (var alarmJson in alarms) {
        try {
          final Map<String, dynamic> data = jsonDecode(alarmJson);

          // scheduledTime이 문자열이면 DateTime으로 변환
          if (data['scheduledTime'] is String) {
            data['scheduledTime'] = DateTime.parse(data['scheduledTime']);
          }

          // stationId가 없는 경우, stationName과 routeId로 찾아옴
          if (data['stationId'] == null || data['stationId'].isEmpty) {
            data['stationId'] = _getStationIdFromName(
              data['stationName'],
              data['routeId'],
            );
          }

          // 필수 필드 검증
          if (!_validateRequiredFields(data)) {
            logMessage('⚠️ 자동 알람 데이터 필수 필드 누락: $data', level: LogLevel.warning);
            continue;
          }

          // AutoAlarm 객체 생성하여 올바른 다음 알람 시간 계산
          final autoAlarm = AutoAlarm.fromJson(data);

          // 다음 알람 시간 계산
          final nextAlarmTime = autoAlarm.getNextAlarmTime();
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
            repeatDays: autoAlarm.repeatDays,
          );

          _alarmFacade.autoAlarmsList.add(alarm);
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

  bool _validateRequiredFields(Map<String, dynamic> data) {
    final requiredFields = [
      'routeNo',
      'stationId',
      'routeId',
      'stationName',
      'repeatDays',
    ];
    // scheduledTime 또는 hour/minute 중 하나는 필수
    if (data['scheduledTime'] == null &&
        (data['hour'] == null || data['minute'] == null)) {
      logMessage(
        '! 자동 알람 데이터 필수 필드 누락: scheduledTime 또는 hour/minute',
        level: LogLevel.error,
      );
      return false;
    }

    final missingFields = requiredFields
        .where(
          (field) =>
              data[field] == null ||
              (data[field] is String && data[field].isEmpty) ||
              (data[field] is List && (data[field] as List).isEmpty),
        )
        .toList();
    if (missingFields.isNotEmpty) {
      logMessage(
        '! 자동 알람 데이터 필수 필드 누락: [31m${missingFields.join(", ")}[0m',
        level: LogLevel.error,
      );
      return false;
    }
    return true;
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
  }) async {
    try {
      // TTS 발화
      if (_useTTS) {
        await SimpleTTSHelper.speakBusAlert(
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          earphoneOnly: !isAutoAlarm, // 일반 알람은 이어폰 전용, 자동 알람은 스피커 허용
          isAutoAlarm: isAutoAlarm, // 🔊 자동 알람 플래그 전달
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
  Future<bool> stopAutoAlarm(
    String busNo,
    String stationName,
    String routeId,
  ) async {
    try {
      logMessage('📋 자동 알람 중지 요청: $busNo번, $stationName', level: LogLevel.info);

      // 수동 중지 알람 목록에 추가 (재시작 방지)
      final alarmKey = "${busNo}_${stationName}_$routeId";
      _alarmFacade.state.manuallyStoppedAlarms.add(alarmKey);
      _alarmFacade.state.manuallyStoppedTimestamps[alarmKey] = DateTime.now();
      logMessage('🚫 수동 중지 알람 추가: $alarmKey', level: LogLevel.info);

      // 새로고침 타이머 중지
      _alarmFacade.cancelRefreshTimer();

      // 버스 모니터링 서비스 중지
      await _notificationService.cancelOngoingTracking();

      // 알림 취소
      await _notificationService.cancelOngoingTracking();

      // 자동 알람 목록에서 제거
      _alarmFacade.autoAlarmsList.removeWhere(
        (alarm) =>
            alarm.busNo == busNo &&
            alarm.stationName == stationName &&
            alarm.routeId == routeId,
      );

      // activeAlarms에서도 제거
      _alarmFacade.activeAlarmsMap.remove(alarmKey);

      await _alarmFacade.saveAutoAlarms();
      await _saveAlarms();

      // TTS 중지 알림 제거 (사용자 요청)
      // try {
      //   await SimpleTTSHelper.speak(
      //     "$busNo번 버스 자동 알람이 중지되었습니다.",
      //     force: true,
      //     earphoneOnly: false,
      //   );
      // } catch (e) {
      //   logMessage('❌ TTS 중지 알림 오류: $e', level: LogLevel.error);
      // }

      logMessage('✅ 자동 알람 중지 완료: $busNo번', level: LogLevel.info);

      notifyListeners();
      return true;
    } catch (e) {
      logMessage('❌ 자동 알람 중지 오류: $e', level: LogLevel.error);
      return false;
    }
  }

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

      final id = "${busNo}_${stationName}_$routeId";

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
      );

      // 알람 저장 (키는 알람의 고유 ID 문자열 사용)
      _alarmFacade.activeAlarmsMap[alarmData.id] = alarmData;
      await _saveAlarms();

      // 설정된 알람 볼륨 가져오기
      final settingsService = SettingsService();
      await settingsService.initialize();
      final volume = settingsService.autoAlarmVolume;

      // TTS 알림 시작 (승차알람은 항상 TTS 발화 - 사용자가 직접 버튼 클릭)
      // isImmediateAlarm이 true이면 무조건 TTS 발화
      if (isImmediateAlarm || useTTS) {
        try {
          await SimpleTTSHelper.initialize();
          await SimpleTTSHelper.setVolume(volume); // 볼륨 설정

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
              '✅ 일반 알람 TTS 발화 완료 (볼륨: ${volume * 100}%, 모드: ${settingsService.getSpeakerModeName(speakerMode)})',
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
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> alarms = _alarmFacade.activeAlarmsMap.values
          .map((alarm) => jsonEncode(alarm.toJson()))
          .toList();
      await prefs.setStringList('alarms', alarms);
      logMessage('✅ 알람 저장 완료: ${alarms.length}개');
    } catch (e) {
      logMessage('❌ 알람 저장 오류: $e', level: LogLevel.error);
    }
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

      // 5. 타이머 정리
      _alarmFacade.cancelRefreshTimer();

      // 6. 상태 저장 및 UI 업데이트
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

    final String alarmKey = "${busNo}_${stationName}_$routeId";
    final String cacheKey = "${busNo}_$routeId";
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

      // 자동 알람 목록에서도 제거
      final autoAlarmIndex = _alarmFacade.autoAlarmsList.indexWhere(
        (alarm) =>
            alarm.busNo == busNo &&
            alarm.stationName == stationName &&
            alarm.routeId == routeId,
      );
      if (autoAlarmIndex != -1) {
        _alarmFacade.autoAlarmsList.removeAt(autoAlarmIndex);
        logMessage(
          '[$busNo] Flutter autoAlarms 목록에서 완전 제거',
          level: LogLevel.debug,
        );
      }

      _alarmFacade.removeCachedBusInfoByKey(cacheKey);
      logMessage('[$cacheKey] 버스 정보 캐시 즉시 제거', level: LogLevel.debug);

      // Check if the route being cancelled is the one being tracked OR if it's the last alarm
      if (_alarmFacade.trackedRouteId == routeId) {
        _alarmFacade.trackedRouteId = null;
        logMessage('추적 Route ID 즉시 초기화됨 (취소된 알람과 일치)', level: LogLevel.debug);
        if (_alarmFacade.activeAlarmsMap.isEmpty && _alarmFacade.autoAlarmsList.isEmpty) {
          // 모든 알람이 없는 경우
          _alarmFacade.isTrackingMode = false;
          shouldForceStopNative = true; // Last tracked alarm removed
          logMessage('추적 모드 즉시 비활성화 (모든 알람 없음)', level: LogLevel.debug);
        } else {
          _alarmFacade.isTrackingMode = true;
          logMessage('다른 활성 알람 존재, 추적 모드 유지', level: LogLevel.debug);
          // Decide if we need to start tracking the next alarm? For now, no.
        }
      } else if (_alarmFacade.activeAlarmsMap.isEmpty && _alarmFacade.autoAlarmsList.isEmpty) {
        // 모든 알람이 없는 경우
        // If the cancelled alarm wasn't the tracked one, but it was the *last* one
        _alarmFacade.isTrackingMode = false;
        _alarmFacade.trackedRouteId = null;
        shouldForceStopNative = true; // Last alarm overall removed
        logMessage('마지막 알람 취소됨, 추적 모드 비활성화', level: LogLevel.debug);
      }

      await _saveAlarms(); // Persist the removal immediately
      await _alarmFacade.saveAutoAlarms(); // 자동 알람 상태도 저장
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
        effectiveStationId = _getStationIdFromName(
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
          try {
            // ✅ 응답 파싱 로직 개선
            dynamic parsedData;
            List<dynamic> arrivals = [];

            // 응답 타입별 처리
            if (result is String) {
              logMessage('🚌 [API 파싱] String 형식 응답 처리', level: LogLevel.debug);
              try {
                parsedData = jsonDecode(result);
              } catch (e) {
                logMessage('❌ JSON 파싱 오류: $e', level: LogLevel.error);
                return false;
              }
            } else if (result is List) {
              logMessage('🚌 [API 파싱] List 형식 응답 처리', level: LogLevel.debug);
              parsedData = result;
            } else if (result is Map) {
              logMessage('🚌 [API 파싱] Map 형식 응답 처리', level: LogLevel.debug);
              parsedData = result;
            } else {
              logMessage(
                '❌ 지원되지 않는 응답 타입: ${result.runtimeType}',
                level: LogLevel.error,
              );
              return false;
            }

            // ✅ parsedData 구조 분석 및 arrivals 추출
            if (parsedData is List) {
              arrivals = parsedData;
            } else if (parsedData is Map) {
              // 자동 알람 응답 형식: { "routeNo": "623", "arrList": [...] }
              if (parsedData.containsKey('arrList')) {
                arrivals = parsedData['arrList'] as List? ?? [];
                logMessage(
                  '🚌 [API 파싱] arrList에서 도착 정보 추출: ${arrivals.length}개',
                  level: LogLevel.debug,
                );
              } else if (parsedData.containsKey('bus')) {
                arrivals = parsedData['bus'] as List? ?? [];
                logMessage(
                  '🚌 [API 파싱] bus에서 도착 정보 추출: ${arrivals.length}개',
                  level: LogLevel.debug,
                );
              } else {
                logMessage(
                  '❌ 예상치 못한 Map 구조: ${parsedData.keys}',
                  level: LogLevel.error,
                );
                return false;
              }
            }

            logMessage(
              '🚌 [API 파싱] 파싱된 arrivals: ${arrivals.length}개 항목',
              level: LogLevel.debug,
            );

            if (arrivals.isNotEmpty) {
              // ✅ 버스 정보 추출 및 필터링
              dynamic busInfo;
              bool found = false;

              // 알람에 설정된 노선 번호와 일치하는 버스 찾기
              for (var bus in arrivals) {
                if (bus is Map) {
                  final busRouteNo = bus['routeNo']?.toString() ?? '';
                  final busRouteId = bus['routeId']?.toString() ?? '';
                  // routeNo 또는 routeId로 매칭
                  if (busRouteNo == alarm.routeNo ||
                      busRouteId == alarm.routeId) {
                    busInfo = bus;
                    found = true;
                    logMessage(
                      '✅ 일치하는 노선 찾음: ${alarm.routeNo} (routeNo: $busRouteNo, routeId: $busRouteId)',
                      level: LogLevel.debug,
                    );
                    break;
                  }
                }
              }

              // 일치하는 노선이 없으면 첫 번째 항목 사용
              if (!found && arrivals.isNotEmpty) {
                busInfo = arrivals.first;
                final routeNo = busInfo['routeNo']?.toString() ?? '정보 없음';
                logMessage(
                  '⚠️ 일치하는 노선 없음, 첫 번째 항목 사용: $routeNo',
                  level: LogLevel.warning,
                );
              }

              if (busInfo != null) {
                // ✅ 도착 정보 추출 - 다양한 필드명 지원
                final estimatedTime = busInfo['arrState'] ??
                    busInfo['estimatedTime'] ??
                    busInfo['도착예정소요시간'] ??
                    "정보 없음";

                final currentStation = busInfo['bsNm'] ??
                    busInfo['currentStation'] ??
                    busInfo['현재정류소'] ??
                    '정보 없음';

                final int remainingMinutes = _parseRemainingMinutes(
                  estimatedTime,
                );

                logMessage(
                  '🚌 [정보 추출] estimatedTime: $estimatedTime, currentStation: $currentStation, remainingMinutes: $remainingMinutes',
                  level: LogLevel.debug,
                );

                // ✅ 캐시에 저장
                final cachedInfo = CachedBusInfo(
                  remainingMinutes: remainingMinutes,
                  currentStation: currentStation,
                  stationName: alarm.stationName,
                  busNo: alarm.routeNo,
                  routeId: alarm.routeId,
                  lastUpdated: DateTime.now(),
                );

                _alarmFacade.updateCachedBusInfo(cachedInfo);

                logMessage(
                  '✅ 자동 알람 버스 정보 업데이트 완료: ${alarm.routeNo}번, $remainingMinutes분 후 도착, 위치: $currentStation',
                  level: LogLevel.info,
                );

                // ✅ 알림 업데이트

                // 자동 알람에서 Flutter 알림 제거 - BusAlertService가 모든 알림 처리
                logMessage(
                  '✅ 자동 알람 정보 업데이트: ${alarm.routeNo}번, $remainingMinutes분 후, $currentStation',
                  level: LogLevel.debug,
                );

                // ✅ 버스 모니터링 서비스 시작 (10분 이내일 때)
                if (remainingMinutes <= 10 && remainingMinutes >= 0) {
                  try {
                    await startBusMonitoringService(
                      routeId: alarm.routeId,
                      stationId: effectiveStationId,
                      busNo: alarm.routeNo,
                      stationName: alarm.stationName,
                    );
                    logMessage(
                      '✅ 자동 알람 버스 모니터링 시작: ${alarm.routeNo}번 ($remainingMinutes분 후 도착)',
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
              logMessage('⚠️ 도착 정보 없음', level: LogLevel.warning);
            }
          } catch (e) {
            logMessage('❌ 버스 정보 파싱 오류: $e', level: LogLevel.error);
            logMessage('원본 응답: $result', level: LogLevel.debug);
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

  // ✅ 문자열 형태의 도착 시간을 분 단위 정수로 변환하는 메서드 개선
  int _parseRemainingMinutes(dynamic estimatedTime) {
    if (estimatedTime == null) return -1;

    final String timeStr = estimatedTime.toString().trim();

    // 곧 도착 관련
    if (timeStr == '곧 도착' || timeStr == '전' || timeStr == '도착') return 0;

    // 운행 종료 관련
    if (timeStr == '운행종료' ||
        timeStr == '운행 종료' ||
        timeStr == '-' ||
        timeStr == '운행종료.') return -1;

    // 출발 예정 관련
    if (timeStr.contains('출발예정') || timeStr.contains('기점출발')) return -1;

    // 숫자 + '분' 형태 처리
    if (timeStr.contains('분')) {
      final numericValue = timeStr.replaceAll(RegExp(r'[^0-9]'), '');
      return numericValue.isEmpty ? -1 : int.tryParse(numericValue) ?? -1;
    }

    // 순수 숫자인 경우
    final numericValue = timeStr.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericValue.isNotEmpty) {
      final minutes = int.tryParse(numericValue);
      if (minutes != null && minutes >= 0 && minutes <= 180) {
        // 3시간 이내만 유효
        return minutes;
      }
    }

    logMessage('⚠️ 파싱할 수 없는 도착 시간 형식: "$timeStr"', level: LogLevel.warning);
    return -1;
  }

  /// 정류장 이름으로 stationId 매핑
  String _getStationIdFromName(String stationName, String fallbackRouteId) {
    // 알려진 정류장 이름과 stationId 매핑
    final Map<String, String> stationMapping = {
      '새동네아파트앞': '7021024000',
      '새동네아파트건너': '7021023900',
      '칠성고가도로하단': '7021051300',
      '대구삼성창조캠퍼스3': '7021011000',
      '대구삼성창조캠퍼스': '7021011200',
      '동대구역': '7021052100',
      '동대구역건너': '7021052000',
      '경명여고건너': '7021024200',
      '경명여고': '7021024100',
    };

    // 정확한 매칭 시도
    if (stationMapping.containsKey(stationName)) {
      return stationMapping[stationName]!;
    }

    // 부분 매칭 시도
    for (var entry in stationMapping.entries) {
      if (stationName.contains(entry.key) || entry.key.contains(stationName)) {
        return entry.value;
      }
    }

    // 매칭 실패 시 fallback 사용
    return fallbackRouteId;
  }

  Future<void> updateAutoAlarms(List<AutoAlarm> autoAlarms) async {
    try {
      // 백그라운드 메신저 상태 확인 및 초기화
      if (!kIsWeb) {
        try {
          final rootIsolateToken = RootIsolateToken.instance;
          if (rootIsolateToken != null) {
            BackgroundIsolateBinaryMessenger.ensureInitialized(
              rootIsolateToken,
            );
          }
        } catch (e) {
          logMessage(
            '⚠️ updateAutoAlarms - BackgroundIsolateBinaryMessenger 초기화 오류 (무시): $e',
            level: LogLevel.warning,
          );
        }
      }

      logMessage('🔄 자동 알람 업데이트 시작: ${autoAlarms.length}개');
      _alarmFacade.autoAlarmsList.clear();

      for (var alarm in autoAlarms) {
        logMessage('📝 알람 처리 중: ${alarm.routeNo}번, ${alarm.stationName}');

        if (!alarm.isActive) {
          logMessage('  ⚠️ 비활성화된 알람 건너뛰기');
          continue;
        }

        final DateTime? scheduledTime = alarm.getNextAlarmTime();

        if (scheduledTime == null) {
          logMessage(
            '  ⚠️ 유효한 다음 알람 시간을 찾지 못함: ${alarm.routeNo}',
            level: LogLevel.warning,
          );
          continue;
        }

        final now = DateTime.now();
        final timeUntilAlarm = scheduledTime.difference(now);
        logMessage('  ⏰ 다음 알람까지 ${timeUntilAlarm.inMinutes}분 남음');

        if (timeUntilAlarm.inSeconds <= 30 &&
            timeUntilAlarm.inSeconds >= -300) {
          logMessage('  ⚡ 알람 시간이 지났음 - 즉시 실행 (${timeUntilAlarm.inSeconds}초)');
          await _alarmFacade.executeAutoAlarmImmediately(alarm);
        }

        final alarmData = alarm_model.AlarmData(
          id: alarm.id,
          busNo: alarm.routeNo,
          stationName: alarm.stationName,
          remainingMinutes: 0,
          routeId: alarm.routeId,
          scheduledTime: scheduledTime,
          useTTS: alarm.useTTS,
          isAutoAlarm: true,
          repeatDays: alarm.repeatDays, // 반복 요일 정보 포함
        );
        _alarmFacade.autoAlarmsList.add(alarmData);
        logMessage('  ✅ 알람 데이터 생성 완료');

        await _alarmFacade.scheduleAutoAlarm(alarm, scheduledTime);
      }

      await _alarmFacade.saveAutoAlarms();
      logMessage('✅ 자동 알람 업데이트 완료: ${_alarmFacade.autoAlarmsList.length}개');
    } catch (e) {
      logMessage('❌ 자동 알람 업데이트 오류: $e', level: LogLevel.error);
      logMessage('  - 스택 트레이스: ${e is Error ? e.stackTrace : "없음"}');
    }
  }
}
