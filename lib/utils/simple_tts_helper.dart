import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 단순화된 TTS 헬퍼 클래스
/// 이 클래스는 기존 TTSHelper의 복잡한 로직을 단순화하여
/// 음성 발화에서 발생하는 RangeError 문제를 해결합니다.
class SimpleTTSHelper {
  static FlutterTts? _flutterTts;
  static const MethodChannel _channel =
      MethodChannel('com.example.daegu_bus_app/tts');
  static bool _initialized = false;
  static bool _speaking = false;

  /// TTS 초기화
  static Future<void> initialize() async {
    try {
      if (_initialized) return;

      _flutterTts = FlutterTts();
      if (Platform.isAndroid) {
        await _flutterTts!.setLanguage('ko-KR');
        await _flutterTts!.setSpeechRate(0.9);
        await _flutterTts!.setVolume(1.0);
        await _flutterTts!.setPitch(1.0);
      }

      _initialized = true;
      debugPrint('SimpleTTS 초기화 완료');
    } catch (e) {
      debugPrint('SimpleTTS 초기화 오류: $e');
      _initialized = false;
    }
  }

  /// 직접 네이티브 TTS 발화 - 안전한 구현
  static Future<bool> speak(String message) async {
    if (!_initialized) await initialize();
    if (_speaking) {
      debugPrint('이미 발화 중입니다. 발화 생략: $message');
      return false;
    }

    // 발화 직전 화면이 갱신된 최신 정보 로그 출력
    debugPrint('최신 정보 기반 TTS 발화 시도: $message');

    try {
      _speaking = true;
      
      // 네이티브 채널 직접 호출
      try {
        final result = await _channel.invokeMethod('speakTTS', {
          'message': message,
        });
        debugPrint('네이티브 TTS 발화: $message, 결과: $result');
        return result == true;
      } catch (e) {
        debugPrint('네이티브 TTS 발화 오류: $e');
        
        // 네이티브 채널 실패시 Flutter TTS 사용
        if (_flutterTts != null) {
          final result = await _flutterTts!.speak(message);
          debugPrint('Flutter TTS 발화: $message, 결과: $result');
          return result == 1;
        }
      }
      
      return false;
    } finally {
      _speaking = false;
    }
  }

  /// 버스 알람 시작을 위한 단순화된 메서드
  static Future<void> speakBusAlarmStart(String busNo, String stationName) async {
    try {
      // 단순화된 알림 메시지 발화
      await speak('$busNo번 승차알림 시작합니다');
    } catch (e) {
      debugPrint('알람 시작 발화 오류: $e');
      
      // 오류 발생시 더 짧은 메시지로 재시도
      try {
        await speak('$busNo번 승차알림');
      } catch (fallbackError) {
        debugPrint('알람 시작 재시도 오류: $fallbackError');
      }
    }
  }

  /// 버스 도착 알림을 위한 단순화된 메서드
  static Future<void> speakBusArriving(String busNo, String stationName) async {
    try {
      // 첫 번째 부분 발화
      await speak('$busNo번 버스');
      await Future.delayed(const Duration(milliseconds: 800));
      
      // 두 번째 부분 발화
      await speak('$stationName 정류장에 곧 도착합니다');
    } catch (e) {
      debugPrint('버스 도착 발화 오류: $e');
    }
  }

  /// 네이티브 TTS 추적 시작 - 안전하게 구현
  static Future<void> startNativeTtsTracking({
    required String routeId,
    required String stationId, 
    required String busNo,
    required String stationName,
  }) async {
    try {
      if (!_initialized) await initialize();
      
      // 입력값 검증
      String effectiveBusNo = busNo.isEmpty ? routeId : busNo;
      String effectiveStationId = stationId.isEmpty ? routeId : stationId;
      String effectiveRouteId = routeId.isEmpty ? busNo : routeId;
      
      // 안전한 발화 처리
      await speakBusAlarmStart(effectiveBusNo, stationName);
      
      // 네이티브 추적 시작
      try {
        await _channel.invokeMethod('startTtsTracking', {
          'routeId': effectiveRouteId,
          'stationId': effectiveStationId,
          'busNo': effectiveBusNo,
          'stationName': stationName,
        });
        debugPrint('네이티브 TTS 추적 시작됨');
      } catch (e) {
        debugPrint('네이티브 TTS 추적 시작 오류: $e');
      }
    } catch (e) {
      debugPrint('TTS 추적 시작 처리 오류: $e');
    }
  }

  /// 네이티브 TTS 추적 중지
  static Future<void> stopNativeTtsTracking() async {
    try {
      await _channel.invokeMethod('stopTtsTracking');
      if (_flutterTts != null) {
        await _flutterTts!.stop();
      }
      debugPrint('TTS 추적 중지됨');
    } catch (e) {
      debugPrint('TTS 추적 중지 오류: $e');
    }
  }
}
