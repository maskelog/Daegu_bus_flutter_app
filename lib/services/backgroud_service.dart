import 'package:daegu_bus_app/main.dart';
import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:daegu_bus_app/services/bus_api_service.dart';
import 'package:workmanager/workmanager.dart';
import '../utils/simple_tts_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
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
      final int alarmId = inputData?['alarmId'] as int? ?? 0;
      final String stationId = inputData?['stationId'] ?? '';
      final int remainingMinutes = inputData?['remainingMinutes'] as int? ?? 3;

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
      final prefs = await SharedPreferences.getInstance();
      final alarms = prefs.getStringList('auto_alarms') ?? [];

      final now = DateTime.now();
      final currentWeekday = now.weekday;
      final isWeekend = currentWeekday == 6 || currentWeekday == 7;

      int processedCount = 0;
      int registeredCount = 0;

      for (var json in alarms) {
        final data = jsonDecode(json);
        final autoAlarm = AutoAlarm.fromJson(data);

        if (!_shouldProcessAlarm(autoAlarm, currentWeekday, isWeekend)) {
          continue;
        }

        final scheduledTime = _calculateNextScheduledTime(autoAlarm, now);
        if (scheduledTime == null) continue;

        final success = await _registerAutoAlarmTask(autoAlarm, scheduledTime);
        if (success) registeredCount++;
        processedCount++;
      }

      logMessage("📊 자동 알람 초기화 완료: 처리 $processedCount개, 등록 $registeredCount개");
      return registeredCount > 0;
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

    // AlarmService 인스턴스 생성
    final alarmService = AlarmService();

    // 알람 설정 - 알람 자체는 설정하지만 즉시 알림이 울리지 않도록
    final bool success = await alarmService.setOneTimeAlarm(
      busNo,
      stationName,
      remainingMinutes,
      routeId: routeId,
      useTTS: useTTS,
      isImmediateAlarm: false,
    );

    if (success) {
      logMessage("✅ 알람 서비스를 통한 알람 설정 성공: $busNo");
    } else {
      logMessage("⚠️ 알람 서비스를 통한 알람 설정 실패: $busNo");
    }

    // 알람 설정 시각에 TTS 및 알림 실행 (즉시 모니터링 시작하지 않음)
    if (useTTS) {
      await SimpleTTSHelper.initialize();
      await SimpleTTSHelper.speak("$busNo번 버스 $stationName 승차 알람이 작동합니다.");
    }

    // 알람 ID로 알림 표시 - 간단한 알림만 표시
    await NotificationService().showNotification(
      id: alarmId,
      busNo: busNo,
      stationName: stationName,
      remainingMinutes: remainingMinutes,
      currentStation: '',
      isOngoing: false, // 지속적인 알림이 아닌 일회성 알림으로 설정
    );

    // 필요한 경우에만 조건부로 버스 모니터링 서비스 시작
    // (즉시 추적하지 않고 사용자가 명시적으로 요청한 경우에만)
    final prefs = await SharedPreferences.getInstance();
    final bool startMonitoring =
        prefs.getBool('auto_start_monitoring') ?? false;

    if (startMonitoring) {
      logMessage("🔔 사용자 설정에 따라 버스 모니터링 서비스 시작");
      await alarmService.startBusMonitoringService(
        stationId: stationId,
        stationName: stationName,
        routeId: routeId,
        busNo: busNo,
      );
    } else {
      logMessage("🔔 즉시 모니터링 기능이 비활성화되어 있습니다");
    }

    logMessage("✅ 자동 알람 작동 완료: $busNo");
    return true;
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
      final info =
          await BusApiService().getBusArrivalByRouteId(stationId, routeId);
      if (info == null || info.bus.isEmpty) {
        await SimpleTTSHelper.speak("$busNo번 버스 도착 정보를 가져올 수 없습니다.");
        return false;
      }

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
  DateTime scheduledTime = DateTime(
    now.year,
    now.month,
    now.day,
    alarm.hour,
    alarm.minute,
  );

  if (scheduledTime.isBefore(now)) {
    int daysToAdd = 1;
    while (daysToAdd <= 7) {
      final nextDate = now.add(Duration(days: daysToAdd));
      if (alarm.repeatDays.contains(nextDate.weekday)) {
        return DateTime(
          nextDate.year,
          nextDate.month,
          nextDate.day,
          alarm.hour,
          alarm.minute,
        );
      }
      daysToAdd++;
    }
    return null;
  }
  return scheduledTime;
}

Future<bool> _registerAutoAlarmTask(
    AutoAlarm alarm, DateTime scheduledTime) async {
  try {
    final now = DateTime.now();
    final initialDelay = scheduledTime.difference(now);

    if (initialDelay.isNegative) return false;

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
    await Workmanager().cancelByUniqueName('autoAlarm_${alarm.id}');

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
    );

    // 디버그 로그 추가
    logMessage('✅ 자동 알람 작업 등록 완료: ${alarm.routeNo} ${alarm.stationName}');
    logMessage('⏰ 예약 시간: $scheduledTime (${initialDelay.inMinutes}분 후)');

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
