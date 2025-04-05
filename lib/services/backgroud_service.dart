import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:daegu_bus_app/services/bus_api_service.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import '../utils/simple_tts_helper.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      // CPU를 깨우기 위해 WakelockPlus 활성화
      await WakelockPlus.enable();
      debugPrint("📱 Background 작업 시작: $task");

      // 입력 데이터 파싱 및 디버깅
      final String routeId = inputData?['routeId'] ?? '';
      final String stationId = inputData?['stationId'] ?? '';
      final String stationName = inputData?['stationName'] ?? '';
      final String busNo = inputData?['busNo'] ?? '';
      final int remainingMinutes = inputData?['remainingMinutes'] ?? 0;
      final bool showNotification = inputData?['showNotification'] ?? true;
      final bool useTTS = inputData?['useTTS'] ?? true;

      debugPrint("📱 작업 파라미터: busNo=$busNo, stationName=$stationName, routeId=$routeId");

      // 알람 ID 계산
      final int alarmId = routeId.isEmpty ? 
          busNo.hashCode ^ stationName.hashCode : 
          routeId.hashCode ^ stationId.hashCode;

      // 자동 알람 작업 처리
      if (task == 'autoAlarmTask') {
        debugPrint("🔔 자동 알람 작업 실행");
        
        // TTS 초기화 시도
        if (useTTS) {
          try {
            await SimpleTTSHelper.initialize();
            debugPrint("🔊 TTS 엔진 초기화 성공");

            // speakBusArriving 메서드 사용 (신규 메서드)
            await SimpleTTSHelper.speakBusArriving(busNo, stationName);
            debugPrint("🔊 버스 도착 TTS 발화 성공");
          } catch (ttsError) {
            debugPrint("🔊 TTS 오류, 기본 speak 메서드로 시도: $ttsError");
            try {
              await SimpleTTSHelper.speak("$busNo번 버스가 $stationName 정류장에 $remainingMinutes분 후 도착합니다.");
            } catch (fallbackError) {
              debugPrint("🔊 기본 TTS도 실패: $fallbackError");
            }
          }
        }

        // 알림 표시
        if (showNotification) {
          try {
            await NotificationService().showAutoAlarmNotification(
              id: alarmId,
              busNo: busNo,
              stationName: stationName,
              remainingMinutes: remainingMinutes,
              routeId: routeId,
            );
            debugPrint("🔔 자동 알람 알림 표시 성공");
          } catch (notifError) {
            debugPrint("🔔 알림 표시 오류: $notifError");
          }
        }

        // 실시간 추적 시작
        const MethodChannel channel =
            MethodChannel('com.example.daegu_bus_app/bus_api');

        try {
          // 먼저 네이티브 TTS 추적 시작
          await channel.invokeMethod('startTtsTracking', {
            'routeId': routeId,
            'stationId': stationId,
            'busNo': busNo,
            'stationName': stationName,
          });
          debugPrint("📱 네이티브 TTS 추적 시작 성공");
          
          // 버스 모니터링 시작
          await channel.invokeMethod('startBusMonitoring', {
            'routeId': routeId,
            'stationId': stationId,
            'stationName': stationName,
          });
          debugPrint("📱 버스 모니터링 서비스 시작 성공");
          
          // 버스 도착 수신기 등록
          await channel.invokeMethod('registerBusArrivalReceiver', {
            'stationId': stationId,
            'stationName': stationName,
            'routeId': routeId,
          });
          debugPrint("📱 버스 도착 수신기 등록 성공");
        } catch (e) {
          debugPrint("❌ 네이티브 호출 실패: $e");
        }

        // 반복 TTS 등록 (2분 주기)
        try {
          final ttsTaskId = 'tts-$alarmId';
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
          debugPrint("⏱️ 반복 TTS 작업 등록 성공: $ttsTaskId");
        } catch (wmError) {
          debugPrint("⏱️ 반복 TTS 작업 등록 실패: $wmError");
        }

        return true;
      }

      // 반복 TTS 작업 처리
      if (task == 'ttsRepeatingTask') {
        debugPrint("🔄 반복 TTS 작업 실행");
        
        try {
          final info =
              await BusApiService().getBusArrivalByRouteId(stationId, routeId);
              
          if (info != null && info.bus.isNotEmpty) {
            final bus = info.bus.first;
            final remainingTime = bus.estimatedTime;
            debugPrint("🚌 버스 정보 가져옴: 남은시간=$remainingTime");

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
                final int mins = int.tryParse(remainingTime.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
                await SimpleTTSHelper.speakBusAlert(
                  busNo: busNo,
                  stationName: stationName,
                  remainingMinutes: mins,
                  currentStation: bus.currentStation,
                );
                debugPrint("🔊 반복 TTS 발화 성공");
              }
            }
          } else {
            debugPrint("⚠️ 버스 정보 없음");
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

      return false;
    } catch (e) {
      debugPrint("🔴 callbackDispatcher 예외: $e");
      return false;
    } finally {
      await WakelockPlus.disable();
      debugPrint("💤 Background 작업 종료: $task");
    }
  });
}
