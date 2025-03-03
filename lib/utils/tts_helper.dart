import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TTSHelper {
  static final FlutterTts _flutterTts = FlutterTts();
  static bool _isInitialized = false;
  static bool _isSpeaking = false;

  /// TTS 초기화: 언어, 속도, 볼륨, 피치 등을 설정합니다.
  static Future<void> initialize() async {
    try {
      await _flutterTts.setLanguage("ko-KR"); // 한국어 설정
      await _flutterTts.setSpeechRate(0.5); // 말하기 속도 (0.0~1.0)
      await _flutterTts.setVolume(1.0); // 볼륨 (0.0~1.0)
      await _flutterTts.setPitch(1.0); // 피치 (0.5~2.0)

      // 완료 콜백 설정
      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        debugPrint('TTS 완료');
      });

      // 에러 콜백 설정
      _flutterTts.setErrorHandler((error) {
        debugPrint('TTS 오류 발생: $error');
        _isSpeaking = false;
      });

      _isInitialized = true;
      debugPrint('TTS 초기화 완료');
    } catch (e) {
      debugPrint('TTS 초기화 오류: $e');
      _isInitialized = false;
    }
  }

  /// 텍스트를 음성으로 출력합니다.
  static Future<void> speak(String message) async {
    if (!_isInitialized) {
      debugPrint('TTS가 초기화되지 않았습니다. 초기화 시도...');
      await initialize();
    }

    // 이미 말하고 있으면 중지
    if (_isSpeaking) {
      await stop();
    }

    debugPrint('TTS 발화 시도: $message');
    _isSpeaking = true;

    try {
      await _flutterTts.speak(message);
    } catch (e) {
      debugPrint('TTS 발화 오류: $e');
      _isSpeaking = false;
    }
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

    try {
      if (remainingMinutes <= 0) {
        message = '$busNo번 버스가 $stationName을 지나갔습니다.';
      } else if (remainingMinutes <= 1) {
        message = '$busNo번 버스가 $stationName에 곧 도착합니다. 준비하세요.';
      } else {
        message = '$busNo번 버스가 약 $remainingMinutes분 후 $stationName에 도착합니다.';

        if (currentStation != null && currentStation.isNotEmpty) {
          if (currentStation == "전정류장") {
            message += ' 전 정류장에서 출발했습니다.';
          } else if (currentStation.contains("전")) {
            message += ' 현재 $currentStation에서 출발했습니다.';
          } else {
            message += ' 현재 $currentStation에 있습니다.';
          }
        }
      }

      debugPrint('버스 알림 TTS 메시지: $message');
      await speak(message);
    } catch (e) {
      debugPrint('버스 알림 TTS 오류: $e');
    }
  }

  /// 알람 설정 메시지를 음성으로 출력합니다.
  /// [busNo]: 버스 번호
  static Future<void> speakAlarmSet(String busNo) async {
    String message = '$busNo번 승차알람이 설정되었습니다.';
    await speak(message);
  }

  /// 알람 해제 메시지를 음성으로 출력합니다.
  /// [busNo]: 버스 번호
  static Future<void> speakAlarmCancel(String busNo) async {
    String message = '$busNo번 승차알람이 해제되었습니다.';
    await speak(message);
  }

  /// TTS를 중지합니다.
  static Future<void> stop() async {
    await _flutterTts.stop();
    _isSpeaking = false;
  }
}
