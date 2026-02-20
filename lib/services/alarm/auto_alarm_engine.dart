import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show logMessage, LogLevel;
import '../../models/auto_alarm.dart';
import '../../models/alarm_data.dart' as alarm_model;
import '../../utils/database_helper.dart';
import '../../utils/simple_tts_helper.dart';
import '../settings_service.dart';
import 'alarm_state.dart';

class AutoAlarmEngine {
  AutoAlarmEngine({
    required AlarmState state,
    required Future<bool> Function({
      required String stationId,
      required String stationName,
      required String routeId,
      required String busNo,
    }) startMonitoring,
    required Future<bool> Function(AutoAlarm alarm) refreshBusInfo,
    required Future<void> Function() saveAlarms,
    required String Function(String stationName, String routeId) resolveStationId,
    required Future<List<DateTime>> Function(int year, int month) getHolidays,
    required int restartPreventionDurationMs,
  })  : _state = state,
        _startMonitoring = startMonitoring,
        _refreshBusInfo = refreshBusInfo,
        _saveAlarms = saveAlarms,
        _resolveStationId = resolveStationId,
        _getHolidays = getHolidays,
        _restartPreventionDurationMs = restartPreventionDurationMs;

  final AlarmState _state;
  final Future<bool> Function({
    required String stationId,
    required String stationName,
    required String routeId,
    required String busNo,
  }) _startMonitoring;
  final Future<bool> Function(AutoAlarm alarm) _refreshBusInfo;
  final Future<void> Function() _saveAlarms;
  final String Function(String stationName, String routeId) _resolveStationId;
  final Future<List<DateTime>> Function(int year, int month) _getHolidays;
  final int _restartPreventionDurationMs;

  Timer? refreshTimer;

  void cancelRefreshTimer() {
    refreshTimer?.cancel();
    refreshTimer = null;
  }

  Future<void> saveAutoAlarms() async {
    await _saveAutoAlarms();
  }

