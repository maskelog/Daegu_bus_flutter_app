import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:daegu_bus_app/services/bus_api_service.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../utils/simple_tts_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../screens/profile_screen.dart';
import 'alarm_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint("📱 Background 작업 시작: $task - ${DateTime.now()}");

      // 일반적인 초기화 오류 처리 개선
      try {
        // 입력 데이터 파싱 및 디버깅
        final String routeId = inputData?['routeId'] ?? '';
        final String stationId = inputData?['stationId'] ?? '';
        final String stationName = inputData?['stationName'] ?? '';
        final String busNo = inputData?['busNo'] ?? '';
        final int remainingMinutes = inputData?['remainingMinutes'] ?? 0;
        final bool showNotification = inputData?['showNotification'] ?? true;
        final bool useTTS = inputData?['useTTS'] ?? true;

        debugPrint(
            "📱 작업 파라미터: busNo=$busNo, stationName=$stationName, routeId=$routeId");

        // 알람 ID 계산
        final int alarmId = routeId.isEmpty
            ? busNo.hashCode ^ stationName.hashCode
            : routeId.hashCode ^ stationId.hashCode;

        // 자동 알람 초기화 작업 처리
        if (task == 'initAutoAlarms') {
          debugPrint("🔄 자동 알람 초기화 시작: ${DateTime.now().toString()}");

          // 최대 재시도 횟수 설정
          const int maxRetries = 3;
          int retryCount = 0;
          bool success = false;

          // 재시도 로직 구현
          while (retryCount < maxRetries && !success) {
            try {
              if (retryCount > 0) {
                debugPrint("🔄 자동 알람 초기화 재시도 #$retryCount");
                // 재시도 시 약간의 지연 추가
                await Future.delayed(Duration(seconds: 2 * retryCount));
              }

              // SharedPreferences 인스턴스 가져오기
              final prefs = await SharedPreferences.getInstance();

              final alarms = prefs.getStringList('auto_alarms') ?? [];
              debugPrint("📋 저장된 자동 알람 수: ${alarms.length}개");

              // 현재 날짜 정보 가져오기
              final now = DateTime.now();
              final currentWeekday = now.weekday; // 1-7 (월-일)
              final isWeekend =
                  currentWeekday == 6 || currentWeekday == 7; // 주말 여부
              debugPrint(
                  "📅 현재 시간: ${now.toString()}, 요일: $currentWeekday, 주말여부: $isWeekend");

              // 공휴일 목록 가져오기 - 오류 처리 개선
              List<DateTime> holidays = [];
              try {
                final alarmService = AlarmService();
                holidays = await alarmService.getHolidays(now.year, now.month);
                debugPrint("🏖️ 공휴일 목록 가져오기 성공: ${holidays.length}개");
              } catch (holidayError) {
                // 공휴일 정보 가져오기 실패해도 계속 진행
                debugPrint("⚠️ 공휴일 정보 가져오기 실패 (무시): $holidayError");
              }

              final isHoliday = holidays.any((holiday) =>
                  holiday.year == now.year &&
                  holiday.month == now.month &&
                  holiday.day == now.day);
              debugPrint("🏖️ 오늘 공휴일 여부: $isHoliday");

              int processedCount = 0;
              int skippedCount = 0;
              int registeredCount = 0;
              int errorCount = 0;

              // 최대 처리할 알람 수 제한 (오류 발생 시 모든 알람을 처리하지 않도록)
              const int maxAlarmsToProcess = 20;
              final alarmsToProcess = alarms.length > maxAlarmsToProcess
                  ? alarms.sublist(0, maxAlarmsToProcess)
                  : alarms;

              if (alarms.length > maxAlarmsToProcess) {
                debugPrint(
                    "⚠️ 알람이 너무 많아 처음 $maxAlarmsToProcess개만 처리합니다 (총: ${alarms.length}개)");
              }

              for (var json in alarmsToProcess) {
                try {
                  processedCount++;
                  final data = jsonDecode(json);
                  final autoAlarm = AutoAlarm.fromJson(data);
                  debugPrint(
                      "🔍 알람 처리 중 #$processedCount: ${autoAlarm.routeNo}번 버스, ${autoAlarm.hour}:${autoAlarm.minute}, 활성화: ${autoAlarm.isActive}");

                  if (!autoAlarm.isActive) {
                    debugPrint("⏭️ 비활성화된 자동 알람 건너뛰기: ${autoAlarm.routeNo}번 버스");
                    skippedCount++;
                    continue;
                  }

                  // 주말/공휴일 제외 체크
                  if (autoAlarm.excludeWeekends && isWeekend) {
                    debugPrint("⏭️ 주말 제외: ${autoAlarm.routeNo}번 버스 알람");
                    skippedCount++;
                    continue;
                  }
                  if (autoAlarm.excludeHolidays && isHoliday) {
                    debugPrint("⏭️ 공휴일 제외: ${autoAlarm.routeNo}번 버스 알람");
                    skippedCount++;
                    continue;
                  }

                  // 반복 요일 체크
                  if (!autoAlarm.repeatDays.contains(currentWeekday)) {
                    debugPrint(
                        "⏭️ 반복 요일 제외: ${autoAlarm.routeNo}번 버스 알람, 설정 요일: ${autoAlarm.repeatDays}");
                    skippedCount++;
                    continue;
                  }

                  // 오늘의 예약 시간 계산
                  DateTime scheduledTime = DateTime(
                    now.year,
                    now.month,
                    now.day,
                    autoAlarm.hour,
                    autoAlarm.minute,
                  );
                  debugPrint("⏰ 예약 시간 계산: ${scheduledTime.toString()}");

                  // 이미 지난 시간이면 다음 반복 요일로 설정
                  if (scheduledTime.isBefore(now)) {
                    debugPrint("⏰ 이미 지난 시간, 다음 반복 요일 찾기 시작");
                    // 다음 반복 요일 찾기
                    int daysToAdd = 1;
                    while (daysToAdd <= 7) {
                      final nextDate = now.add(Duration(days: daysToAdd));
                      final nextWeekday = nextDate.weekday;
                      debugPrint(
                          "🔍 다음 날짜 확인: ${nextDate.toString()}, 요일: $nextWeekday");

                      if (autoAlarm.repeatDays.contains(nextWeekday)) {
                        scheduledTime = DateTime(
                          nextDate.year,
                          nextDate.month,
                          nextDate.day,
                          autoAlarm.hour,
                          autoAlarm.minute,
                        );
                        debugPrint(
                            "✅ 다음 유효 시간 발견: $daysToAdd일 후, ${scheduledTime.toString()}");
                        break;
                      }
                      daysToAdd++;
                    }
                  }

                  final initialDelay = scheduledTime.difference(now);
                  debugPrint(
                      "⏱️ 설정될 지연 시간: ${initialDelay.inHours}시간 ${initialDelay.inMinutes % 60}분 ${initialDelay.inSeconds % 60}초");

                  if (initialDelay.inSeconds <= 0) {
                    debugPrint(
                        "⏭️ 이미 지난 시간으로 계산됨: ${autoAlarm.routeNo}번 버스 알람, 지연: ${initialDelay.inSeconds}초");
                    skippedCount++;
                    continue;
                  }

                  final inputData = {
                    'alarmId': autoAlarm.id,
                    'busNo': autoAlarm.routeNo,
                    'stationName': autoAlarm.stationName,
                    'remainingMinutes': 3, // 기본값으로 설정
                    'routeId': autoAlarm.routeId,
                    'isAutoAlarm': true,
                    'showNotification': true,
                    'startTracking': true,
                    'stationId': autoAlarm.stationId,
                    'shouldFetchRealtime': true,
                    'useTTS': autoAlarm.useTTS,
                    'currentStation': '',
                    'notificationTime': scheduledTime.millisecondsSinceEpoch,
                    'speakerMode': 1,
                  };

                  // 기존 작업이 있다면 취소
                  await Workmanager()
                      .cancelByUniqueName('autoAlarm_${autoAlarm.id}');
                  debugPrint("🔄 기존 알람 취소: autoAlarm_${autoAlarm.id}");

                  // 새로운 작업 등록
                  await Workmanager().registerOneOffTask(
                    'autoAlarm_${autoAlarm.id}',
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
                  );
                  registeredCount++;

                  debugPrint(
                      "✅ 자동 알람 등록 성공: ${autoAlarm.routeNo}, ${autoAlarm.stationName}, ${initialDelay.inMinutes}분 후 실행 (${scheduledTime.toString()})");
                } catch (e) {
                  debugPrint("❌ 개별 자동 알람 초기화 오류: $e");
                  errorCount++;
                  // 개별 알람 실패는 무시하고 계속 진행
                }
              }

              debugPrint(
                  "📊 자동 알람 초기화 통계: 총 ${alarms.length}개, 처리 $processedCount개, 스킵 $skippedCount개, 등록 $registeredCount개, 오류 $errorCount개");
              debugPrint("✅ 자동 알람 초기화 완료: ${DateTime.now().toString()}");

              // 적어도 하나의 알람이 성공적으로 등록되었거나, 모든 알람이 정상적으로 처리된 경우 성공으로 간주
              success = registeredCount > 0 ||
                  (processedCount == alarms.length && errorCount == 0);
              debugPrint("🚦 작업 상태: ${success ? '성공' : '실패'}");

              if (!success && retryCount < maxRetries - 1) {
                debugPrint("⚠️ 자동 알람 초기화 부분 실패, 재시도 예정...");
              }
            } catch (e) {
              retryCount++;
              debugPrint("❌ 자동 알람 초기화 시도 #$retryCount 실패: $e");

              if (retryCount >= maxRetries) {
                debugPrint("🛑 최대 재시도 횟수 도달, 작업 실패");
                return false;
              }
            }
          }

          // 작업 성공 여부 반환
          return success;
        }

        // 자동 알람 작업 처리
        if (task == 'autoAlarmTask') {
          debugPrint("🔔 자동 알람 작업 실행");
          debugPrint("📱 입력 데이터: $inputData");

          // TTS 초기화 시도
          if (useTTS) {
            try {
              debugPrint("🔊 TTS 초기화 시작");
              await SimpleTTSHelper.initialize();
              debugPrint("✅ TTS 엔진 초기화 성공");

              // 스피커 모드 설정
              try {
                debugPrint("🔊 스피커 모드 설정 시작");
                const MethodChannel audioChannel =
                    MethodChannel('com.example.daegu_bus_app/audio');
                final result =
                    await audioChannel.invokeMethod('setSpeakerMode', {
                  'mode': 1, // 스피커 모드로 설정
                  'force': true, // 강제로 모드 변경
                });
                debugPrint("✅ 스피커 모드 설정 성공: $result");

                // 스피커 모드 확인
                final currentMode =
                    await audioChannel.invokeMethod('getSpeakerMode');
                debugPrint("📱 현재 스피커 모드: $currentMode");
              } catch (speakerError) {
                debugPrint("❌ 스피커 모드 설정 오류: $speakerError");
                // 스피커 모드 설정 실패 시에도 계속 진행
              }

              // speakBusArriving 메서드 사용
              debugPrint("🔊 TTS 발화 시작: $busNo번 버스 도착 알림");
              await SimpleTTSHelper.speakBusArriving(busNo, stationName);
              debugPrint("✅ TTS 발화 성공");
            } catch (ttsError) {
              debugPrint("❌ TTS 오류, 기본 speak 메서드로 시도: $ttsError");
              try {
                debugPrint("🔊 기본 TTS 발화 시도");
                await SimpleTTSHelper.speak(
                    "$busNo번 버스가 $stationName 정류장에 $remainingMinutes분 후 도착합니다.");
                debugPrint("✅ 기본 TTS 발화 성공");
              } catch (fallbackError) {
                debugPrint("❌ 기본 TTS도 실패: $fallbackError");
              }
            }
          }

          // 알림 표시
          if (showNotification) {
            try {
              debugPrint("🔔 알림 표시 시작");
              await NotificationService().showAutoAlarmNotification(
                id: alarmId,
                busNo: busNo,
                stationName: stationName,
                remainingMinutes: remainingMinutes,
                routeId: routeId,
              );
              debugPrint("✅ 알림 표시 성공");
            } catch (notifError) {
              debugPrint("❌ 알림 표시 오류: $notifError");
            }
          }

          // 실시간 추적 시작
          const MethodChannel channel =
              MethodChannel('com.example.daegu_bus_app/bus_api');

          try {
            debugPrint("📱 네이티브 TTS 추적 시작");
            // 먼저 네이티브 TTS 추적 시작
            await channel.invokeMethod('startTtsTracking', {
              'routeId': routeId,
              'stationId': stationId,
              'busNo': busNo,
              'stationName': stationName,
            });
            debugPrint("✅ 네이티브 TTS 추적 시작 성공");

            // 버스 모니터링 시작
            debugPrint("📱 버스 모니터링 시작");
            await channel.invokeMethod('startBusMonitoring', {
              'routeId': routeId,
              'stationId': stationId,
              'stationName': stationName,
            });
            debugPrint("✅ 버스 모니터링 서비스 시작 성공");

            // 버스 도착 수신기 등록
            debugPrint("📱 버스 도착 수신기 등록");
            await channel.invokeMethod('registerBusArrivalReceiver', {
              'stationId': stationId,
              'stationName': stationName,
              'routeId': routeId,
            });
            debugPrint("✅ 버스 도착 수신기 등록 성공");
          } catch (e) {
            debugPrint("❌ 네이티브 호출 실패: $e");
          }

          // 반복 TTS 등록 (2분 주기)
          try {
            final ttsTaskId = 'tts-$alarmId';
            debugPrint("⏱️ 반복 TTS 작업 등록 시작: $ttsTaskId");
            await Workmanager().registerPeriodicTask(
              ttsTaskId,
              'ttsRepeatingTask',
              frequency: const Duration(minutes: 2),
              inputData: {
                'busNo': busNo,
                'stationName': stationName,
                'routeId': routeId,
                'stationId': stationId,
                'useTTS': useTTS,
              },
            );
            debugPrint("✅ 반복 TTS 작업 등록 성공: $ttsTaskId");
          } catch (wmError) {
            debugPrint("❌ 반복 TTS 작업 등록 실패: $wmError");
          }

          return true;
        }

        // 반복 TTS 작업 처리
        if (task == 'ttsRepeatingTask') {
          debugPrint("🔄 반복 TTS 작업 실행");
          debugPrint("📱 입력 데이터: $inputData");

          try {
            // 입력 데이터에서 필요한 정보 추출
            final String busNo = inputData?['busNo'] ?? '';
            final String stationName = inputData?['stationName'] ?? '';
            final String routeId = inputData?['routeId'] ?? '';
            final String stationId = inputData?['stationId'] ?? '';
            final bool useTTS = inputData?['useTTS'] ?? true;

            if (busNo.isEmpty || stationId.isEmpty || routeId.isEmpty) {
              debugPrint(
                  "❌ 필수 파라미터 누락: busNo=$busNo, stationId=$stationId, routeId=$routeId");
              return false;
            }

            final info = await BusApiService()
                .getBusArrivalByRouteId(stationId, routeId);

            if (info != null && info.bus.isNotEmpty) {
              final bus = info.bus.first;
              final remainingTime = bus.estimatedTime;
              debugPrint("🚌 버스 정보 가져옴: $busNo번 버스, 남은시간=$remainingTime");

              if (useTTS) {
                // TTS 초기화 확인
                await SimpleTTSHelper.initialize();

                if (remainingTime == '운행종료' || remainingTime.contains('곧도착')) {
                  // 버스가 곧 도착하거나 운행 종료된 경우
                  await SimpleTTSHelper.speakBusArriving(busNo, stationName);
                  // 반복 작업 취소
                  await Workmanager().cancelByUniqueName('tts-$alarmId');
                  debugPrint("🔄 버스 도착, 반복 TTS 작업 취소");
                } else {
                  // 버스가 아직 도착하지 않은 경우
                  final int mins = int.tryParse(
                          remainingTime.replaceAll(RegExp(r'[^0-9]'), '')) ??
                      0;
                  // 정류장 개수 추출
                  final remainingStops = int.tryParse(bus.remainingStations
                          .replaceAll(RegExp(r'[^0-9]'), '')) ??
                      0;

                  await SimpleTTSHelper.speakBusAlert(
                    busNo: busNo,
                    stationName: stationName,
                    remainingMinutes: mins,
                    currentStation: bus.currentStation,
                    remainingStops: remainingStops, // 남은 정류장 개수 전달
                  );
                  debugPrint("🔊 반복 TTS 발화 성공");
                }
              }
            } else {
              debugPrint("⚠️ 버스 정보 없음: $busNo번 버스");
              if (useTTS) {
                await SimpleTTSHelper.speak("$busNo번 버스 도착 정보를 가져올 수 없습니다.");
                debugPrint("🔊 오류 메시지 TTS 발화");
              }
            }

            return true;
          } catch (ttsTaskError) {
            debugPrint("🔄 반복 TTS 작업 실행 오류: $ttsTaskError");
            return false;
          }
        }

        // 기본적으로 처리하지 못한 작업은 실패 반환
        debugPrint("⚠️ 처리되지 않은 작업 유형: $task");
        return false;
      } catch (e) {
        debugPrint("❗ 작업 내부 처리 오류: $e");
        return false;
      }
    } catch (e) {
      debugPrint("🔴 callbackDispatcher 예외: $e");
      return false;
    } finally {
      debugPrint("💤 Background 작업 종료: $task - ${DateTime.now()}");
    }
  });
}
