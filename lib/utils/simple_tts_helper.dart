import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../main.dart' show logMessage, LogLevel;
import 'tts_switcher.dart';

/// TTS(Text-to-Speech) 기능을 간편하게 사용할 수 있는 유틸리티 클래스
class SimpleTTSHelper {
  static FlutterTts? _flutterTts;
  static const MethodChannel _ttsChannel =
      MethodChannel('com.example.daegu_bus_app/tts');
  static bool _isInitialized = false;
  static bool _isSpeaking = false;
  static final Set<String> _recentMessages = {};
  static Timer? _cleanupTimer;
  static TtsSwitcher? _ttsSwitcher;

  /// TTS 엔진 초기화
  static Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _flutterTts = FlutterTts();
      await _flutterTts?.setLanguage('ko-KR');
      await _flutterTts?.setSpeechRate(0.5);
      await _flutterTts?.setVolume(1.0);
      await _flutterTts?.setPitch(1.1);

      // 이벤트 리스너 설정
      _flutterTts?.setStartHandler(() {
        _isSpeaking = true;
        logMessage('🔊 TTS 발화 시작', level: LogLevel.info);
      });

      _flutterTts?.setCompletionHandler(() {
        _isSpeaking = false;
        logMessage('✅ TTS 발화 완료', level: LogLevel.info);
      });

      _flutterTts?.setErrorHandler((message) {
        _isSpeaking = false;
        logMessage('❌ TTS 오류: $message', level: LogLevel.error);
      });

      _flutterTts?.setCancelHandler(() {
        _isSpeaking = false;
        logMessage('🔄 TTS 취소됨', level: LogLevel.info);
      });

      // TTS 스위처 초기화
      _ttsSwitcher = TtsSwitcher();
      await _ttsSwitcher?.initialize();

