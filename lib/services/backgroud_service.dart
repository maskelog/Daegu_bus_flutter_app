import 'package:daegu_bus_app/main.dart';
import 'package:daegu_bus_app/services/bus_api_service.dart';
import 'package:flutter/services.dart';
import 'package:workmanager/workmanager.dart';
import '../utils/simple_tts_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'alarm_service.dart';
import '../models/auto_alarm.dart';
import '../models/bus_info.dart';
import 'notification_service.dart';
import 'settings_service.dart';

const int defaultPreNotificationMinutes = 5;

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      logMessage("📱 Background 작업 시작: $task - ${DateTime.now()}");

      // 입력 데이터 파싱 및 디버깅
      final String routeId = inputData?['routeId'] ?? '';
      final String stationName = inputData?['stationName'] ?? '';
      final String busNo = inputData?['busNo'] ?? '';
      final bool useTTS = inputData?['useTTS'] ?? true;

      // alarmId가 문자열로 전달될 수 있으므로 안전하게 처리
      final dynamic rawAlarmId = inputData?['alarmId'];
      final int alarmId =
          rawAlarmId is int
              ? rawAlarmId
              : (rawAlarmId is String ? int.tryParse(rawAlarmId) ?? 0 : 0);

      final String stationId = inputData?['stationId'] ?? '';

      // remainingMinutes도 안전하게 처리
      final dynamic rawMinutes = inputData?['remainingMinutes'];
      final int remainingMinutes =
          rawMinutes is int
              ? rawMinutes
              : (rawMinutes is String ? int.tryParse(rawMinutes) ?? 3 : 3);

      logMessage(
        "📱 작업 파라미터: busNo=$busNo, stationName=$stationName, routeId=$routeId",
      );

      try {
        // 자동 알람 초기화 작업 처리
        if (task == 'initAutoAlarms') {
          return await _handleInitAutoAlarms(inputData: inputData);
        }

        // 자동 알람 작업 처리
        if (task == 'autoAlarmTask') {
          return await _handleAutoAlarmTask(
            busNo: busNo,
            stationName: stationName,
            routeId: routeId,
            stationId: stationId,
            remainingMinutes: remainingMinutes,
            useTTS: useTTS,
            alarmId: alarmId,
          );
        }

        // TTS 반복 작업 처리
        if (task == 'ttsRepeatingTask') {
          return await _handleTTSRepeatingTask(
            busNo: busNo,
            stationName: stationName,
            routeId: routeId,
            stationId: stationId,
            useTTS: useTTS,
            alarmId: alarmId,
          );
        }

        logMessage("⚠️ 처리되지 않은 작업 유형: $task");
        return false;
      } catch (e) {
        logMessage("❗ 작업 내부 처리 오류: $e");
        return false;
      }
    } catch (e) {
      logMessage("🔴 callbackDispatcher 예외: $e");
      return false;
    }
  });
}

