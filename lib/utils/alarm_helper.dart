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
void alarmCallback(int alarmId) async {
  final prefs = await SharedPreferences.getInstance();
  final String? alarmJson = prefs.getString('alarm_$alarmId');
  if (alarmJson != null) {
    final alarmData = AlarmData.fromJson(jsonDecode(alarmJson));

    // NotificationService 인스턴스 생성 및 사용
    final notificationService = NotificationService();
    await notificationService.initialize(); // 초기화 필요

    // OS 알림 표시
    await notificationService.showNotification(
      id: alarmId,
      busNo: alarmData.busNo,
      stationName: alarmData.stationName,
      remainingMinutes: alarmData.remainingMinutes,
    );

    // TTS 음성 안내 실행
    await TTSHelper.speakBusAlert(
      busNo: alarmData.busNo,
      stationName: alarmData.stationName,
      remainingMinutes: alarmData.remainingMinutes,
    );

    print('알람 실행: $alarmId');
    // 사용 후 알람 데이터 삭제
    await prefs.remove('alarm_$alarmId');
  } else {
    print('알람 데이터가 없습니다. 알람 ID: $alarmId');
  }
}

/// AlarmHelper 클래스: AndroidAlarmManager를 사용하여 알람을 예약하거나 취소합니다.
class AlarmHelper {
  // NotificationService 인스턴스 생성
  static final NotificationService _notificationService = NotificationService();

  /// 일회성 알람 설정
  /// [alarmTime]은 버스 도착 예정 시각이며, [preNotificationTime]을 뺀 시각에 알람이 울립니다.
  /// 예약 시, [busNo], [stationName], [remainingMinutes] 데이터를 저장하여 예약된 시각에
  /// alarmCallback()에서 사용하도록 합니다.
  static Future<bool> setOneTimeAlarm({
    required int id,
    required DateTime alarmTime,
    required Duration preNotificationTime,
    required String busNo,
    required String stationName,
    required int remainingMinutes,
  }) async {
    // 예약 알람 시각 계산
    DateTime notificationTime = alarmTime.subtract(preNotificationTime);

    // 알람 데이터를 SharedPreferences에 저장 (키: 'alarm_<id>')
    final alarmData = AlarmData(
      busNo: busNo,
      stationName: stationName,
      remainingMinutes: remainingMinutes,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('alarm_$id', jsonEncode(alarmData.toJson()));

    // 예약 시간이 이미 지난 경우, 즉시 알림 실행 후 데이터를 삭제합니다.
    if (notificationTime.isBefore(DateTime.now())) {
      // NotificationService 초기화 및 사용
      await _notificationService.initialize();
      await _notificationService.showNotification(
        id: id,
        busNo: busNo,
        stationName: stationName,
        remainingMinutes: remainingMinutes,
      );
      await prefs.remove('alarm_$id');
      return true;
    }

    // 예약된 시각에 alarmCallback()을 호출하도록 알람 예약
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

  /// 고정된 알람 ID 생성 함수: 버스 번호와 정류장 이름을 조합하여 생성합니다.
  static int getAlarmId(String busNo, String stationName) {
    return (busNo + stationName).hashCode;
  }

  /// 예약된 알람 취소
  static Future<bool> cancelAlarm(int id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('alarm_$id');
    return await AndroidAlarmManager.cancel(id);
  }
}
