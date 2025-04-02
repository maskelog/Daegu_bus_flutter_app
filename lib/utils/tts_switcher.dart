import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'simple_tts_helper.dart';
import 'tts_helper.dart';

// 버스 실시간 정보 업데이트 콜백 함수 타입
typedef BusRemainingTimeCallback = Future<int> Function();

/// 안전한 TTS 발화를 보장하기 위한 클래스
class TTSSwitcher {
  static const MethodChannel _channel =
      MethodChannel('com.example.daegu_bus_app/tts');

  // 주기적 알림 타이머
  static Timer? _busAlertTimer;

  // 실시간 업데이트를 위한 남은 시간 콜백 함수
  static BusRemainingTimeCallback? _getRemainingTimeCallback;

  // 현재 추적 중인 버스 번호 (중지 시 사용)
  static String? _currentBusNo;

  /// 직접 네이티브 TTS 발화 - 안전한 구현
  static Future<bool> speakSafely(String message) async {
    try {
      // 먼저 SimpleTTSHelper로 시도
      return await SimpleTTSHelper.speak(message);
    } catch (e) {
      debugPrint('SimpleTTSHelper 발화 오류: $e');

      // 오류 발생 시 네이티브 채널 직접 호출
      try {
        final result = await _channel.invokeMethod('speakTTS', {
          'message': message,
        });
        return result == true;
      } catch (e2) {
        debugPrint('네이티브 채널 직접 호출 오류: $e2');
        return false;
      }
    }
  }

  /// 버스 알람 시작용 TTS - 통합형
  static Future<void> startBusAlarm(String busNo, String stationName) async {
    try {
      await speakSafely('$busNo번 버스 승차알림을 시작합니다');
    } catch (e) {
      debugPrint('버스 알람 시작 TTS 오류: $e');
    }
  }

  /// 안전한 네이티브 TTS 추적 시작
  static Future<void> startTtsTracking({
    required String routeId,
    required String stationId,
    required String busNo,
    required String stationName,
    required int remainingMinutes, // 초기 남은 시간을 필수로 설정
    BusRemainingTimeCallback? getRemainingTimeCallback, // 실시간 업데이트 콜백
  }) async {
    try {
      // 현재 버스 번호 저장
      _currentBusNo = busNo;

      // 콜백 함수 저장
      _getRemainingTimeCallback = getRemainingTimeCallback;

      // 시작 메시지 발화
      await speakSafely('$busNo번 버스 승차알람이 설정되었습니다.');

      debugPrint('네이티브 TTS 추적 시작됨: $busNo, 초기 남은 시간: $remainingMinutes분');

      // 주기적인 TTS 알림 설정
      _setupPeriodicBusAlertWithTime(busNo, stationName, remainingMinutes);
    } catch (e) {
      debugPrint('TTS 추적 전체 오류: $e');
      try {
        await speakSafely('$busNo번 버스 승차알람을 시작합니다');
      } catch (_) {}
    }
  }

// 주기적인 TTS 알림 발화 설정 - 남은 시간 전달 받는 버전
  static void _setupPeriodicBusAlertWithTime(
      String busNo, String stationName, int initialRemainingMinutes) {
    // 기존 타이머 있으면 취소
    _busAlertTimer?.cancel();

    // 초기 남은 시간
    int remainingMinutes = initialRemainingMinutes;
    debugPrint('초기 남은 시간 설정: $remainingMinutes분');

    // 초기 발화
    if (remainingMinutes > 0) {
      speakSafely('$busNo번 버스가 약 $remainingMinutes분 후 도착 예정입니다.');
    } else {
      speakSafely('$busNo번 버스가 곧 도착합니다.');
    }

    // 마지막 발화 시간 기록
    int lastSpokenMinutes = remainingMinutes;

    // 1분 간격 타이머 설정
    _busAlertTimer = Timer.periodic(const Duration(seconds: 60), (timer) async {
      try {
        if (_getRemainingTimeCallback != null) {
          // 콜백으로 실시간 남은 시간 가져오기
          remainingMinutes = await _getRemainingTimeCallback!();
          debugPrint('콜백에서 가져온 실시간 남은 시간: $remainingMinutes분');
        } else {
          // 콜백이 없으면 이전 값에서 1분 감소
          remainingMinutes--;
          debugPrint('콜백 없음, 남은 시간 감소: $remainingMinutes분');
        }

        // 남은 시간이 음수가 되지 않도록 보정
        if (remainingMinutes < 0) remainingMinutes = 0;

        // 값이 변경되었거나 특정 조건에서만 발화
        if (remainingMinutes != lastSpokenMinutes) {
          if (remainingMinutes <= 0) {
            await speakSafely('$busNo번 버스가 곧 도착합니다.');
            timer.cancel();
            _busAlertTimer = null;
            debugPrint('도착 임박으로 타이머 종료');
          } else {
            await speakSafely('$busNo번 버스가 약 $remainingMinutes분 후 도착 예정입니다.');
            debugPrint('TTS 발화: $busNo번 버스, 남은 시간 $remainingMinutes분');
          }
          lastSpokenMinutes = remainingMinutes;
        } else {
          debugPrint('남은 시간 변화 없음: $remainingMinutes분, 발화 생략');
        }
      } catch (e) {
        debugPrint('타이머 실행 중 오류: $e');
        remainingMinutes--; // 오류 시 기본 감소
      }
    });
  }

  /// 안전한 TTS 추적 중지
  static Future<void> stopTtsTracking([String? busNo]) async {
    try {
      final effectiveBusNo = busNo ?? _currentBusNo;

      _busAlertTimer?.cancel();
      _busAlertTimer = null;
      _getRemainingTimeCallback = null;
      _currentBusNo = null;

      try {
        await _channel.invokeMethod('stopTtsTracking');
      } catch (e) {
        debugPrint('TTS 추적 중지 오류 (무시): $e');
      }

      await SimpleTTSHelper.stopNativeTtsTracking();
      await TTSHelper.stopNativeTtsTracking();

      debugPrint('TTS 추적 완전히 중지됨');

      if (effectiveBusNo != null) {
        await speakSafely('$effectiveBusNo번 버스 승차알람이 중지되었습니다.');
      }
    } catch (e) {
      debugPrint('TTS 추적 중지 오류: $e');
      try {
        final effectiveBusNo = busNo ?? _currentBusNo;
        if (effectiveBusNo != null) {
          await speakSafely('$effectiveBusNo번 버스 승차알람이 중지되었습니다.');
        }
      } catch (_) {}
    }
  }
}
