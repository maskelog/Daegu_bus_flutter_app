import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'notification_helper.dart';

// 이 함수는 최상위 함수(isolate에서 실행되어야 함)
void alarmCallback(int alarmId) {
  // 알람 ID에 따라 다른 작업 수행 가능
  NotificationHelper.showNotification(
    id: alarmId,
    title: '버스 도착 알림',
    body: '버스가 곧 도착합니다!',
  );

  print('알람 실행: $alarmId');
}

class AlarmHelper {
  // 일회성 알람 설정
  static Future<bool> setOneTimeAlarm({
    required int id,
    required DateTime alarmTime,
    required Duration preNotificationTime,
  }) async {
    DateTime notificationTime = alarmTime.subtract(preNotificationTime);

    // 이미 지난 시간이면 바로 알림
    if (notificationTime.isBefore(DateTime.now())) {
      NotificationHelper.showNotification(
        id: id,
        title: '버스 도착 알림',
        body: '버스가 곧 도착합니다!',
      );
      return true;
    }

    bool success = await AndroidAlarmManager.oneShotAt(
      notificationTime,
      id,
      alarmCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
    );

    return success;
  }

  // 알람 취소
  static Future<bool> cancelAlarm(int id) async {
    return await AndroidAlarmManager.cancel(id);
  }
}
