import 'dart:async';
import 'dart:convert';
import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:daegu_bus_app/utils/tts_helper.dart';

/// AlarmData 모델: 알람에 필요한 정보를 저장합니다.
class AlarmData {
  final String busNo;
  final String stationName;
  final int remainingMinutes;

  AlarmData({
    required this.busNo,
    required this.stationName,
    required this.remainingMinutes,
  });

  Map<String, dynamic> toJson() => {
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
      };

  factory AlarmData.fromJson(Map<String, dynamic> json) => AlarmData(
        busNo: json['busNo'],
        stationName: json['stationName'],
        remainingMinutes: json['remainingMinutes'],
      );
}

/// 최상위 함수: 별도의 isolate에서 실행되어야 합니다.
/// 예약된 알람 데이터(SharedPreferences에 저장된)를 불러와 OS 알림과 TTS 음성 안내를 실행합니다.
@pragma('vm:entry-point')
void alarmCallback(int alarmId) async {
  final prefs = await SharedPreferences.getInstance();
  final String? alarmJson = prefs.getString('alarm_$alarmId');
  print('알람 콜백 실행: ID $alarmId, 데이터: $alarmJson');

  if (alarmJson != null) {
    final alarmData = AlarmData.fromJson(jsonDecode(alarmJson));

    final notificationService = NotificationService();
    await notificationService.initialize();
    await notificationService.showNotification(
      id: alarmId,
      busNo: alarmData.busNo,
      stationName: alarmData.stationName,
      remainingMinutes: alarmData.remainingMinutes,
    );
    print('알림 표시 완료: ${alarmData.busNo}');

    await TTSHelper.speakBusAlert(
      busNo: alarmData.busNo,
      stationName: alarmData.stationName,
      remainingMinutes: alarmData.remainingMinutes,
    );
    print('TTS 실행 완료');

    await prefs.remove('alarm_$alarmId');
    print('알람 데이터 삭제: alarm_$alarmId');
  } else {
    print('알람 데이터 없음: ID $alarmId');
  }
}

class AlarmHelper {
  static final NotificationService _notificationService = NotificationService();

  static Future<bool> setOneTimeAlarm({
    required int id,
    required DateTime alarmTime,
    required Duration preNotificationTime,
    required String busNo,
    required String stationName,
    required int remainingMinutes,
  }) async {
    final notificationTime = alarmTime.subtract(preNotificationTime);
    final prefs = await SharedPreferences.getInstance();

    final alarmData = AlarmData(
      busNo: busNo,
      stationName: stationName,
      remainingMinutes: remainingMinutes,
    );

    await prefs.setString('alarm_$id', jsonEncode(alarmData.toJson()));
    print('알람 데이터 저장: ${prefs.getString('alarm_$id')}');

    if (notificationTime.isBefore(DateTime.now())) {
      print('과거 시간 알람 즉시 실행: $notificationTime');
      await _notificationService.initialize();
      await _notificationService.showNotification(
        id: id,
        busNo: busNo,
        stationName: stationName,
        remainingMinutes: remainingMinutes,
      );
      await TTSHelper.speakBusAlert(
        busNo: busNo,
        stationName: stationName,
        remainingMinutes: remainingMinutes,
      );
      await prefs.remove('alarm_$id');
      return true;
    }

    final success = await AndroidAlarmManager.oneShotAt(
      notificationTime,
      id,
      alarmCallback,
      exact: true,
      wakeup: true,
      rescheduleOnReboot: true,
      alarmClock: true,
    );
    print('알람 예약 결과: $success, 시간: $notificationTime');
    return success;
  }

  static int getAlarmId(String busNo, String stationName) {
    return (busNo + stationName).hashCode;
  }

  static Future<bool> cancelAlarm(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('alarm_$id');
    return await AndroidAlarmManager.cancel(id);
  }
}
