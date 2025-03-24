import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:workmanager/workmanager.dart';

void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == 'autoAlarmTask') {
      final bool isAutoAlarm = inputData?['isAutoAlarm'] ?? false;

      if (isAutoAlarm) {
        final int alarmId = inputData?['alarmId'] ?? 0;
        final String busNo = inputData?['busNo'] ?? '';
        final String stationName = inputData?['stationName'] ?? '';
        final int remainingMinutes = inputData?['remainingMinutes'] ?? 0;
        final String routeId = inputData?['routeId'] ?? '';

        // 자동 알람 실행 - 사용자에게 먼저 알림
        await NotificationService().showAutoAlarmNotification(
          id: alarmId,
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          routeId: routeId,
        );

        // 필요한 경우 실제 도착 알람 설정 로직
        // 이 부분은 플랫폼별 구현 필요
      }
      return true;
    }
    return false;
  });
}
