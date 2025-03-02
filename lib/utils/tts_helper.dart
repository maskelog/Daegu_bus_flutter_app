import 'package:flutter_tts/flutter_tts.dart';

class TTSHelper {
  static final FlutterTts _flutterTts = FlutterTts();

  /// TTS 초기화: 언어, 속도, 볼륨, 피치 등을 설정합니다.
  static Future<void> initialize() async {
    await _flutterTts.setLanguage("ko-KR"); // 한국어 설정
    await _flutterTts.setSpeechRate(0.5); // 말하기 속도 (0.0~1.0)
    await _flutterTts.setVolume(1.0); // 볼륨 (0.0~1.0)
    await _flutterTts.setPitch(1.0); // 피치 (0.5~2.0)
  }

  /// 버스 도착 알림 메시지를 음성으로 출력합니다.
  /// [busNo]: 버스 번호, [stationName]: 정류장 이름, [remainingMinutes]: 남은 시간(분)
  /// [currentStation]: 현재 버스 위치 (n번째 전 출발)
  static Future<void> speakBusAlert({
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String? currentStation,
  }) async {
    String message;

    if (remainingMinutes <= 0) {
      message = '$busNo번 버스가 $stationName을(를) 지나갔습니다.';
    } else if (remainingMinutes <= 1) {
      message = '$busNo번 버스가 $stationName에 곧 도착합니다.';
    } else {
      // 기본 메시지 형식: "[버스번호]번 버스가 약 [남은시간]분 후 도착합니다."
      message = '$busNo번 버스가 약 $remainingMinutes분 후 도착합니다.';

      // 현재 정류장 정보가 있으면 추가
      if (currentStation != null && currentStation.isNotEmpty) {
        // "전정류장" 또는 "1번째 전" 같은 형식 확인
        if (currentStation == "전정류장") {
          message += ' 전 정류장에서 출발했습니다.';
        } else if (currentStation.contains("전")) {
          message += ' 현재 $currentStation에서 출발했습니다.';
        } else {
          message += ' 현재 $currentStation에 있습니다.';
        }
      }
    }

    await _flutterTts.speak(message);
  }

  /// 알람 설정 메시지를 음성으로 출력합니다.
  /// [busNo]: 버스 번호
  static Future<void> speakAlarmSet(String busNo) async {
    String message = '$busNo번 승차알람이 설정되었습니다.';
    await _flutterTts.speak(message);
  }

  /// 알람 해제 메시지를 음성으로 출력합니다.
  /// [busNo]: 버스 번호
  static Future<void> speakAlarmCancel(String busNo) async {
    String message = '$busNo번 승차알람이 해제되었습니다.';
    await _flutterTts.speak(message);
  }

  /// TTS를 중지합니다.
  static Future<void> stop() async {
    await _flutterTts.stop();
  }
}
