import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../main.dart' show logMessage, LogLevel;
import 'tts_switcher.dart';

/// TTS(Text-to-Speech) 기능을 간편하게 사용할 수 있는 유틸리티 클래스
class SimpleTTSHelper {
  static FlutterTts? _flutterTts;
  static const MethodChannel _ttsChannel =
      MethodChannel('com.devground.daegubus/tts');
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
  static Future<bool> speak(String message,
      {bool force = false, bool earphoneOnly = false}) async {
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

      // 🔊 자동 알람의 경우 이어폰 연결 상태와 관계없이 발화 (earphoneOnly가 false이고 force가 true인 경우)
      if (!earphoneOnly && force) {
        logMessage('🔊 자동 알람 TTS: 이어폰 연결 상태 무시하고 발화 시도', level: LogLevel.info);

        // TTS 발화 실행
        _isSpeaking = true;
        _addRecentMessage(message);

        // 먼저 네이티브 TTS 시도 (스피커 포함)
        try {
          logMessage('🔊 네이티브 TTS 발화 시도 (스피커 모드): $message',
              level: LogLevel.info);

          final result = await _ttsChannel.invokeMethod('speakTTS', {
            'message': message,
            'isHeadphoneMode': false, // 스피커 모드 강제
            'forceSpeaker': true, // 스피커 강제 사용
            'volume': 1.0, // 최대 볼륨
          });

          logMessage('✅ 네이티브 TTS 발화 성공 (스피커): $result', level: LogLevel.info);
          return true;
        } catch (e) {
          logMessage('❌ 네이티브 TTS 발화 실패, Flutter TTS로 폴백: $e',
              level: LogLevel.warning);

          // 네이티브 TTS 실패 시 Flutter TTS로 폴백
          try {
            if (_flutterTts == null) {
              await initialize();
            }

            await _flutterTts?.setVolume(1.0); // 최대 볼륨
            await _flutterTts?.setSpeechRate(0.5); // 적당한 속도
            await _flutterTts?.speak(message);

            logMessage('✅ Flutter TTS 폴백 발화 성공: $message',
                level: LogLevel.info);
            return true;
          } catch (flutterError) {
            logMessage('❌ Flutter TTS 폴백도 실패: $flutterError',
                level: LogLevel.error);
            _isSpeaking = false;
            return false;
          }
        }
      }

      // 🎧 일반 알람 및 이어폰 전용 모드 (earphoneOnly가 true인 경우)
      logMessage('🎧 이어폰 전용 모드 TTS 시도', level: LogLevel.info);

      // 현재 설정된 오디오 출력 모드 확인
      int currentMode = earphoneOnly ? 0 : await _getCurrentAudioMode();
      logMessage('🔊 현재 오디오 출력 모드: $currentMode (earphoneOnly: $earphoneOnly)',
          level: LogLevel.info);

      // 이어폰 연결 상태 확인
      bool isHeadphoneConnected = await _checkHeadphoneConnection();
      logMessage('🎧 이어폰 연결 상태: ${isHeadphoneConnected ? "연결됨" : "연결 안됨"}',
          level: LogLevel.info);

      // 🎧 일반 알람의 경우 이어폰이 연결되지 않았으면 TTS 발화 안함
      if (earphoneOnly && !isHeadphoneConnected) {
        logMessage('⚠️ 일반 알람: 이어폰이 연결되지 않아 TTS 발화를 건너뜁니다.',
            level: LogLevel.warning);
        _isSpeaking = false;
        return false;
      }

      // 출력 모드에 따른 처리
      switch (currentMode) {
        case 0: // 이어폰 전용
          if (!isHeadphoneConnected) {
            logMessage('⚠️ 이어폰 전용 모드인데 이어폰이 연결되지 않았습니다.',
                level: LogLevel.warning);
            return false;
          }
          break;
        case 1: // 스피커 전용
          // 스피커 모드는 이어폰 연결 상태와 관계없이 진행
          break;
        case 2: // 자동 감지
          if (earphoneOnly && !isHeadphoneConnected) {
            logMessage('⚠️ 이어폰 전용 요청인데 이어폰이 연결되지 않았습니다.',
                level: LogLevel.warning);
            return false;
          }
          break;
      }

      // TTS 발화 실행
      _isSpeaking = true;
      _addRecentMessage(message);

      // 강제 모드인 경우 이어폰 체크 무시하고 네이티브 TTS 사용
      if (force) {
        logMessage('🔊 강제 모드로 네이티브 TTS 사용', level: LogLevel.info);
        return await _speakNative(message, force: true);
      }

      if (currentMode == 0 || (earphoneOnly && isHeadphoneConnected)) {
        // 이어폰 전용 또는 이어폰 강제 모드
        return await _speakFlutter(message, force: force);
      } else {
        // 스피커 전용 또는 기타
        return await _speakNative(message, force: force);
      }
    } catch (e) {
      logMessage('❌ TTS 발화 오류: $e', level: LogLevel.error);
      _isSpeaking = false;
      return false;
    }
  }

  /// 네이티브 TTS 사용 (Android)
  static Future<bool> _speakNative(String message, {bool force = false}) async {
    try {
      logMessage('🔊 네이티브 TTS 발화 시도: $message (force=$force)',
          level: LogLevel.info);

      final isHeadphoneMode =
          await _ttsSwitcher?.isHeadphoneConnected() ?? false;

      // 강제 모드인 경우 추가 파라미터 전달
      final result = await _ttsChannel.invokeMethod('speakTTS', {
        'message': message,
        'isHeadphoneMode': isHeadphoneMode,
        'forceSpeaker': force, // 강제 스피커 모드 플래그 추가
        'volume': force ? 1.0 : 0.8, // 강제 모드일 때 최대 볼륨
      });

      _isSpeaking = true;
      _addRecentMessage(message);

      logMessage('✅ 네이티브 TTS 발화 요청 성공: $result', level: LogLevel.info);

      // 강제 모드인 경우 백업 TTS는 실행하지 않음 (중복 방지)
      // 자동알람의 경우 TTSService에서 별도로 백업 TTS를 처리함

      return true;
    } catch (e) {
      logMessage('❌ 네이티브 TTS 발화 오류: $e', level: LogLevel.error);

      // 네이티브 TTS 실패 시 Flutter TTS로 폴백
      logMessage('🔄 Flutter TTS로 폴백 시도', level: LogLevel.warning);
      return await _speakFlutter(message, force: force);
    }
  }

  /// Flutter TTS 사용
  static Future<bool> _speakFlutter(String message,
      {bool force = false}) async {
    try {
      if (_flutterTts == null) {
        await initialize();
      }

      _isSpeaking = true;
      _addRecentMessage(message);

      // 강제 모드인 경우 볼륨 및 속도 설정
      if (force) {
        await _flutterTts?.setVolume(1.0);
        await _flutterTts?.setSpeechRate(0.5);
        await _flutterTts?.setPitch(1.0);
        logMessage('🔊 Flutter TTS 강제 모드 설정 완료', level: LogLevel.info);
      }

      await _flutterTts?.stop();
      await _flutterTts?.speak(message);

      logMessage('✅ Flutter TTS 발화 시작: $message (force=$force)',
          level: LogLevel.info);

      // 강제 모드인 경우 백업 TTS는 실행하지 않음 (중복 방지)
      // 자동알람의 경우 TTSService에서 별도로 백업 TTS를 처리함

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

  /// 현재 오디오 출력 모드 가져오기
  static Future<int> _getCurrentAudioMode() async {
    try {
      final result = await _ttsChannel.invokeMethod('getAudioOutputMode');
      return result as int;
    } catch (e) {
      logMessage('⚠️ 오디오 출력 모드 확인 실패: $e', level: LogLevel.warning);
      return 2; // 기본값: 자동 감지
    }
  }

  /// 이어폰 연결 상태 확인
  static Future<bool> _checkHeadphoneConnection() async {
    try {
      final result = await _ttsChannel.invokeMethod('isHeadphoneConnected');
      return result as bool;
    } catch (e) {
      logMessage('⚠️ 이어폰 연결 상태 확인 실패: $e', level: LogLevel.warning);
      return false;
    }
  }

  /// 버스 도착 알림 TTS 발화 (간소화)
  static Future<bool> speakBusArriving(String busNo, String stationName,
      {bool earphoneOnly = true}) async {
    final message = "$busNo번 버스가 곧 도착합니다. 탑승 준비하세요.";
    return await speak(message, earphoneOnly: earphoneOnly);
  }

  /// 버스 알림 TTS 발화 (간소화된 메시지)
  static Future<bool> speakBusAlert({
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String? currentStation,
    int? remainingStops,
    bool earphoneOnly = true,
    bool isAutoAlarm = false, // 자동 알람 여부 추가
  }) async {
    String message;

    // 정류장 이름 제거로 메시지 간소화
    if (remainingMinutes <= 0) {
      message = "$busNo번 버스가 곧 도착합니다.";
    } else if (remainingStops == 1) {
      message = "$busNo번 버스가 앞 정류장에 도착했습니다. 곧 도착합니다.";
    } else {
      message = "$busNo번 버스가 약 $remainingMinutes분 후 도착 예정입니다.";
    }

    // 자동 알람인 경우 강제 스피커 모드로 발화
    if (isAutoAlarm) {
      logMessage('🔊 자동 알람 TTS 발화 (강제 스피커 모드): $message', level: LogLevel.info);
      return await speak(message, force: true, earphoneOnly: false);
    }

    return await speak(message, earphoneOnly: earphoneOnly);
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