Future<bool> _handleInitAutoAlarms({Map<String, dynamic>? inputData}) async {
  // 입력 데이터 로깅
  final timestamp =
      inputData?['timestamp'] ?? DateTime.now().millisecondsSinceEpoch;
  final autoAlarmsCount = inputData?['autoAlarmsCount'] ?? 0;
  final isRetry = inputData?['isRetry'] ?? false;

  logMessage(
    "🔄 자동 알람 초기화 시작 - 타임스탬프: $timestamp, 알람 수: $autoAlarmsCount, 재시도: $isRetry",
  );
  const int maxRetries = 3;
  int retryCount = 0;

  while (retryCount < maxRetries) {
    try {
      // 기존 자동 알람 작업 모두 취소
      try {
        await Workmanager().cancelAll();
        logMessage("✅ 기존 WorkManager 작업 모두 취소");
      } catch (e) {
        logMessage("⚠️ 기존 WorkManager 작업 취소 오류 (무시): $e");
      }

      final prefs = await SharedPreferences.getInstance();
      final alarms = prefs.getStringList('auto_alarms') ?? [];

      if (alarms.isEmpty) {
        logMessage("⚠️ 저장된 자동 알람이 없습니다");
        return true; // 알람이 없어도 성공으로 처리
      }

      logMessage("📊 저장된 자동 알람: ${alarms.length}개");

      final now = DateTime.now();
      final currentWeekday = now.weekday;
      final isWeekend = currentWeekday == 6 || currentWeekday == 7;

      int processedCount = 0;
      int registeredCount = 0;
      int immediateCount = 0;

      for (var json in alarms) {
        try {
          final data = jsonDecode(json);
          final autoAlarm = AutoAlarm.fromJson(data);

          // 알람이 활성화되어 있는지 확인
          if (!autoAlarm.isActive) {
            logMessage(
              "⚠️ 비활성화된 알람 건너뜀: ${autoAlarm.routeNo} ${autoAlarm.stationName}",
            );
            continue;
          }

          // 오늘이 알람 요일인지 확인
          if (!_shouldProcessAlarm(autoAlarm, currentWeekday, isWeekend)) {
            logMessage(
              "⚠️ 오늘은 알람 요일이 아님: ${autoAlarm.routeNo} ${autoAlarm.stationName}",
            );
            continue;
          }

          // 다음 알람 시간 계산
          final scheduledTime = _calculateNextScheduledTime(autoAlarm, now);
          if (scheduledTime == null) {
            logMessage(
              "⚠️ 유효한 알람 시간을 찾을 수 없음: ${autoAlarm.routeNo} ${autoAlarm.stationName}",
            );
            continue;
          }

          // 알람 시간이 지금부터 1분 이내인 경우만 즉시 실행 (더 엄격한 조건 적용)
          final timeUntilAlarm = scheduledTime.difference(now).inMinutes;
          final timeUntilAlarmSeconds = scheduledTime.difference(now).inSeconds;

          // 알람 시간이 지금부터 1분 이내이고, 아직 시간이 지나지 않았을 경우만 즉시 실행
          if (timeUntilAlarm <= 1 && timeUntilAlarmSeconds >= 0) {
            logMessage(
              "🔔 알람 시간이 1분 이내입니다. 즉시 실행: ${autoAlarm.routeNo} ${autoAlarm.stationName}, 남은 시간: $timeUntilAlarmSeconds초",
            );

            // 즉시 알람 실행
            await _handleAutoAlarmTask(
              busNo: autoAlarm.routeNo,
              stationName: autoAlarm.stationName,
              routeId: autoAlarm.routeId,
              stationId: autoAlarm.stationId,
              remainingMinutes: 3,
              useTTS: autoAlarm.useTTS,
              alarmId: int.parse(autoAlarm.id),
            );

            immediateCount++;
          }

          // 다음 알람 작업 등록
          final success = await _registerAutoAlarmTask(
            autoAlarm,
            scheduledTime,
          );
          if (success) registeredCount++;
          processedCount++;
        } catch (e) {
          logMessage("❌ 알람 처리 중 오류: $e");
        }
      }

      logMessage(
        "📊 자동 알람 초기화 완료: 처리 $processedCount개, 등록 $registeredCount개, 즉시실행 $immediateCount개",
      );
      return registeredCount > 0 || immediateCount > 0;
    } catch (e) {
      retryCount++;
      logMessage("❌ 자동 알람 초기화 시도 #$retryCount 실패: $e");
      if (retryCount < maxRetries) {
        await Future.delayed(Duration(seconds: 2 * retryCount));
      }
    }
  }
  return false;
}

