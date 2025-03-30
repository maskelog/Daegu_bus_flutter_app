import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TTSHelper {
  static final FlutterTts _flutterTts = FlutterTts();
  static const MethodChannel _nativeChannel =
      MethodChannel('com.example.daegu_bus_app/bus_api');

  static bool _isInitialized = false;
  static bool _isSpeaking = false;
  static bool _isPrioritySpeaking = false;

  /// TTS 초기화
  static Future<void> initialize() async {
    try {
      await _flutterTts.setLanguage("ko-KR");
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      if (Platform.isAndroid) {
        await _flutterTts.setQueueMode(1);
        await _flutterTts.setSharedInstance(true);
      }

      _flutterTts.setCompletionHandler(() {
        _isSpeaking = false;
        _isPrioritySpeaking = false;
        debugPrint('TTS 완료');
      });

      _flutterTts.setErrorHandler((error) {
        debugPrint('TTS 오류 발생: $error');
        _isSpeaking = false;
        _isPrioritySpeaking = false;
      });

      final engines = await _flutterTts.getEngines;
      debugPrint('사용 가능한 TTS 엔진: $engines');

      try {
        final languages = await _flutterTts.getLanguages;
        debugPrint('사용 가능한 TTS 언어: $languages');
        final koSupported = languages.toString().contains('ko');
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

  static Future<bool> ensureInitialized() async {
    debugPrint('TTS 초기화 상태 확인: $_isInitialized');
    if (!_isInitialized) {
      try {
        await initialize();
        return _isInitialized;
      } catch (e) {
        debugPrint('TTS 재초기화 실패: $e');
        return false;
      }
    }
    return true;
  }

  static Future<void> speak(String message, {bool priority = false}) async {
    final initialized = await ensureInitialized();
    if (!initialized) {
      debugPrint('TTS 초기화 실패: $message');
      return;
    }

    if (!priority && _isPrioritySpeaking) {
      debugPrint('우선순위 발화 중: $message 무시됨');
      return;
    }

    if (_isSpeaking && (priority || !_isPrioritySpeaking)) {
      await stop();
    }

    debugPrint('TTS 발화: $message ${priority ? "(우선순위)" : ""}');
    _isSpeaking = true;
    if (priority) _isPrioritySpeaking = true;

    try {
      await _flutterTts.speak(message);
    } catch (e) {
      debugPrint('TTS 발화 오류: $e');
      _isSpeaking = false;
      _isPrioritySpeaking = false;
    }
  }

  static Future<void> speakBusAlert({
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String? currentStation,
    bool priority = false,
  }) async {
    try {
      await _flutterTts.setVolume(1.0);

      String message;
      if (remainingMinutes <= 0) {
        message = '$busNo번 버스가 $stationName에 곧 도착합니다! 탑승 준비하세요.';
        priority = true;
      } else if (remainingMinutes <= 1) {
        message = '$busNo번 버스가 $stationName에 곧 도착합니다. 준비하세요.';
        priority = true;
      } else {
        message = '$busNo번 버스가 약 $remainingMinutes분 후 $stationName에 도착합니다.';
        if (currentStation != null && currentStation.isNotEmpty) {
          message += ' 현재 위치는 $currentStation입니다.';
        }
      }

      if (priority) {
        await _flutterTts.speak("알림. 알림.");
        await Future.delayed(const Duration(milliseconds: 1000));
      }

      await speak(message, priority: priority);
    } catch (e) {
      debugPrint('버스 알림 TTS 오류: $e');
    }
  }

  static Future<void> speakBusArrivalImmediate({
    required String busNo,
    required String stationName,
    String? currentStation,
  }) async {
    try {
      await _flutterTts.setVolume(1.0);
      String message = '$busNo번 버스가 곧 $stationName에 도착합니다!';
      if (currentStation != null && currentStation.isNotEmpty) {
        message += ' 현재 위치: $currentStation';
      }

      await _flutterTts.speak("중요 알림. 중요 알림.");
      await Future.delayed(const Duration(milliseconds: 1000));
      await speak(message, priority: true);
    } catch (e) {
      debugPrint('강제 TTS 오류: $e');
    }
  }

  static Future<void> speakAlarmSet(String busNo) async {
    String message = '$busNo번 승차알람이 설정되었습니다.';
    await speak(message);
  }

  static Future<void> speakAlarmCancel(String busNo) async {
    await Future.delayed(const Duration(milliseconds: 500));
    final initialized = await ensureInitialized();
    if (!initialized) return;
    String message = '$busNo번 승차알람이 해제되었습니다.';
    await speak(message);
  }

  static Future<void> stop() async {
    await _flutterTts.stop();
    _isSpeaking = false;
    _isPrioritySpeaking = false;
  }

  /// ✅ 네이티브(Android) TTS 추적을 호출하는 함수
  static Future<void> startNativeTtsTracking({
    required String routeId,
    required String stationId,
    required String busNo,
    required String stationName,
  }) async {
    try {
      await _nativeChannel.invokeMethod('startTtsTracking', {
        'routeId': routeId,
        'stationId': stationId,
        'busNo': busNo,
        'stationName': stationName,
      });
      debugPrint('📣 Native TTS 추적 시작 호출 완료');
    } catch (e) {
      debugPrint('❌ Native TTS 추적 호출 실패: $e');
    }
  }
}
