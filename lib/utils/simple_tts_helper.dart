import 'dart:async';
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
  static const bool _initialized = false;

  /// TTS 초기화
  static Future<bool> initialize() async {
    try {
      await _channel.invokeMethod('forceEarphoneOutput');
      debugPrint('🔊 TTS 초기화 성공');
      return true;
    } catch (e) {
      debugPrint('❌ TTS 초기화 오류: $e');
      return false;
    }
  }

  /// TTS 발화
  static Future<bool> speak(String message) async {
    try {
      debugPrint('🔊 TTS 발화 요청: "$message"');
      debugPrint('🔊 TTS 모드는 네이티브 로그를 확인하세요');

      final result = await _channel.invokeMethod('speakTTS', {
        'message': message,
        'isHeadphoneMode': false, // 기본 발화는 스피커 모드 사용
      });

      // 발화 후 알림창에 안내 메시지 추가
      debugPrint('🔊 TTS 발화 완료: 결과=$result');
      debugPrint('🔔 알림이 표시된 경우 설정 > 알림 또는 알림창에서 취소할 수 있습니다');

      return result == true;
    } catch (e) {
      debugPrint('❌ TTS 발화 오류: $e');
      return false;
    }
  }

  /// 버스 알람 시작을 위한 단순화된 메서드
  static Future<bool> speakBusAlarmStart(
      String busNo, String stationName) async {
    final message = '$busNo 번 버스 알림이 설정되었습니다.';
    try {
      debugPrint('🔔 버스 알람 시작 TTS 요청: "$message"');
      debugPrint('🔊 TTS 모드는 네이티브 로그를 확인하세요');

      final result = await _channel.invokeMethod('speakTTS', {
        'message': message,
        'isHeadphoneMode': false, // 알람 설정 시에는 스피커 우선
      });

      debugPrint('🔔 버스 알람 시작 TTS 완료: 결과=$result');
      return result == true;
    } catch (e) {
      debugPrint('❌ 버스 알람 시작 TTS 오류: $e');
      return false;
    }
  }

  /// 버스 도착 알림을 위한 단순화된 메서드
  static Future<void> speakBusArriving(String busNo, String stationName) async {
    try {
      // 위치 정보를 더 명확히 포함
      await speak('$busNo번 버스가 $stationName 정류장 앞 정류장에 도착했습니다. 곧 $stationName에 도착합니다. 탑승 준비하세요.');
    } catch (e) {
      debugPrint('버스 도착 발화 오류: $e');
    }
  }

  /// 버스 도착 발화 - 단순화
  static Future<void> speakBusAlert({
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String? currentStation,
    int? remainingStops, // 추가: 남은 정류장 수
  }) async {
    try {
      // 정류장 개수에 따른 처리
      String message;
      if (remainingStops == 1 && remainingMinutes <= 3) {
        // 목적지 앞 정류장 도착 시
        message = '$busNo번 버스가 $stationName 정류장 앞 정류장에 도착했습니다. 곧 $stationName에 도착합니다.';
      } else if (remainingMinutes <= 0) {
        message = '$busNo번 버스가 $stationName에 도착했습니다. 탑승하세요.';
      } else {
        message = '$busNo번 버스가 약 $remainingMinutes분 후 도착 예정입니다.';
      }

      // 현재 위치 정보가 있으면 추가
      if (currentStation != null && currentStation.isNotEmpty && remainingMinutes > 0) {
        message += ' 현재 $currentStation 위치입니다.';
      }

      await speak(message);
    } catch (e) {
      debugPrint('버스 알림 발화 오류: $e');
    }
  }

  /// 알람 취소 발화
  static Future<void> speakAlarmCancel(String busNo) async {
    try {
      final message = '$busNo번 버스 알림이 취소되었습니다.';
      await speak(message);
    } catch (e) {
      debugPrint('알림 취소 발화 오류: $e');
    }
  }

  /// 알람 설정 발화
  static Future<void> speakAlarmSet(String busNo) async {
    try {
      final message = '$busNo번 버스 승차 알람이 설정되었습니다.';
      await speak(message);
    } catch (e) {
      debugPrint('알람 설정 발화 오류: $e');
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

      // 보아수 알림, 방법 채널을 통해 시작되는 경우가 많으니 발화 생략
      // 여기서 발화를 하면 두 번 발화되는 문제가 발생함
      debugPrint('네이티브 TTS 추적 시작 - 발화 생략');

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

  /// 이어폰 전용 발화
  static Future<bool> speakToHeadphone(String message) async {
    try {
      debugPrint('🎧 이어폰 전용 TTS 발화 요청: "$message"');

      final result = await _channel.invokeMethod('speakEarphoneOnly', {
        'message': message,
      });

      debugPrint('🎧 이어폰 전용 TTS 발화 완료: 결과=$result');
      return result == true;
    } catch (e) {
      debugPrint('❌ 이어폰 전용 TTS 발화 오류: $e');
      return false;
    }
  }

  /// 승차 완료 처리
  static Future<void> handleBoardingComplete() async {
    try {
      debugPrint('✅ 승차 완료 처리 시작');

      // TTS 중지
      await stop();

      // 네이티브 추적 중지
      await stopNativeTtsTracking();

      debugPrint('✅ 승차 완료 처리 완료');
    } catch (e) {
      debugPrint('❌ 승차 완료 처리 오류: $e');
    }
  }

  /// TTS 중지
  static Future<bool> stop() async {
    try {
      await _channel.invokeMethod('stopTTS');
      debugPrint('🔊 TTS 중지 성공');
      return true;
    } catch (e) {
      debugPrint('❌ TTS 중지 오류: $e');
      return false;
    }
  }
}
