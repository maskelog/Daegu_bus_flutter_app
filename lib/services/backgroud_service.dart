import 'package:daegu_bus_app/main.dart';
import 'package:daegu_bus_app/services/bus_api_service.dart';
import 'package:daegu_bus_app/services/api_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import '../utils/simple_tts_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:ui';
import 'alarm_service.dart';
import '../models/auto_alarm.dart';
import '../models/bus_info.dart';

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
      final int alarmId = rawAlarmId is int
          ? rawAlarmId
          : (rawAlarmId is String ? int.tryParse(rawAlarmId) ?? 0 : 0);

      final String stationId = inputData?['stationId'] ?? '';

      // remainingMinutes도 안전하게 처리
      final dynamic rawMinutes = inputData?['remainingMinutes'];
      final int remainingMinutes = rawMinutes is int
          ? rawMinutes
          : (rawMinutes is String ? int.tryParse(rawMinutes) ?? 3 : 3);

      logMessage(
          "📱 작업 파라미터: busNo=$busNo, stationName=$stationName, routeId=$routeId");

      try {
        // 자동 알람 초기화 작업 처리
        if (task == 'initAutoAlarms') {
          return await _handleInitAutoAlarms();
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

Future<bool> _handleInitAutoAlarms() async {
  logMessage("🔄 자동 알람 초기화 시작");
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
                "⚠️ 비활성화된 알람 건너뜀: ${autoAlarm.routeNo} ${autoAlarm.stationName}");
            continue;
          }

          // 오늘이 알람 요일인지 확인
          if (!_shouldProcessAlarm(autoAlarm, currentWeekday, isWeekend)) {
            logMessage(
                "⚠️ 오늘은 알람 요일이 아님: ${autoAlarm.routeNo} ${autoAlarm.stationName}");
            continue;
          }

          // 다음 알람 시간 계산
          final scheduledTime = _calculateNextScheduledTime(autoAlarm, now);
          if (scheduledTime == null) {
            logMessage(
                "⚠️ 유효한 알람 시간을 찾을 수 없음: ${autoAlarm.routeNo} ${autoAlarm.stationName}");
            continue;
          }

          // 알람 시간이 지금부터 1분 이내인 경우만 즉시 실행 (더 엄격한 조건 적용)
          final timeUntilAlarm = scheduledTime.difference(now).inMinutes;
          final timeUntilAlarmSeconds = scheduledTime.difference(now).inSeconds;

          // 알람 시간이 지금부터 1분 이내이고, 아직 시간이 지나지 않았을 경우만 즉시 실행
          if (timeUntilAlarm <= 1 && timeUntilAlarmSeconds >= 0) {
            logMessage(
                "🔔 알람 시간이 1분 이내입니다. 즉시 실행: ${autoAlarm.routeNo} ${autoAlarm.stationName}, 남은 시간: $timeUntilAlarmSeconds초");

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
          final success =
              await _registerAutoAlarmTask(autoAlarm, scheduledTime);
          if (success) registeredCount++;
          processedCount++;
        } catch (e) {
          logMessage("❌ 알람 처리 중 오류: $e");
        }
      }

      logMessage(
          "📊 자동 알람 초기화 완료: 처리 $processedCount개, 등록 $registeredCount개, 즉시실행 $immediateCount개");
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

    // BackgroundIsolateBinaryMessenger 초기화
    if (!kIsWeb) {
      try {
        final rootIsolateToken = RootIsolateToken.instance;
        if (rootIsolateToken != null) {
          BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
          logMessage('✅ BackgroundIsolateBinaryMessenger 초기화 성공');
        } else {
          logMessage('⚠️ RootIsolateToken이 null입니다', level: LogLevel.warning);
        }
      } catch (e) {
        logMessage('⚠️ BackgroundIsolateBinaryMessenger 초기화 오류 (무시): $e',
            level: LogLevel.warning);
      }
    }

    // 알람 서비스 초기화
    final alarmService = AlarmService();
    try {
      await alarmService.initialize();
      logMessage("✅ 알람 서비스 초기화 성공");
    } catch (e) {
      logMessage("❌ 알람 서비스 초기화 오류: $e");
    }

    // 백그라운드에서 알림 전송 방식 개선
    try {
      // 자동 알람 시작 알림
      if (useTTS) {
        try {
          await SimpleTTSHelper.initialize();
          await SimpleTTSHelper.speak("$busNo번 버스 $stationName 승차 알람이 시작됩니다.");
          logMessage("🔊 TTS 알람 발화 성공");
        } catch (e) {
          logMessage("🔊 TTS 알람 발화 오류: $e");
        }
      }

      // ApiService를 사용하여 백그라운드 알림 표시 (첫 번째 알림)
      try {
        final bool success = await ApiService.showBackgroundNotification(
          id: alarmId,
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          currentStation: '자동 알람',
          routeId: routeId,
          isAutoAlarm: true,
        );

        if (success) {
          logMessage("✅ ApiService를 통한 알림 표시 성공");
        } else {
          logMessage("⚠️ ApiService를 통한 알림 표시 실패");

          // 실패 시 기존 방식으로 시도
          const MethodChannel channel =
              MethodChannel('com.example.daegu_bus_app/notification');
          final int safeNotificationId = alarmId.abs() % 2147483647;

          await channel.invokeMethod('showNotification', {
            'id': safeNotificationId,
            'busNo': busNo,
            'stationName': stationName,
            'remainingMinutes': remainingMinutes,
            'currentStation': '자동 알람',
            'payload': routeId,
            'isAutoAlarm': true,
            'isOngoing': true,
            'routeId': routeId,
            'notificationTime': DateTime.now().millisecondsSinceEpoch,
            'useTTS': true,
            'actions': ['cancel_alarm'],
          });
          logMessage("✅ 기존 방식으로 백업 알림 표시 성공");
        }
      } catch (e) {
        logMessage("❌ 첫 번째 알림 표시 오류: $e");
      }

      // 버스 도착 정보 API 호출
      logMessage("🐛 [DEBUG] 자동 알람 버스 정보 업데이트 시도: $busNo번, $stationName");

      // 기본값 설정
      int actualRemainingMinutes = remainingMinutes;
      String? currentStation;

      // TTS 발화 - 기본 정보로 안내
      if (useTTS) {
        try {
          // 기본 안내 메시지 사용
          await SimpleTTSHelper.speak(
              "$busNo번 버스 $stationName 정류장 알람이 시작되었습니다. 잠시 후 실시간 정보를 안내해 드리겠습니다.");
          logMessage("🔊 TTS 알람 발화 성공");
        } catch (e) {
          logMessage("🔊 TTS 알람 발화 오류: $e");
        }
      }

      // 백그라운드에서도 실시간 버스 정보 가져오기 시도
      try {
        logMessage("🐛 [DEBUG] 백그라운드에서 실시간 버스 정보 가져오기 시도");

        // 버스 API 직접 호출
        final busArrivalInfo =
            await BusApiService().getBusArrivalByRouteId(stationId, routeId);

        if (busArrivalInfo != null && busArrivalInfo.bus.isNotEmpty) {
          // 버스 정보 추출
          final busData = busArrivalInfo.bus.first;
          final busInfo = BusInfo.fromBusInfoData(busData);
          currentStation = busInfo.currentStation;

          // 남은 시간 추출
          final estimatedTimeStr =
              busInfo.estimatedTime.replaceAll(RegExp(r'[^0-9]'), '');
          if (estimatedTimeStr.isNotEmpty) {
            actualRemainingMinutes = int.parse(estimatedTimeStr);
          }

          logMessage(
              "✅ 실시간 버스 정보 가져오기 성공: $busNo, 남은 시간: $actualRemainingMinutes분, 위치: $currentStation");
        } else {
          logMessage("⚠️ 실시간 버스 정보를 가져오지 못했습니다. 기본 정보로 진행합니다.");
        }
      } catch (e) {
        logMessage("❌ 실시간 버스 정보 가져오기 오류: $e");
        logMessage("⚠️ 기본 정보로 진행합니다.");
      }

      // 업데이트된 정보로 알림 표시
      try {
        final bool success = await ApiService.showBackgroundNotification(
          id: alarmId,
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: actualRemainingMinutes,
          currentStation: currentStation ?? '자동 알람 - 실시간 정보 로드 중',
          routeId: routeId,
          isAutoAlarm: true,
        );

        if (success) {
          logMessage("✅ 알림 표시 성공");
        } else {
          logMessage("⚠️ 알림 표시 실패");
        }
      } catch (e) {
        logMessage("❌ 알림 표시 오류: $e");
      }

      // 백업 방법: SharedPreferences에 알람 정보 저장 (앱이 활성화될 때 표시하기 위함)
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            'last_auto_alarm_data',
            jsonEncode({
              'alarmId': alarmId,
              'busNo': busNo,
              'stationName': stationName,
              'remainingMinutes': actualRemainingMinutes,
              'routeId': routeId,
              'stationId': stationId,
              'currentStation': currentStation,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'isAutoAlarm': true,
              'hasRealTimeInfo':
                  currentStation != null && currentStation.isNotEmpty
            }));
        await prefs.setBool('has_new_auto_alarm', true);
        logMessage("✅ 자동 알람 정보 저장 완료 - 메인 앱에서도 이를 감지하여 알림을 표시할 것입니다");

        if (currentStation != null && currentStation.isNotEmpty) {
          logMessage(
              "🐛 [DEBUG] 실시간 버스 정보 포함하여 저장 완료: $busNo, 남은 시간: $actualRemainingMinutes분, 위치: $currentStation");
        } else {
          logMessage("🐛 [DEBUG] 기본 정보로 저장 완료. 앱이 활성화될 때 업데이트 예정.");
        }
      } catch (e) {
        logMessage("❌ 자동 알람 정보 저장 실패: $e");
      }

      // 성공 반환
      logMessage("✅ 자동 알람 작동 완료: $busNo");
      return true;
    } catch (e) {
      logMessage("⚠️ 버스 정보 조회 또는 알림 표시 오류: $e");

      // 오류 발생 시에도 ApiService로 알림 표시 시도
      try {
        await ApiService.showBackgroundNotification(
          id: alarmId,
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          currentStation: '자동 알람 (정보 로드 실패)',
          routeId: routeId,
          isAutoAlarm: true,
        );
        logMessage("✅ 오류 상황에서도 ApiService로 알림 표시 성공");
      } catch (e) {
        logMessage("❌ 오류 상황에서 ApiService 알림 실패: $e");
      }

      // SharedPreferences에도 정보 저장 (백업)
      try {
        // 오류 발생 시에도 버스 정보 가져오기 시도
        String? currentStation;
        int actualRemainingMinutes = remainingMinutes;

        try {
          logMessage("🐛 [DEBUG] 오류 발생 후 실시간 버스 정보 가져오기 시도");
          final busArrivalInfo =
              await BusApiService().getBusArrivalByRouteId(stationId, routeId);

          if (busArrivalInfo != null && busArrivalInfo.bus.isNotEmpty) {
            final busData = busArrivalInfo.bus.first;
            final busInfo = BusInfo.fromBusInfoData(busData);
            currentStation = busInfo.currentStation;

            final estimatedTimeStr =
                busInfo.estimatedTime.replaceAll(RegExp(r'[^0-9]'), '');
            if (estimatedTimeStr.isNotEmpty) {
              actualRemainingMinutes = int.parse(estimatedTimeStr);
            }

            logMessage(
                "✅ 오류 후 실시간 버스 정보 가져오기 성공: $busNo, 남은 시간: $actualRemainingMinutes분, 위치: $currentStation");
          }
        } catch (e2) {
          logMessage("❌ 오류 후 실시간 버스 정보 가져오기 실패: $e2");
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
            'last_auto_alarm_data',
            jsonEncode({
              'alarmId': alarmId,
              'busNo': busNo,
              'stationName': stationName,
              'remainingMinutes': actualRemainingMinutes,
              'routeId': routeId,
              'stationId': stationId,
              'currentStation': currentStation,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'isAutoAlarm': true,
              'hasError': currentStation == null || currentStation.isEmpty,
              'hasRealTimeInfo':
                  currentStation != null && currentStation.isNotEmpty
            }));
        await prefs.setBool('has_new_auto_alarm', true);

        if (currentStation != null && currentStation.isNotEmpty) {
          logMessage(
              "✅ 오류 후 실시간 정보 포함하여 저장 완료: $busNo, 남은 시간: $actualRemainingMinutes분, 위치: $currentStation");
        } else {
          logMessage("✅ 오류 상황에서의 기본 알람 정보 저장 완료");
        }
      } catch (e2) {
        logMessage("❌ 기본 알람 정보 저장 실패: $e2");
      }

      return true; // 오류가 있어도 작업은 성공으로 처리
    }
  } catch (e) {
    logMessage("❌ 자동 알람 작업 실행 오류: $e");
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
    final alarmService = AlarmService();

    // 버스 도착 정보 가져오기
    try {
      logMessage("🐛 [DEBUG] TTS 반복 작업 - 버스 정보 업데이트 시도: $busNo번, $stationName");

      // 여러 번 시도하는 로직 추가
      BusArrivalInfo? info;
      int retryCount = 0;
      const maxRetries = 3;

      while (retryCount < maxRetries && info == null) {
        try {
          info =
              await BusApiService().getBusArrivalByRouteId(stationId, routeId);
          if (info == null) {
            retryCount++;
            logMessage(
                "⚠️ TTS 반복 작업 - 버스 정보 조회 실패 ($retryCount/$maxRetries) - 재시도 중");
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
          "🐛 [DEBUG] TTS 반복 작업 - 버스 정보 조회 성공: ${info.bus.length}개 버스 정보 받음");
      final busData = info.bus.first;
      // 여기서 models/bus_info.dart의 BusInfo로 변환
      final busInfoFromApi = BusInfo.fromBusInfoData(busData);

      // TTS 발화
      await _speakBusInfo(busInfoFromApi, busNo, stationName);

      // 버스 정보 캐시에 업데이트할 필요가 있는 경우
      // BusArrival의 BusInfo로 변환해서 전달
      final remainingTime = int.tryParse(
              busInfoFromApi.estimatedTime.replaceAll(RegExp(r'[^0-9]'), '')) ??
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
    logMessage('✅ 자동 알람 시간이 방금 지났습니다. 즉시 실행: ${todayScheduledTime.toString()}, '
        '지난 시간: ${now.difference(todayScheduledTime).inSeconds}초');
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
    AutoAlarm alarm, DateTime scheduledTime) async {
  try {
    final now = DateTime.now();
    final initialDelay = scheduledTime.difference(now);

    // 이미 시간이 지난 경우 처리
    if (initialDelay.isNegative) {
      logMessage('⚠️ 알람 시간이 이미 지났습니다. 다음 알람 시간을 계산합니다.');
      // 다음 알람 시간 계산
      final nextScheduledTime = _calculateNextScheduledTime(alarm, now);
      if (nextScheduledTime != null) {
        return _registerAutoAlarmTask(alarm, nextScheduledTime);
      }
      return false;
    }

    final inputData = {
      'alarmId': alarm.id,
      'busNo': alarm.routeNo,
      'stationName': alarm.stationName,
      'routeId': alarm.routeId,
      'stationId': alarm.stationId,
      'useTTS': alarm.useTTS,
      'remainingMinutes': 3,
      'showNotification': true,
    };

    // 이전 동일 작업 취소
    try {
      await Workmanager().cancelByUniqueName('autoAlarm_${alarm.id}');
      logMessage('✅ 기존 자동 알람 작업 취소: ${alarm.routeNo} ${alarm.stationName}');
    } catch (e) {
      logMessage('⚠️ 기존 자동 알람 작업 취소 오류 (무시): $e');
    }

    // 자동 알람 작업 등록
    await Workmanager().registerOneOffTask(
      'autoAlarm_${alarm.id}',
      'autoAlarmTask',
      initialDelay: initialDelay,
      inputData: inputData,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: false,
        requiresCharging: false,
        requiresDeviceIdle: false,
        requiresStorageNotLow: false,
      ),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      backoffPolicy: BackoffPolicy.linear,
      backoffPolicyDelay: const Duration(minutes: 1),
    );

    // 디버그 로그 추가
    logMessage('✅ 자동 알람 작업 등록 완료: ${alarm.routeNo} ${alarm.stationName}');
    logMessage('⏰ 예약 시간: $scheduledTime (${initialDelay.inMinutes}분 후)');

    // 백업 알람 등록 - 5분 후 재시도
    try {
      final backupTaskId = 'autoAlarm_backup_${alarm.id}';
      await Workmanager().cancelByUniqueName(backupTaskId);

      // 백업 알람은 원래 알람보다 5분 뒤에 실행
      final backupDelay = initialDelay + const Duration(minutes: 5);

      await Workmanager().registerOneOffTask(
        backupTaskId,
        'autoAlarmTask',
        initialDelay: backupDelay,
        inputData: inputData,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      logMessage('✅ 백업 자동 알람 작업 등록 완료: ${backupDelay.inMinutes}분 후');
    } catch (e) {
      logMessage('⚠️ 백업 알람 등록 오류 (무시): $e');
    }

    return true;
  } catch (e) {
    logMessage("❌ 자동 알람 작업 등록 실패: $e");
    return false;
  }
}

Future<void> _speakBusInfo(
    BusInfo bus, String busNo, String stationName) async {
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
  );
}