      // 중복 메시지 관리를 위한 타이머 설정
      _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
        _cleanupRecentMessages();
      });

      _isInitialized = true;
      logMessage('✅ TTS 초기화 완료', level: LogLevel.info);
    } catch (e) {
      logMessage('❌ TTS 초기화 오류: $e', level: LogLevel.error);
      _isInitialized = false;
    }
  }

  /// 텍스트를 음성으로 변환 (플러터 TTS 사용)
  static Future<bool> speak(String message, {bool force = false}) async {
    try {
      if (!_isInitialized) {
        await initialize();
      }

      // 이미 말하고 있다면 중단
      if (_isSpeaking && !force) {
        logMessage('⚠️ TTS가 이미 실행 중입니다. 메시지: $message',
            level: LogLevel.warning);
        return false;
      }

      // 중복 메시지 체크 (5분 이내 동일 메시지)
      if (!force && _isRecentMessage(message)) {
        logMessage('⚠️ 최근에 동일한 TTS 메시지가 발화되었습니다: $message',
            level: LogLevel.warning);
        return false;
      }

      // 메시지가 비어있는 경우 무시
      if (message.trim().isEmpty) {
        logMessage('⚠️ 비어있는 TTS 메시지', level: LogLevel.warning);
        return false;
      }

      // TTS 엔진 선택 (이어폰 연결 상태에 따라)
      final useNativeTts = await _ttsSwitcher?.shouldUseNativeTts() ?? false;

      if (useNativeTts) {
        return await _speakNative(message);
      } else {
        return await _speakFlutter(message);
      }
    } catch (e) {
      logMessage('❌ TTS 발화 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  /// 네이티브 TTS 사용 (Android)
  static Future<bool> _speakNative(String message) async {
    try {
      logMessage('🔊 네이티브 TTS 발화 시도: $message', level: LogLevel.info);

      final isHeadphoneMode =
          await _ttsSwitcher?.isHeadphoneConnected() ?? false;
      final result = await _ttsChannel.invokeMethod('speakTTS', {
        'message': message,
        'isHeadphoneMode': isHeadphoneMode,
      });

      _isSpeaking = true;
      _addRecentMessage(message);

      logMessage('✅ 네이티브 TTS 발화 요청 성공: $result', level: LogLevel.info);
      return true;
    } catch (e) {
      logMessage('❌ 네이티브 TTS 발화 오류: $e', level: LogLevel.error);

      // 네이티브 TTS 실패 시 Flutter TTS로 폴백
      logMessage('🔄 Flutter TTS로 폴백 시도', level: LogLevel.warning);
      return await _speakFlutter(message);
    }
  }

  /// Flutter TTS 사용
  static Future<bool> _speakFlutter(String message) async {
    try {
      if (_flutterTts == null) {
        await initialize();
      }

      _isSpeaking = true;
      _addRecentMessage(message);

      await _flutterTts?.stop();
      await _flutterTts?.speak(message);

      logMessage('✅ Flutter TTS 발화 시작: $message', level: LogLevel.info);
      return true;
    } catch (e) {
      logMessage('❌ Flutter TTS 발화 오류: $e', level: LogLevel.error);
      _isSpeaking = false;
      return false;
    }
  }

  /// TTS 중지
  static Future<bool> stop() async {
    try {
      if (!_isInitialized) return false;

      // Flutter TTS 중지
      await _flutterTts?.stop();

      // 네이티브 TTS 중지 시도
      try {
        await _ttsChannel.invokeMethod('stopTTS');
      } catch (e) {
        logMessage('⚠️ 네이티브 TTS 중지 오류: $e', level: LogLevel.warning);
      }

      _isSpeaking = false;
      logMessage('✅ TTS 중지 완료', level: LogLevel.info);
      return true;
    } catch (e) {
      logMessage('❌ TTS 중지 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  /// 오디오 출력 모드 설정 (0: 이어폰 전용, 1: 스피커 전용, 2: 자동)
  static Future<bool> setAudioOutputMode(int mode) async {
    try {
      await _ttsChannel.invokeMethod('setAudioOutputMode', {'mode': mode});
      logMessage('✅ 오디오 출력 모드 설정: $mode', level: LogLevel.info);
      return true;
    } catch (e) {
      logMessage('❌ 오디오 출력 모드 설정 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  /// 리소스 해제
  static Future<void> dispose() async {
    try {
      await stop();
      _cleanupTimer?.cancel();
      _flutterTts?.stop();
      _ttsSwitcher?.dispose();
      _isInitialized = false;
      _recentMessages.clear();
      logMessage('✅ TTS 리소스 해제 완료', level: LogLevel.info);
    } catch (e) {
      logMessage('❌ TTS 리소스 해제 오류: $e', level: LogLevel.error);
    }
  }

  /// 최근 메시지인지 확인 (중복 방지)
  static bool _isRecentMessage(String message) {
    return _recentMessages.contains(message);
  }

  /// 최근 메시지에 추가
  static void _addRecentMessage(String message) {
    _recentMessages.add(message);

    // 최대 50개 메시지만 유지
    if (_recentMessages.length > 50) {
      _recentMessages.remove(_recentMessages.first);
    }
  }

  /// 오래된 메시지 정리 (5분 단위)
  static void _cleanupRecentMessages() {
    _recentMessages.clear();
    logMessage('🧹 TTS 메시지 캐시 정리됨', level: LogLevel.debug);
  }

  /// 현재 말하고 있는 상태인지 확인
  static bool get isSpeaking => _isSpeaking;

  /// 초기화되었는지 확인
  static bool get isInitialized => _isInitialized;

  /// 버스 도착 알림 TTS 발화
  static Future<bool> speakBusArriving(String busNo, String stationName) async {
    final message = "$busNo번 버스가 $stationName 정류장에 곧 도착합니다. 탑승 준비하세요.";
    return await speak(message);
  }

  /// 버스 알림 TTS 발화 (상세 정보 포함)
  static Future<bool> speakBusAlert({
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String? currentStation,
    int? remainingStops,
  }) async {
    String message;

    if (remainingMinutes <= 0) {
      message = "$busNo번 버스가 $stationName 정류장에 곧 도착합니다. 탑승 준비하세요.";
    } else if (remainingStops == 1) {
      message = "$busNo번 버스가 $stationName 정류장 앞 정류장에 도착했습니다. 곧 도착합니다.";
    } else {
      final locationInfo = currentStation != null &&
              currentStation.isNotEmpty &&
              currentStation != "정보 없음"
          ? " 현재 $currentStation 위치에서"
          : "";
      message =
          "$busNo번 버스가$locationInfo $stationName 정류장에 약 $remainingMinutes분 후 도착 예정입니다.";
    }

    return await speak(message);
  }

  /// 볼륨 설정
  static Future<void> setVolume(double volume) async {
    try {
      // volume은 0.0 ~ 1.0 사이의 값
      final normalizedVolume = volume.clamp(0.0, 1.0);
      await _ttsChannel.invokeMethod('setVolume', {'volume': normalizedVolume});
    } catch (e) {
      logMessage('볼륨 설정 오류: $e', level: LogLevel.error);
      rethrow;
    }
  }
}