Future<void> _showLocalNotification(
  int id,
  String busNo,
  String stationName,
  int remainingMinutes,
  String routeId,
) async {
  try {
    // 로컬 알림 대신 MethodChannel을 사용하여 네이티브 알림 표시
    const MethodChannel channel = MethodChannel(
      'com.example.daegu_bus_app/bus_api',
    );
    final int safeNotificationId = id.abs() % 2147483647;

    // 네이티브 메서드 호출
    await channel.invokeMethod('showNotification', {
      'id': safeNotificationId,
      'busNo': busNo,
      'stationName': stationName,
      'remainingMinutes': remainingMinutes,
      'currentStation': '자동 알람',
      'payload': routeId,
      'isAutoAlarm': true,
      'isOngoing': false,
      'routeId': routeId,
      'notificationTime': DateTime.now().millisecondsSinceEpoch,
      'useTTS': false,
      'actions': ['cancel_alarm'],
    });

    logMessage('✅ 로컬 알림 표시 성공: $busNo, $stationName ($id)');
  } catch (e) {
    logMessage('❌ 로컬 알림 표시 실패: $e', level: LogLevel.error);
    rethrow;
  }
}

Future<bool> _handleAutoAlarmTask({
  required String busNo,
  required String stationName,
  required String routeId,
  required String stationId,
  required int remainingMinutes,
  required bool useTTS,
  required int alarmId,
}) async {
  try {
    logMessage("🔔 자동 알람 작업 실행: $busNo번 버스, 현재시간: ${DateTime.now()}");

    // 알람 시간 제한 확인 (예약된 시간으로부터 10분까지만 허용)
    final prefs = await SharedPreferences.getInstance();
    final alarmDataStr = prefs.getString('last_executed_alarm_$alarmId');
    if (alarmDataStr != null) {
      final alarmData = jsonDecode(alarmDataStr);
      final scheduledTime = DateTime.parse(
        alarmData['scheduledTime'] ?? DateTime.now().toIso8601String(),
      );
      final now = DateTime.now();
      final difference = now.difference(scheduledTime).inMinutes;

      if (difference > 10) {
        logMessage(
          "⚠️ 예약된 알람 시간으로부터 10분이 지났습니다. 알람을 취소합니다.",
          level: LogLevel.warning,
        );
        return false;
      }
    }

    // 먼저 실시간 버스 정보 가져오기
    BusArrivalInfo? busArrivalInfo;
    String? currentStation;
    int actualRemainingMinutes = remainingMinutes;

    // 현재 시간 로깅 (운행 시간 제한 제거)
    final now = DateTime.now();
    final hour = now.hour;

    // 운행 시간 외 알람 실행 시 로그만 남기고 계속 진행
    if (hour < 5 || hour >= 23) {
      logMessage(
        "⚠️ 현재 버스 운행 시간이 아닙니다 (현재 시간: $hour시). 테스트 목적으로 계속 진행합니다.",
        level: LogLevel.warning,
      );
    }

    try {
      logMessage("🚌 자동 알람 버스 정보 업데이트 시도: $busNo번, $stationName");
      int apiRetryCount = 0;
      const maxRetries = 3;

      while (busArrivalInfo == null && apiRetryCount < maxRetries) {
        try {
          busArrivalInfo = await BusApiService().getBusArrivalByRouteId(
            stationId,
            routeId,
          );
          if (busArrivalInfo == null) {
            apiRetryCount++;
            logMessage("⚠️ 버스 정보 API 응답 없음. 재시도 #$apiRetryCount");
            await Future.delayed(const Duration(seconds: 2));
          } else {
            logMessage("✅ 버스 정보 API 응답 성공");
          }
        } catch (e) {
          apiRetryCount++;
          logMessage("❌ 버스 정보 API 호출 오류. 재시도 #$apiRetryCount: $e");
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      if (busArrivalInfo != null && busArrivalInfo.bus.isNotEmpty) {
        final busInfo = busArrivalInfo.bus.first;
        currentStation = busInfo.currentStation;
        final estimatedTimeStr = busInfo.estimatedTime.replaceAll(
          RegExp(r'[^0-9]'),
          '',
        );

        // 도착 예정 시간이 유효한 경우에만 업데이트
        if (estimatedTimeStr.isNotEmpty) {
          actualRemainingMinutes = int.parse(estimatedTimeStr);
          logMessage(
            "✅ 실시간 버스 정보 가져오기 성공: $busNo, 남은 시간: $actualRemainingMinutes분, 위치: $currentStation",
          );
        } else {
          logMessage("⚠️ 유효한 도착 시간 정보가 없습니다.", level: LogLevel.warning);
          actualRemainingMinutes = remainingMinutes; // 기본값 사용
        }
      } else {
        logMessage("⚠️ 버스 정보를 가져올 수 없습니다.", level: LogLevel.warning);
        actualRemainingMinutes = remainingMinutes; // 기본값 사용
      }
    } catch (e) {
      logMessage("❌ 버스 정보 업데이트 중 오류: $e", level: LogLevel.error);
      actualRemainingMinutes = remainingMinutes; // 오류 시 기본값 사용
    }

    // 알림 표시 시도
    bool notificationSent = false;

    // MethodChannel을 통한 알림 시도
    try {
      const MethodChannel channel = MethodChannel(
        'com.example.daegu_bus_app/bus_api',
      );
      final int safeNotificationId = alarmId.abs() % 2147483647;

      await channel.invokeMethod('showNotification', {
        'id': safeNotificationId,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': actualRemainingMinutes,
        'currentStation': currentStation ?? '실시간 정보 로드 중...',
        'payload': routeId,
        'isAutoAlarm': true,
        'isOngoing': true,
        'routeId': routeId,
        'notificationTime': DateTime.now().millisecondsSinceEpoch,
        'useTTS': false,
        'actions': ['cancel_alarm'],
        'actionLabels': {'cancel_alarm': '알람 취소'},
      });
      logMessage("✅ 알림 표시 성공");
      notificationSent = true;
    } catch (e) {
      logMessage("❌ 알림 표시 오류: $e");
    }

    // 로컬 알림으로 시도 (백업)
    if (!notificationSent) {
      try {
        await _showLocalNotification(
          alarmId,
          busNo,
          stationName,
          actualRemainingMinutes,
          routeId,
        );
        logMessage("✅ 로컬 알림 표시 성공");
        notificationSent = true;
      } catch (e) {
        logMessage("❌ 로컬 알림 표시 오류: $e");
      }
    }

    // TTS 알림 발화
    if (useTTS) {
      try {
        await _speakAlarm(busNo, stationName, actualRemainingMinutes);
        logMessage("🔊 TTS 알람 발화 성공");
      } catch (e) {
        logMessage("🔊 TTS 알람 발화 오류: $e", level: LogLevel.error);
        try {
          await SimpleTTSHelper.initialize();
          await SimpleTTSHelper.speak(
            "$busNo번 버스가 약 $actualRemainingMinutes분 후 도착 예정입니다.",
          );
          logMessage("🔊 백업 TTS 발화 성공");
        } catch (fallbackError) {
          logMessage("🔊 백업 TTS 발화도 실패: $fallbackError", level: LogLevel.error);
        }
      }
    }

    // 메인 앱에 알람 정보 저장
    try {
      await _saveAlarmInfoForMainApp(
        alarmId,
        busNo,
        stationName,
        actualRemainingMinutes,
        routeId,
        stationId,
        currentStation,
      );
      logMessage("✅ 메인 앱 알람 정보 저장 성공");
    } catch (e) {
      logMessage("❌ 메인 앱 알람 정보 저장 실패: $e", level: LogLevel.error);
    }

    return true;
  } catch (e) {
    logMessage("❌ 자동 알람 작업 실행 오류: $e", level: LogLevel.error);
    try {
      await _showLocalNotification(
        alarmId,
        busNo,
        stationName,
        remainingMinutes,
        routeId,
      );
      logMessage("✅ 오류 발생 시 로컬 알림 표시 성공");
    } catch (e) {
      logMessage("❌ 오류 발생 시 로컬 알림 표시 실패: $e", level: LogLevel.error);
    }
    return false;
  }
}

Future<bool> _handleTTSRepeatingTask({
  required String busNo,
  required String stationName,
  required String routeId,
  required String stationId,
  required bool useTTS,
  required int alarmId,
}) async {
  try {
    if (!useTTS) return true;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('alarm_cancelled_$alarmId') ?? false) {
      await Workmanager().cancelByUniqueName('tts-$alarmId');
      return true;
    }

    // AlarmService 인스턴스 생성하여 TTS 알람 시작 기능 사용
    final alarmService = AlarmService(
      notificationService: NotificationService(),
      settingsService: SettingsService(),
    );

    // 버스 도착 정보 가져오기
    try {
      logMessage("🐛 [DEBUG] TTS 반복 작업 - 버스 정보 업데이트 시도: $busNo번, $stationName");

      // 여러 번 시도하는 로직 추가
      BusArrivalInfo? info;
      int retryCount = 0;
      const maxRetries = 3;

      while (retryCount < maxRetries && info == null) {
        try {
          info = await BusApiService().getBusArrivalByRouteId(
            stationId,
            routeId,
          );
          if (info == null) {
            retryCount++;
            logMessage(
              "⚠️ TTS 반복 작업 - 버스 정보 조회 실패 ($retryCount/$maxRetries) - 재시도 중",
            );
            await Future.delayed(const Duration(seconds: 2));
          }
        } catch (e) {
          retryCount++;
          logMessage("❌ TTS 반복 작업 - 버스 정보 조회 오류 ($retryCount/$maxRetries): $e");
          await Future.delayed(const Duration(seconds: 2));
        }
      }

      if (info == null || info.bus.isEmpty) {
        logMessage("⚠️ TTS 반복 작업 - 버스 정보를 가져오지 못함");
        await SimpleTTSHelper.speak("$busNo번 버스 도착 정보를 가져올 수 없습니다.");
        return false;
      }

      logMessage(
        "🐛 [DEBUG] TTS 반복 작업 - 버스 정보 조회 성공: ${info.bus.length}개 버스 정보 받음",
      );
      final busData = info.bus.first;
      // 여기서 models/bus_info.dart의 BusInfo로 변환
      final busInfoFromApi = BusInfo.fromBusInfoData(busData);

      // TTS 발화
      await _speakBusInfo(busInfoFromApi, busNo, stationName);

      // 버스 정보 캐시에 업데이트할 필요가 있는 경우
      // BusArrival의 BusInfo로 변환해서 전달
      final remainingTime =
          int.tryParse(
            busInfoFromApi.estimatedTime.replaceAll(RegExp(r'[^0-9]'), ''),
          ) ??
          0;

      // AlarmService에 직접 정보 전달하지 않고 TTS 알람만 시작
      await alarmService.startAlarm(busNo, stationName, remainingTime);

      logMessage("🔔 TTS 알람 실행 완료: $busNo, 남은 시간: $remainingTime분");
      return true;
    } catch (e) {
      logMessage("❌ 버스 정보 조회 오류: $e");

      // 오류 발생 시 간단한 알림 시도
      await alarmService.startAlarm(busNo, stationName, 0);
      return false;
    }
  } catch (e) {
    logMessage("❌ TTS 반복 작업 오류: $e");
    return false;
  }
}

bool _shouldProcessAlarm(AutoAlarm alarm, int currentWeekday, bool isWeekend) {
  if (!alarm.isActive) return false;
  if (alarm.excludeWeekends && isWeekend) return false;
  if (!alarm.repeatDays.contains(currentWeekday)) return false;
  return true;
}

DateTime? _calculateNextScheduledTime(AutoAlarm alarm, DateTime now) {
  // 오늘 알람 시간 계산
  DateTime todayScheduledTime = DateTime(
    now.year,
    now.month,
    now.day,
    alarm.hour,
    alarm.minute,
  );

  // 오늘이 반복 요일에 포함되는지 확인
  bool isTodayValid = alarm.repeatDays.contains(now.weekday);

  // 오늘이 반복 요일이고 아직 시간이 지나지 않았다면
  if (isTodayValid && todayScheduledTime.isAfter(now)) {
    logMessage('✅ 오늘 자동 알람 시간 사용: ${todayScheduledTime.toString()}');
    return todayScheduledTime;
  }

  // 오늘이 반복 요일이고 시간이 조금 지났지만 1분 이내인 경우만 즉시 실행
  if (isTodayValid &&
      now.difference(todayScheduledTime).inMinutes <= 1 &&
      now.difference(todayScheduledTime).inSeconds <= 60) {
    // 시간이 지난 지 1분 이내인 경우만 즉시 실행
    logMessage(
      '✅ 자동 알람 시간이 방금 지났습니다. 즉시 실행: ${todayScheduledTime.toString()}, '
      '지난 시간: ${now.difference(todayScheduledTime).inSeconds}초',
    );
    // 현재 시간에서 30초 후로 설정
    return now.add(const Duration(seconds: 30));
  }

  // 다음 유효한 알람 요일 찾기
  int daysToAdd = 1;
  while (daysToAdd <= 7) {
    final nextDate = now.add(Duration(days: daysToAdd));
    if (alarm.repeatDays.contains(nextDate.weekday)) {
      final nextScheduledTime = DateTime(
        nextDate.year,
        nextDate.month,
        nextDate.day,
        alarm.hour,
        alarm.minute,
      );
      logMessage('✅ 다음 자동 알람 시간 찾음: ${nextScheduledTime.toString()}');
      return nextScheduledTime;
    }
    daysToAdd++;
  }

  logMessage('⚠️ 유효한 자동 알람 시간을 찾을 수 없습니다');
  return null;
}

Future<bool> _registerAutoAlarmTask(
  AutoAlarm alarm,
  DateTime scheduledTime,
) async {
  try {
    final now = DateTime.now();
    final initialDelay = scheduledTime.difference(now);

    // 이미 시간이 지났거나 1분 이내인 경우 즉시 실행
    if (initialDelay.isNegative || initialDelay.inMinutes <= 1) {
      logMessage(
        '🔔 알람 시간이 이미 지났거나 1분 이내입니다. 즉시 실행: ${alarm.routeNo}, ${alarm.stationName}',
      );

      // 즉시 알람 실행
      return await _executeAlarmDirectly(alarm);
    }

    // 작업 ID 생성 (고유성 보장)
    final String uniqueTaskId =
        'autoAlarm_${alarm.id}_${DateTime.now().millisecondsSinceEpoch}';

    // 입력 데이터 (확장)
    final Map<String, dynamic> inputData = {
      'alarmId': alarm.id,
      'busNo': alarm.routeNo,
      'stationName': alarm.stationName,
      'routeId': alarm.routeId,
      'stationId': alarm.stationId,
      'useTTS': alarm.useTTS,
      'remainingMinutes': 3,
      'scheduledTime': scheduledTime.millisecondsSinceEpoch,
      'createdAt': now.millisecondsSinceEpoch,
      'requiredStrict': initialDelay.inMinutes < 10, // 10분 이내는 엄격하게 실행
    };

    // 기존 알람 취소
    await Workmanager().cancelByUniqueName('autoAlarm_${alarm.id}');

    // 배터리 절약을 위한 최적화된 알람 예약
    await Workmanager().registerOneOffTask(
      uniqueTaskId,
      'autoAlarmTask',
      initialDelay: initialDelay,
      inputData: inputData,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true, // 배터리 부족 시 실행 안함
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: true, // 저장공간 부족 시 실행 안함
      ),
      backoffPolicy: BackoffPolicy.exponential, // 지수적 백오프로 변경
      backoffPolicyDelay: const Duration(minutes: 5), // 백오프 지연 시간 증가
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

    // 백업 알람 등록 (5분 또는 1분 전)
    Duration backupDelay =
        initialDelay - Duration(minutes: initialDelay.inMinutes > 10 ? 5 : 1);
    if (backupDelay.inSeconds > 0) {
      await _registerBackupAlarm(alarm, scheduledTime, backupDelay);
    }

    // 저장 및 로깅
    await _saveRegisteredAlarmInfo(alarm, scheduledTime, uniqueTaskId);

    return true;
  } catch (e) {
    logMessage('❌ 알람 예약 오류: $e', level: LogLevel.error);
    return false;
  }
}

/// TTS로 알람 발화
Future<void> _speakAlarm(
  String busNo,
  String stationName,
  int remainingMinutes,
) async {
  try {
    // TTS 엔진 초기화
    await SimpleTTSHelper.initialize();

    String message;
    if (remainingMinutes <= 0) {
      message = "$busNo번 버스가 $stationName 정류장에 곧 도착합니다. 탑승 준비하세요.";
    } else {
      message = "$busNo번 버스가 약 $remainingMinutes분 후 도착 예정입니다.";
    }

    // 볼륨 최대화 및 스피커 모드 설정
    await SimpleTTSHelper.setVolume(1.0);
    await SimpleTTSHelper.setAudioOutputMode(1); // 스피커 모드

    // 자동 알람은 이어폰 체크를 무시하고 강제 스피커 모드로 발화
    await SimpleTTSHelper.speak(message, force: true, earphoneOnly: false);
    logMessage("🔊 TTS 발화 완료: $message (강제 스피커 모드)");

    // 5초 후 한 번 더 발화 시도 (백업)
    await Future.delayed(const Duration(seconds: 5));
    await SimpleTTSHelper.speak(message, force: true, earphoneOnly: false);
    logMessage("🔊 백업 TTS 발화 완료: $message (5초 후)");
  } catch (e) {
    logMessage("❌ TTS 발화 중 오류: $e", level: LogLevel.error);

    // 오류 발생 시 네이티브 TTS 직접 호출 시도
    try {
      const MethodChannel channel = MethodChannel(
        'com.example.daegu_bus_app/tts',
      );
      await channel.invokeMethod('speakTTS', {
        'message': "$busNo번 버스가 $stationName 정류장에 도착 예정입니다.",
        'isHeadphoneMode': false,
        'forceSpeaker': true,
      });
      logMessage("🔊 네이티브 TTS 발화 시도 (백업)");
    } catch (e) {
      logMessage("❌ 네이티브 TTS 발화도 실패: $e", level: LogLevel.error);
      rethrow;
    }
  }
}

/// 메인 앱에서 알림을 표시할 수 있도록 SharedPreferences에 알람 정보 저장
Future<void> _saveAlarmInfoForMainApp(
  int alarmId,
  String busNo,
  String stationName,
  int remainingMinutes,
  String routeId,
  String stationId, [
  String? currentStation,
]) async {
  try {
    final prefs = await SharedPreferences.getInstance();

    // 알람 정보 저장
    await prefs.setString(
      'last_auto_alarm_data',
      jsonEncode({
        'alarmId': alarmId,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'routeId': routeId,
        'stationId': stationId,
        'currentStation': currentStation,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'isAutoAlarm': true,
        'hasRealTimeInfo': currentStation != null && currentStation.isNotEmpty,
      }),
    );

    // 새 알람 플래그 설정
    await prefs.setBool('has_new_auto_alarm', true);

    // 알람 이력에 추가
    final alarmHistoryJson = prefs.getString('auto_alarm_history') ?? '[]';
    final List<dynamic> alarmHistory = jsonDecode(alarmHistoryJson);

    // 최근 10개 알람만 유지
    if (alarmHistory.length >= 10) {
      alarmHistory.removeAt(0);
    }

    // 새 알람 이력 추가
    alarmHistory.add({
      'alarmId': alarmId,
      'busNo': busNo,
      'stationName': stationName,
      'executedAt': DateTime.now().toIso8601String(),
      'success': true,
    });

    await prefs.setString('auto_alarm_history', jsonEncode(alarmHistory));
    logMessage("✅ 알람 정보 저장 완료 - 메인 앱에서 처리 가능");
  } catch (e) {
    logMessage("❌ 알람 정보 저장 실패: $e", level: LogLevel.error);
  }
}

Future<void> _speakBusInfo(
  BusInfo bus,
  String busNo,
  String stationName,
) async {
  final remainingTime = bus.estimatedTime;

  if (remainingTime == '운행종료' || remainingTime.contains('곧도착')) {
    await SimpleTTSHelper.speakBusArriving(busNo, stationName);
    return;
  }

  final mins =
      int.tryParse(remainingTime.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  final remainingStops =
      int.tryParse(bus.remainingStops.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;

  await SimpleTTSHelper.speakBusAlert(
    busNo: busNo,
    stationName: stationName,
    remainingMinutes: mins,
    currentStation: bus.currentStation,
    remainingStops: remainingStops,
    isAutoAlarm: true,
  );
}

/// 알람 직접 실행 메소드
Future<bool> _executeAlarmDirectly(AutoAlarm alarm) async {
  try {
    logMessage('🔔 알람 즉시 실행: ${alarm.routeNo}, ${alarm.stationName}');

    return await _handleAutoAlarmTask(
      busNo: alarm.routeNo,
      stationName: alarm.stationName,
      routeId: alarm.routeId,
      stationId: alarm.stationId,
      remainingMinutes: 3,
      useTTS: alarm.useTTS,
      alarmId: int.parse(alarm.id),
    );
  } catch (e) {
    logMessage('❌ 알람 즉시 실행 오류: $e', level: LogLevel.error);
    return false;
  }
}

/// 백업 알람 등록 메소드
Future<void> _registerBackupAlarm(
  AutoAlarm alarm,
  DateTime scheduledTime,
  Duration backupDelay,
) async {
  try {
    final String backupTaskId =
        'autoAlarm_backup_${alarm.id}_${DateTime.now().millisecondsSinceEpoch}';

    // 백업 알람 입력 데이터
    final Map<String, dynamic> backupInputData = {
      'alarmId': alarm.id,
      'busNo': alarm.routeNo,
      'stationName': alarm.stationName,
      'routeId': alarm.routeId,
      'stationId': alarm.stationId,
      'useTTS': alarm.useTTS,
      'remainingMinutes': 3,
      'scheduledTime': scheduledTime.millisecondsSinceEpoch,
      'isBackup': true,
    };

    // 배터리 절약을 위한 최적화된 백업 알람 등록
    await Workmanager().registerOneOffTask(
      backupTaskId,
      'autoAlarmTask',
      initialDelay: backupDelay,
      inputData: backupInputData,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true, // 배터리 부족 시 백업도 실행 안함
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: true, // 저장공간 부족 시 백업도 실행 안함
      ),
      backoffPolicy: BackoffPolicy.exponential, // 지수적 백오프
      backoffPolicyDelay: const Duration(minutes: 10), // 백업은 더 긴 지연
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );

    logMessage('✅ 백업 알람 등록 완료: ${backupDelay.inMinutes}분 전');
  } catch (e) {
    logMessage('❌ 백업 알람 등록 오류: $e', level: LogLevel.error);
  }
}

/// 등록된 알람 정보 저장 메소드
Future<void> _saveRegisteredAlarmInfo(
  AutoAlarm alarm,
  DateTime scheduledTime,
  String taskId,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();

    // 알람 등록 정보 생성
    final Map<String, dynamic> registrationInfo = {
      'alarmId': alarm.id,
      'busNo': alarm.routeNo,
      'stationName': alarm.stationName,
      'routeId': alarm.routeId,
      'scheduledTime': scheduledTime.toIso8601String(),
      'taskId': taskId,
      'registeredAt': DateTime.now().toIso8601String(),
    };

    // 등록된 알람 목록 가져오기
    final registeredAlarmsJson = prefs.getString('registered_alarms') ?? '[]';
    final List<dynamic> registeredAlarms = jsonDecode(registeredAlarmsJson);

    // 이전 등록 정보 제거
    registeredAlarms.removeWhere((item) => item['alarmId'] == alarm.id);

    // 새 등록 정보 추가
    registeredAlarms.add(registrationInfo);

    // 업데이트된 목록 저장
    await prefs.setString('registered_alarms', jsonEncode(registeredAlarms));

    logMessage(
      '✅ 알람 등록 정보 저장 완료: ${alarm.routeNo}, ${scheduledTime.toString()}',
    );
  } catch (e) {
    logMessage('❌ 알람 등록 정보 저장 오류: $e', level: LogLevel.error);
  }
}
