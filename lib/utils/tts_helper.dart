import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TTSHelper {
  static final FlutterTts _flutterTts = FlutterTts();
  static bool _isInitialized = false;
  static bool _isSpeaking = false;
  static bool _isPrioritySpeaking = false;

  /// TTS 초기화: 언어, 속도, 볼륨, 피치 등을 설정합니다.
  static Future<void> initialize() async {
    try {
      await _flutterTts.setLanguage("ko-KR"); // 한국어 설정
      await _flutterTts.setSpeechRate(0.5); // 말하기 속도 (0.0~1.0)
      await _flutterTts.setVolume(1.0); // 볼륨 (0.0~1.0)
      await _flutterTts.setPitch(1.0); // 피치 (0.5~2.0)

      // 백그라운드에서 작동하도록 설정 (안드로이드 전용)
      if (Platform.isAndroid) {
        await _flutterTts.setQueueMode(1); // 큐 모드 설정 (이전 음성 완료 후 실행)
        await _flutterTts.setSharedInstance(true); // 공유 인스턴스 사용 (iOS)
      }

      // 완료 콜백 설정
      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        _isPrioritySpeaking = false;
        debugPrint('TTS 완료');
      });

      // 에러 콜백 설정
      _flutterTts.setErrorHandler((error) {
        debugPrint('TTS 오류 발생: $error');
        _isSpeaking = false;
        _isPrioritySpeaking = false;
      });

      // 현재 엔진 상태 출력
      final engines = await _flutterTts.getEngines;
      debugPrint('사용 가능한 TTS 엔진: $engines');

      // 언어 설정 확인 대신 사용 가능한 언어 목록 확인
      try {
        final languages = await _flutterTts.getLanguages;
        debugPrint('사용 가능한 TTS 언어: $languages');

        // 한국어 지원 확인
        final koSupported = languages.toString().contains('ko') ||
            languages.toString().contains('ko-KR');
        debugPrint('한국어 TTS 지원 여부: $koSupported');
      } catch (e) {
        debugPrint('TTS 언어 목록 확인 오류: $e');
      }

      _isInitialized = true;
      debugPrint('TTS 초기화 완료');
    } catch (e) {
      debugPrint('TTS 초기화 오류: $e');
      _isInitialized = false;
    }
  }

  /// TTS 엔진이 초기화되었는지 확인하고, 필요시 재초기화합니다.
  static Future<bool> ensureInitialized() async {
    debugPrint('TTS 초기화 상태 확인: $_isInitialized');

    if (!_isInitialized) {
      try {
        await initialize();
        debugPrint('TTS 초기화 완료: $_isInitialized');
        return _isInitialized;
      } catch (e) {
        debugPrint('TTS 재초기화 실패: $e');
        return false;
      }
    }

    // 추가 검증
    try {
      final available = await _flutterTts.isLanguageAvailable("ko-KR");
      debugPrint('한국어 TTS 가용성: $available');

      if (available != 1) {
        debugPrint('한국어 TTS 불가능, 재초기화 시도');
        await initialize();
      }

      return _isInitialized;
    } catch (e) {
      debugPrint('TTS 언어 확인 오류: $e');
      return _isInitialized;
    }
  }

  /// 텍스트를 음성으로 출력합니다.
  static Future<void> speak(String message, {bool priority = false}) async {
    // TTS 엔진 초기화 확인
    final initialized = await ensureInitialized();
    if (!initialized) {
      debugPrint('TTS 엔진 초기화에 실패하여 발화를 건너뜁니다: $message');
      return;
    }

    // 우선순위 발화가 아니고, 현재 우선순위 발화 중이면 무시
    if (!priority && _isPrioritySpeaking) {
      debugPrint('우선순위 TTS가 발화 중이므로 요청 무시: $message');
      return;
    }

    // 이미 말하고 있으면 중지 (우선순위 발화인 경우)
    if (_isSpeaking && (priority || !_isPrioritySpeaking)) {
      await stop();
    }

    debugPrint('TTS 발화 시도: $message${priority ? " (우선순위)" : ""}');
    _isSpeaking = true;
    if (priority) {
      _isPrioritySpeaking = true;
    }

    try {
      await _flutterTts.speak(message);
    } catch (e) {
      debugPrint('TTS 발화 오류: $e');
      _isSpeaking = false;
      _isPrioritySpeaking = false;
    }
  }

  /// 버스 도착 알림 메시지를 음성으로 출력합니다.
  static Future<void> speakBusAlert({
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String? currentStation,
    bool priority = false,
  }) async {
    try {
      // 오디오 볼륨 최대화 재확인
      await _flutterTts.setVolume(1.0);

      String message;
      if (remainingMinutes <= 0) {
        // 곧 도착 시 특별한 메시지로 처리
        message = '$busNo번 버스가 $stationName에 곧 도착합니다! 탑승 준비하세요.';
        // 우선순위를 true로 설정 (0분 남은 경우는 항상 우선적으로 처리)
        priority = true;
      } else if (remainingMinutes <= 1) {
        message = '$busNo번 버스가 $stationName에 곧 도착합니다. 준비하세요.';
        // 1분 이내도 우선순위로 처리
        priority = true;
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

      // 우선순위 설정
      if (remainingMinutes <= 1) {
        priority = true;
      }

      // 중요 알림인 경우 주의 환기용 사운드 먼저 재생
      if (priority) {
        await _flutterTts.speak("알림. 알림.");
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      await speak(message, priority: priority);
    } catch (e) {
      debugPrint('버스 알림 TTS 오류: $e');
    }
  }

  /// 버스 곧 도착 알림을 강제로 발화합니다 (포그라운드 서비스에서 호출)
  static Future<void> speakBusArrivalImmediate({
    required String busNo,
    required String stationName,
    String? currentStation,
  }) async {
    try {
      // 오디오 볼륨 최대화
      await _flutterTts.setVolume(1.0);

      String message = '$busNo번 버스가 곧 $stationName에 도착합니다! ';
      if (currentStation != null && currentStation.isNotEmpty) {
        message += '현재 $currentStation에 있습니다.';
      } else {
        message += '탑승 준비하세요!';
      }

      debugPrint('버스 도착 강제 TTS 메시지: $message');

      // 주의 환기용 사운드 먼저 재생
      await _flutterTts.speak("중요 알림. 중요 알림.");
      await Future.delayed(const Duration(milliseconds: 1000));

      // 우선순위 true로 발화
      await speak(message, priority: true);
    } catch (e) {
      debugPrint('버스 도착 강제 TTS 오류: $e');
    }
  }

  /// 알람 설정 메시지를 음성으로 출력합니다.
  static Future<void> speakAlarmSet(String busNo) async {
    String message = '$busNo번 승차알람이 설정되었습니다.';
    await speak(message);
  }

  /// 알람 해제 메시지를 음성으로 출력합니다.
  static Future<void> speakAlarmCancel(String busNo) async {
    // 약간의 딜레이를 추가하여 TTS 엔진이 재연결될 시간을 줍니다.
    await Future.delayed(const Duration(milliseconds: 500));

    final initialized = await ensureInitialized();
    if (!initialized) {
      debugPrint("TTS 초기화 실패, 알람 해제 음성 안내 건너뜁니다.");
      return;
    }
    String message = '$busNo번 승차알람이 해제되었습니다.';
    await speak(message);
  }

  /// TTS를 중지합니다.
  static Future<void> stop() async {
    await _flutterTts.stop();
    _isSpeaking = false;
    _isPrioritySpeaking = false;
  }
}