  Future<void> checkAutoAlarms() async {
    try {
      final settingsService = SettingsService();
      if (!settingsService.useAutoAlarm || !_state.autoAlarmEnabled) {
        logMessage(
          '⚠️ 자동 알람이 설정에서 비활성화되어 있거나 수동으로 중지되었습니다.',
          level: LogLevel.warning,
        );
        return;
      }

      final now = DateTime.now();
      final alarmsCopy = List<alarm_model.AlarmData>.from(_state.autoAlarms);

      for (var alarm in alarmsCopy) {
        final alarmTime = alarm.scheduledTime;
        final timeDifference = alarmTime.difference(now);

        final isTargetTime =
            now.hour == alarmTime.hour && now.minute == alarmTime.minute;
        final isWithinMinute =
            timeDifference.inSeconds >= -59 && timeDifference.inSeconds <= 0;

        logMessage(
          '🕒 알람 시간 체크: ${alarm.busNo}번 - 현재: ${now.hour}:${now.minute}:${now.second}, 알람: ${alarmTime.hour}:${alarmTime.minute}, 차이: ${timeDifference.inSeconds}초',
          level: LogLevel.debug,
        );

        if (!isTargetTime || !isWithinMinute) {
          continue;
        }

        final alarmKey = "${alarm.busNo}_${alarm.stationName}_${alarm.routeId}";
        final executionKey = "${alarmKey}_${alarmTime.hour}:${alarmTime.minute}";
        if (_state.executedAlarms.containsKey(executionKey)) {
          final lastExecution = _state.executedAlarms[executionKey]!;
          final sameMinute =
              lastExecution.hour == now.hour && lastExecution.minute == now.minute;
          if (sameMinute) {
            logMessage(
              '⏭️ 알람 중복 실행 방지: ${alarm.busNo}번 - 이미 ${lastExecution.hour}:${lastExecution.minute}에 실행됨',
              level: LogLevel.warning,
            );
            continue;
          }
        }

        logMessage(
          '✅ 알람 실행 조건 만족: ${alarm.busNo}번 - 시간: ${alarmTime.hour}:${alarmTime.minute}, 차이: ${timeDifference.inSeconds}초',
          level: LogLevel.info,
        );

        if (_state.manuallyStoppedAlarms.contains(alarmKey)) {
          final stoppedTime = _state.manuallyStoppedTimestamps[alarmKey];
          if (stoppedTime != null) {
            final stoppedDate =
                DateTime(stoppedTime.year, stoppedTime.month, stoppedTime.day);
            final currentDate = DateTime(now.year, now.month, now.day);

            if (currentDate.isAfter(stoppedDate)) {
              _state.manuallyStoppedAlarms.remove(alarmKey);
              _state.manuallyStoppedTimestamps.remove(alarmKey);
              logMessage(
                '✅ 수동 중지 알람 자동 해제 (다음날 도래): ${alarm.busNo}번, ${alarm.stationName}',
                level: LogLevel.info,
              );
            } else {
              logMessage(
                '⚠️ 자동 알람 스킵 (오늘 수동으로 중지됨): ${alarm.busNo}번, ${alarm.stationName}',
                level: LogLevel.warning,
              );
              continue;
            }
          } else {
            _state.manuallyStoppedAlarms.remove(alarmKey);
          }
        }

        if (_state.activeAlarms.containsKey(alarmKey)) {
          logMessage(
            '⚠️ 자동 알람 스킵 (이미 추적 중): ${alarm.busNo}번, ${alarm.stationName}',
            level: LogLevel.warning,
          );
          continue;
        }

        logMessage(
          '⚡ 자동 알람 실행: ${alarm.busNo}번, 예정 시간: ${alarmTime.toString()}, 현재 시간: ${now.toString()}',
          level: LogLevel.info,
        );

        String effectiveStationId =
            _resolveStationId(alarm.stationName, alarm.routeId);

        try {
          final dbHelper = DatabaseHelper();
          final resolvedStationId =
              await dbHelper.getStationIdFromWincId(alarm.stationName);
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

        final autoAlarm = AutoAlarm(
          id: alarm.id.toString(),
          routeNo: alarm.busNo,
          stationName: alarm.stationName,
          stationId: effectiveStationId,
          routeId: alarm.routeId,
          hour: alarmTime.hour,
          minute: alarmTime.minute,
          repeatDays: (alarm.repeatDays?.isNotEmpty ?? false)
              ? alarm.repeatDays!
              : [now.weekday],
          useTTS: alarm.useTTS,
          isActive: true,
        );

        _state.executedAlarms[executionKey] = now;

        await startContinuousAutoAlarm(autoAlarm);

        _state.autoAlarms.removeWhere((a) => a.id == alarm.id);

        final currentMonthHolidays = await _getHolidays(now.year, now.month);
        final nextTargetMonth = now.month == 12 ? 1 : now.month + 1;
        final nextTargetYear = now.month == 12 ? now.year + 1 : now.year;
        final nextMonthHolidays = await _getHolidays(nextTargetYear, nextTargetMonth);
        final customExcludeDates = SettingsService().customExcludeDates;
        final allHolidays = [...currentMonthHolidays, ...nextMonthHolidays, ...customExcludeDates];

        final nextAlarmTime = autoAlarm.getNextAlarmTime(holidays: allHolidays);
        if (nextAlarmTime != null) {
          final nextAlarm = alarm_model.AlarmData(
            id: alarm.id,
            busNo: alarm.busNo,
            stationName: alarm.stationName,
            remainingMinutes: 0,
            routeId: alarm.routeId,
            scheduledTime: nextAlarmTime,
            useTTS: alarm.useTTS,
            isAutoAlarm: true,
            repeatDays: alarm.repeatDays ?? [],
          );
          _state.autoAlarms.add(nextAlarm);
          logMessage(
            '✅ 다음 자동 알람 스케줄링: ${alarm.busNo}번, 다음 시간: ${nextAlarmTime.toString()}',
          );
        }

        await _saveAutoAlarms();
        logMessage('✅ 자동 알람 실행 완료: ${alarm.busNo}번', level: LogLevel.info);
      }
    } catch (e) {
      logMessage('❌ 자동 알람 체크 오류: $e', level: LogLevel.error);
    }
  }

  Future<void> startContinuousAutoAlarm(AutoAlarm alarm) async {
    try {
      logMessage(
        '⚡ 지속적인 자동 알람 시작: ${alarm.routeNo}번, ${alarm.stationName}',
        level: LogLevel.info,
      );

      await _startMonitoring(
        routeId: alarm.routeId,
        stationId: alarm.stationId,
        busNo: alarm.routeNo,
        stationName: alarm.stationName,
      );

      refreshTimer?.cancel();
      refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
        if (!_state.isInTrackingMode) {
          timer.cancel();
          return;
        }

        try {
          await _refreshBusInfo(alarm);

          final cacheKey = "${alarm.routeNo}_${alarm.routeId}";
          final cachedInfo = _state.cachedBusInfo[cacheKey];

          final remainingMinutes = cachedInfo?.remainingMinutes ?? 0;
          final currentStation = cachedInfo?.currentStation ?? '정보 업데이트 중';

          logMessage(
            '🔄 자동 알람 업데이트: ${alarm.routeNo}번, $remainingMinutes분 후, 현재: $currentStation',
            level: LogLevel.info,
          );

          if (timer.tick % 2 == 0) {
            if (alarm.useTTS) {
              try {
                await SimpleTTSHelper.speakBusAlert(
                  busNo: alarm.routeNo,
                  stationName: alarm.stationName,
                  remainingMinutes: remainingMinutes,
                  currentStation: currentStation,
                  isAutoAlarm: true,
                );

                logMessage(
                  '🔊 자동 알람 TTS 반복 발화: ${alarm.routeNo}번, $remainingMinutes분 후',
                  level: LogLevel.info,
                );
              } catch (e) {
                logMessage(
                  '❌ 자동 알람 TTS 반복 발화 오류: $e',
                  level: LogLevel.error,
                );
              }
            }
          }
        } catch (e) {
          logMessage('❌ 자동 알람 업데이트 오류: $e', level: LogLevel.error);
        }
      });

      await executeAutoAlarmImmediately(alarm);

      logMessage('✅ 지속적인 자동 알람 시작 완료: ${alarm.routeNo}번',
          level: LogLevel.info);
    } catch (e) {
      logMessage('❌ 지속적인 자동 알람 시작 오류: $e', level: LogLevel.error);
    }
  }

  Future<void> executeAutoAlarmImmediately(AutoAlarm alarm) async {
    try {
      if (_state.userManuallyStopped) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final timeSinceStop = now - _state.lastManualStopTime;
        if (timeSinceStop < _restartPreventionDurationMs) {
          logMessage(
            '🛑 사용자가 ${(timeSinceStop / 1000).toInt()}초 전에 수동 중지했음 - 자동 알람 실행 거부: ${alarm.routeNo}번',
            level: LogLevel.warning,
          );
          return;
        } else {
          _state.userManuallyStopped = false;
          _state.lastManualStopTime = 0;
          logMessage(
            '✅ Flutter 재시작 방지 기간 만료 - 자동 알람 실행 허용: ${alarm.routeNo}번',
            level: LogLevel.info,
          );
        }
      }

      final settingsService = SettingsService();
      if (!settingsService.useAutoAlarm) {
        logMessage(
          '⚠️ 자동 알람이 설정에서 비활성화되어 있어 실행하지 않습니다: ${alarm.routeNo}번',
          level: LogLevel.warning,
        );
        return;
      }

      logMessage(
        '⚡ 즉시 자동 알람 실행: ${alarm.routeNo}번, ${alarm.stationName}',
        level: LogLevel.info,
      );

      await _refreshBusInfo(alarm);

      final cacheKey = "${alarm.routeNo}_${alarm.routeId}";
      final cachedInfo = _state.cachedBusInfo[cacheKey];

      final remainingMinutes = cachedInfo?.remainingMinutes ?? 0;
      final currentStation = cachedInfo?.currentStation ?? '정보 업데이트 중';

      final alarmData = alarm_model.AlarmData(
        id: alarm.id,
        busNo: alarm.routeNo,
        stationName: alarm.stationName,
        remainingMinutes: remainingMinutes,
        routeId: alarm.routeId,
        scheduledTime: DateTime.now().add(
          Duration(minutes: remainingMinutes.clamp(0, 60)),
        ),
        currentStation: currentStation,
        useTTS: alarm.useTTS,
        isAutoAlarm: true,
      );

      final alarmKey = "${alarm.routeNo}_${alarm.stationName}_${alarm.routeId}";
      _state.activeAlarms[alarmKey] = alarmData;
      await _saveAlarms();

      logMessage(
        '✅ 자동 알람을 activeAlarms에 추가: ${alarm.routeNo}번 ($remainingMinutes분 후)',
        level: LogLevel.info,
      );

      if (alarm.useTTS) {
        try {
          await SimpleTTSHelper.speakBusAlert(
            busNo: alarm.routeNo,
            stationName: alarm.stationName,
            remainingMinutes: remainingMinutes,
            currentStation: currentStation,
            isAutoAlarm: true,
          );
          logMessage('🔊 즉시 자동 알람 TTS 발화 완료 (강제 스피커 모드)',
              level: LogLevel.info);
        } catch (e) {
          logMessage('❌ 즉시 자동 알람 TTS 발화 오류: $e', level: LogLevel.error);
        }
      }

      logMessage('✅ 즉시 자동 알람 실행 완료: ${alarm.routeNo}번',
          level: LogLevel.info);
    } catch (e) {
      logMessage('❌ 즉시 자동 알람 실행 오류: $e', level: LogLevel.error);
    }
  }

  Future<void> _saveAutoAlarms() async {
    try {
      logMessage('🔄 자동 알람 저장 시작...');
      final prefs = await SharedPreferences.getInstance();
      final List<String> alarms = _state.autoAlarms.map((alarm) {
        final autoAlarm = AutoAlarm(
          id: alarm.id,
          routeNo: alarm.busNo,
          stationName: alarm.stationName,
          stationId: _resolveStationId(alarm.stationName, alarm.routeId),
          routeId: alarm.routeId,
          hour: alarm.scheduledTime.hour,
          minute: alarm.scheduledTime.minute,
          repeatDays: alarm.repeatDays ?? [],
          useTTS: alarm.useTTS,
          isActive: true,
        );

        final json = autoAlarm.toJson();
        json['scheduledTime'] = alarm.scheduledTime.toIso8601String();
        final jsonString = jsonEncode(json);

        logMessage('📝 알람 데이터 변환: ${alarm.busNo}번 버스');
        logMessage('  - ID: ${autoAlarm.id}');
        logMessage('  - 시간: ${autoAlarm.hour}:${autoAlarm.minute}');
        logMessage(
          '  - 정류장: ${autoAlarm.stationName} (${autoAlarm.stationId})',
        );
        logMessage(
          '  - 반복: ${autoAlarm.repeatDays.map((d) => [
                '월',
                '화',
                '수',
                '목',
                '금',
                '토',
                '일'
              ][d - 1]).join(", ")}',
        );
        logMessage('  - JSON: $jsonString');

        return jsonString;
      }).toList();

      logMessage('📊 저장할 알람 수: ${alarms.length}개');
      await prefs.setStringList('auto_alarms', alarms);

      final savedAlarms = prefs.getStringList('auto_alarms') ?? [];
      logMessage('✅ 자동 알람 저장 완료');
      logMessage('  - 저장된 알람 수: ${savedAlarms.length}개');
      if (savedAlarms.isNotEmpty) {
        final firstAlarm = jsonDecode(savedAlarms.first);
        logMessage('  - 첫 번째 알람 정보:');
        logMessage('    • 버스: ${firstAlarm['routeNo']}');
        logMessage('    • 시간: ${firstAlarm['scheduledTime']}');
        logMessage(
          '    • 반복: ${(firstAlarm['repeatDays'] as List).map((d) => [
                '월',
                '화',
                '수',
                '목',
                '금',
                '토',
                '일'
              ][d - 1]).join(", ")}',
        );
      }
    } catch (e) {
      logMessage('❌ 자동 알람 저장 오류: $e', level: LogLevel.error);
      logMessage('  - 스택 트레이스: ${e is Error ? e.stackTrace : "없음"}');
    }
  }
}
