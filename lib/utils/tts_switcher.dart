import 'dart:async';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart' show logMessage, LogLevel;

/// TTS 출력 모드 열거형
enum TtsOutputMode {
  /// 이어폰 전용 모드
  headphoneOnly,

  /// 스피커 전용 모드
  speakerOnly,

  /// 자동 감지 모드 (기본값)
  auto
}

/// TTS 엔진 선택을 위한 스위처 클래스
class TtsSwitcher {
  static const MethodChannel _platform =
      MethodChannel('com.example.daegu_bus_app/tts');
  static const String _prefsKey = 'tts_output_mode';

  /// 현재 설정된 출력 모드
  TtsOutputMode _currentMode = TtsOutputMode.auto;

  /// 초기화 여부
  bool _isInitialized = false;

  /// 초기화
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 저장된 설정 불러오기
      final prefs = await SharedPreferences.getInstance();
      final savedMode = prefs.getInt(_prefsKey);

      if (savedMode != null) {
        _currentMode = TtsOutputMode
            .values[savedMode.clamp(0, TtsOutputMode.values.length - 1)];
      }

      // 네이티브 모듈에 초기 모드 설정
      await _platform
          .invokeMethod('setAudioOutputMode', {'mode': _currentMode.index});

      _isInitialized = true;
      logMessage('✅ TTS 스위처 초기화 완료: $_currentMode', level: LogLevel.info);
    } catch (e) {
      logMessage('❌ TTS 스위처 초기화 오류: $e', level: LogLevel.error);
    }
  }

  /// 출력 모드 설정
  Future<bool> setOutputMode(TtsOutputMode mode) async {
    try {
      _currentMode = mode;

      // 설정 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, mode.index);

      // 네이티브 모듈에 설정
      await _platform.invokeMethod('setAudioOutputMode', {'mode': mode.index});

      logMessage('✅ TTS 출력 모드 설정: $mode', level: LogLevel.info);
      return true;
    } catch (e) {
      logMessage('❌ TTS 출력 모드 설정 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  /// 이어폰 연결 상태 확인
  Future<bool> isHeadphoneConnected() async {
    try {
      final result = await _platform.invokeMethod<bool>('isHeadphoneConnected');
      return result ?? false;
    } catch (e) {
      logMessage('❌ 이어폰 연결 상태 확인 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  /// 네이티브 TTS를 사용해야 하는지 확인
  Future<bool> shouldUseNativeTts() async {
    try {
      // 이어폰 연결 상태 확인
      final bool headphoneStatus = await isHeadphoneConnected();

      // 모드에 따른 결정
      switch (_currentMode) {
        case TtsOutputMode.headphoneOnly:
          // 이어폰 전용 모드에서는 이어폰이 연결된 경우만 네이티브 TTS 사용
          final shouldUse = headphoneStatus;
          logMessage(
              '🎧 이어폰 전용 모드: ${shouldUse ? "네이티브 TTS 사용" : "Flutter TTS 사용"}',
              level: LogLevel.debug);
          return shouldUse;

        case TtsOutputMode.speakerOnly:
          // 스피커 전용 모드에서는 항상 Flutter TTS 사용
          logMessage('🔊 스피커 전용 모드: Flutter TTS 사용', level: LogLevel.debug);
          return false;

        case TtsOutputMode.auto:
          // 자동 모드에서는 이어폰 연결 상태에 따라 결정
          // 이어폰 연결 시 네이티브 TTS, 그 외에는 Flutter TTS
          logMessage(
              '🔄 자동 감지 모드: ${headphoneStatus ? "네이티브 TTS 사용" : "Flutter TTS 사용"}',
              level: LogLevel.debug);
          return headphoneStatus;
      }
    } catch (e) {
      logMessage('❌ TTS 엔진 선택 오류: $e', level: LogLevel.error);
      // 오류 발생 시 기본값으로 Flutter TTS 사용
      return false;
    }
  }

  /// 현재 출력 모드 가져오기
  TtsOutputMode get currentMode => _currentMode;

  /// 리소스 해제
  void dispose() {
    _isInitialized = false;
  }

  /// TTS 추적 시작 (정적 메서드)
  static Future<bool> startTtsTracking({
    required String routeId,
    required String stationId,
    required String busNo,
    required String stationName,
    int remainingMinutes = 5,
    Future<int> Function()? getRemainingTimeCallback,
  }) async {
    try {
      // 네이티브 메서드로 TTS 추적 시작
      final result = await _platform.invokeMethod('startTtsTracking', {
        'routeId': routeId,
        'stationId': stationId,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
      });

      logMessage('✅ TTS 추적 시작: $busNo, $stationName', level: LogLevel.info);
      return result == true;
    } catch (e) {
      logMessage('❌ TTS 추적 시작 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  /// TTS 추적 중지 (정적 메서드)
  static Future<bool> stopTtsTracking(String busNo) async {
    try {
      final result = await _platform.invokeMethod('stopTtsTracking', {
        'busNo': busNo,
      });

      logMessage('✅ TTS 추적 중지: $busNo', level: LogLevel.info);
      return result == true;
    } catch (e) {
      logMessage('❌ TTS 추적 중지 오류: $e', level: LogLevel.error);
      return false;
    }
  }
}
