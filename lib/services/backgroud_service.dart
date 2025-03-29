import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:daegu_bus_app/services/bus_api_service.dart';
import 'package:daegu_bus_app/utils/tts_helper.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:workmanager/workmanager.dart';
import 'package:flutter/services.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      await WakelockPlus.enable();

      final String routeId = inputData?['routeId'] ?? '';
      final String stationId = inputData?['stationId'] ?? '';
      final String stationName = inputData?['stationName'] ?? '';
      final String busNo = inputData?['busNo'] ?? '';
      final int remainingMinutes = inputData?['remainingMinutes'] ?? 0;

      final int alarmId = routeId.hashCode ^ stationId.hashCode;

      if (task == 'autoAlarmTask') {
        await TTSHelper.speak(
            "$busNo번 버스가 $stationName 정류장에 $remainingMinutes분 후 도착합니다.");

        await NotificationService().showAutoAlarmNotification(
          id: alarmId,
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          routeId: routeId,
        );

        // 실시간 추적 시작
        const MethodChannel channel =
            MethodChannel('com.example.daegu_bus_app/bus_api');

        try {
          await channel.invokeMethod('startBusMonitoring', {
            'routeId': routeId,
            'stationId': stationId,
            'stationName': stationName,
          });
          await channel.invokeMethod('registerBusArrivalReceiver');
        } catch (e) {
          print("❌ Native 호출 실패: $e");
        }

        // 반복 TTS 등록 (2분 주기)
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
          },
        );

        return true;
      }

      if (task == 'ttsRepeatingTask') {
        final info =
            await BusApiService().getBusArrivalByRouteId(stationId, routeId);
        if (info != null && info.bus.isNotEmpty) {
          final bus = info.bus.first;
          final remainingTime = bus.estimatedTime;

          if (remainingTime == '운행종료' || remainingTime.contains('곧도착')) {
            await TTSHelper.speak("$busNo번 버스가 곧 도착합니다.");
            await Workmanager().cancelByUniqueName('tts-$alarmId');
          } else {
            await TTSHelper.speak(
                "$busNo번 버스가 $stationName 정류장에 $remainingTime 후 도착 예정입니다.");
          }
        } else {
          await TTSHelper.speak("$busNo번 버스 도착 정보를 가져올 수 없습니다.");
        }

        return true;
      }

      return false;
    } catch (e) {
      print("🔴 callbackDispatcher 예외: $e");
      return false;
    } finally {
      await WakelockPlus.disable();
    }
  });
}
