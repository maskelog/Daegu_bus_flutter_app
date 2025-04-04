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
  // 마지막으로 발화된 남은 시간
  static int lastSpokenMinutes = -1;
  // 마지막 발화 시간
  static DateTime lastSpeakTime = DateTime.now();

  // 마지막으로 알려진 남은 시간을 저장하는 변수
  static int _lastKnownRemainingMinutes = 0;
  // 마지막 발화 시간 기록용 맵
  static final Map<String, DateTime> _lastNotificationTimes = {};

  /// 직접 네이티브 TTS 발화 - 안전한 구현
  static Future<bool> speakSafely(String message) async {
    debugPrint('🔊 TTS 발화 시도: "$message"');

    // 도착 임박 메시지인지 확인 (우선순위 처리용)
    bool isArrivalImminent = message.contains('곧 도착') || message.contains('0분');

    // 먼저 이어폰 출력 강제 설정 시도
    try {
      await _channel.invokeMethod('forceEarphoneOutput');
    } catch (e) {
      debugPrint('이어폰 출력 설정 오류 (무시): $e');
    }

    // TTSHelper 방식으로 메시지 분할 발화 시도
    if (message.length > 15 &&
        !message.contains('번 버스가 약') &&
        !message.contains('번 버스 승차알람')) {
      try {
        // 긴 메시지 문장 분할
        final parts = _splitMessageIntoParts(message);
        if (parts.length > 1) {
          debugPrint('TTS 메시지 분할: ${parts.length}개 부분으로 발화');
          bool success = true;

          // 각 부분 순차 발화
          for (var part in parts) {
            final result = await _speakPart(part, isArrivalImminent);
            if (!result) success = false;
            await Future.delayed(const Duration(milliseconds: 300));
          }

          return success;
        }
      } catch (splitError) {
        debugPrint('메시지 분할 오류 (무시): $splitError');
      }
    }

    // 분할하지 않고 직접 발화
    return await _speakPart(message, isArrivalImminent);
  }

  /// 메시지를 작은 부분으로 분할
  static List<String> _splitMessageIntoParts(String message) {
    // 구분자로 분할 시도
    final sentenceDelimiters = RegExp(r'[.!?,]');
    final parts = message.split(sentenceDelimiters);

    // 결과 필터링 (빈 부분 제거)
    return parts
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  /// 각 메시지 부분 발화 처리
  static Future<bool> _speakPart(String message, bool isPriority) async {
    try {
      // 먼저 SimpleTTSHelper로 시도
      final result = await SimpleTTSHelper.speak(message);
      if (result) {
        debugPrint('🔊 SimpleTTSHelper 발화 성공');
        return true;
      }

      debugPrint('SimpleTTSHelper 발화 실패, TTSHelper 시도');
    } catch (e) {
      debugPrint('SimpleTTSHelper 발화 오류: $e');
    }

    // TTSHelper 방식으로 시도
    try {
      await TTSHelper.speakEarphoneOnly(message, priority: isPriority);
      debugPrint('🔊 TTSHelper.speakEarphoneOnly 발화 성공');
      return true;
    } catch (e2) {
      debugPrint('TTSHelper.speakEarphoneOnly 발화 오류: $e2');
    }

    // 네이티브 채널 직접 호출
    try {
      final result = await _channel.invokeMethod('speakTTS', {
        'message': message,
        'priority': isPriority,
      });

      if (result == true) {
        debugPrint('🔊 네이티브 채널 직접 호출 성공');
        return true;
      }
    } catch (e3) {
      debugPrint('네이티브 채널 직접 호출 오류: $e3');
    }

    // 모든 방법 실패한 경우 (도착 임박 시에만) 마지막 방법으로 재시도
    if (isPriority) {
      try {
        // 도착 임박 메시지는 30초 후 재발화 강제 트리거
        lastSpeakTime = DateTime.now().subtract(const Duration(seconds: 30));
        lastSpokenMinutes = -1;

        // 최후의 수단: 이어폰 전용 발화
        final result = await _channel.invokeMethod('speakEarphoneOnly', {
          'message': message,
        });
        debugPrint('🔊 최후의 수단 speakEarphoneOnly 결과: $result');
        return result == true;
      } catch (e4) {
        debugPrint('최후의 수단 발화 실패: $e4');
      }
    }

    return false;
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
    required int remainingMinutes,
    BusRemainingTimeCallback? getRemainingTimeCallback,
  }) async {
    try {
      // 기존 타이머가 있다면 취소
      _busAlertTimer?.cancel();
      _busAlertTimer = null;

      // 유효성 검사 및 기본값 설정
      String effectiveBusNo = busNo.isEmpty ? '알 수 없음' : busNo;
      String effectiveRouteId = routeId.isEmpty ? effectiveBusNo : routeId;

      // 초기 시간 값을 캐싱
      _lastKnownRemainingMinutes = remainingMinutes;
      lastSpokenMinutes = -1; // 초기화하여 첫 발화가 확실히 되도록 함
      lastSpeakTime = DateTime.now()
          .subtract(const Duration(seconds: 60)); // 초기 발화를 위해 시간 조정

      // 현재 버스 번호 저장
      _currentBusNo = effectiveBusNo;

      // 실시간 버스 정보 로깅
      debugPrint(
          '트래킹 시작 시 버스 정보: 버스=$effectiveBusNo, 정류장=$stationName, 노선ID=$effectiveRouteId, 정류장ID=$stationId');

      // 콜백 함수 설정 및 오류 처리 강화
      _getRemainingTimeCallback = getRemainingTimeCallback != null
          ? () async {
              try {
                final time = await getRemainingTimeCallback();
                debugPrint('콜백에서 가져온 남은 시간: $time분');
                return time;
              } catch (e) {
                debugPrint('콜백 실행 중 오류: $e');
                return _lastKnownRemainingMinutes; // 오류 시 이전 값 유지
              }
            }
          : null;

      // 초기 발화 실행
      await checkAndSpeak();

      // 실시간 정보 수신을 위한 타이머 설정 (15초 간격)
      _busAlertTimer =
          Timer.periodic(const Duration(seconds: 15), (timer) async {
        try {
          debugPrint('\n--- 실시간 버스 정보 업데이트 처리 시작 ---');
          int previousMinutes = _lastKnownRemainingMinutes;

          if (_getRemainingTimeCallback != null) {
            try {
              final newMinutes = await _getRemainingTimeCallback!();
              debugPrint('콜백에서 가져온 실시간 남은 시간: $newMinutes분');

              if (previousMinutes != newMinutes) {
                debugPrint('시간 변경 감지: $previousMinutes분 → $newMinutes분');
                updateTrackedBusTime(newMinutes);
              }
            } catch (callbackError) {
              debugPrint('콜백 오류 발생: $callbackError');
            }
          }

          // 항상 발화 조건 체크 (콜백 오류 시에도)
          await checkAndSpeak();
        } catch (e) {
          debugPrint('타이머 실행 중 오류: $e');
        }
      });

      debugPrint('TTS 트래킹 시작 완료');
    } catch (e) {
      debugPrint('TTS 트래킹 시작 중 오류: $e');
      // 오류 발생 시에도 타이머는 계속 실행되도록 함
      _busAlertTimer?.cancel();
      _busAlertTimer = null;
    }
  }

  /// 발화 조건 체크 및 실행
  static Future<void> checkAndSpeak() async {
    if (_currentBusNo == null) return;

    final now = DateTime.now();
    final timeSinceLastSpeak = now.difference(lastSpeakTime).inSeconds;

    // 도착 임박(0분) 특별 처리
    if (_lastKnownRemainingMinutes == 0) {
      final zeroKey = "${_currentBusNo}_0";
      final lastZeroTime = _lastNotificationTimes[zeroKey];

      if (lastZeroTime == null || now.difference(lastZeroTime).inSeconds > 30) {
        debugPrint('⚡️ 도착 임박 알림 발화');
        await speakSafely('$_currentBusNo번 버스가 곧 도착합니다. 탑승 준비하세요.');
        _lastNotificationTimes[zeroKey] = now;
        lastSpeakTime = now;
        lastSpokenMinutes = 0;
        return;
      }
    }

    // 일반 시간대 발화 조건
    if (_lastKnownRemainingMinutes != lastSpokenMinutes &&
        timeSinceLastSpeak >= 45) {
      debugPrint('⚡️ 일반 시간대 알림 발화: $_lastKnownRemainingMinutes분');
      await speakSafely(
          '$_currentBusNo번 버스가 약 $_lastKnownRemainingMinutes분 후 도착 예정입니다.');
      lastSpeakTime = now;
      lastSpokenMinutes = _lastKnownRemainingMinutes;
    }
  }

  /// 버스 도착 시간 업데이트 및 TTS 발화
  static Future<void> updateTrackedBusTime(int remainingMinutes) async {
    if (_currentBusNo == null) return;

    // 중요 시간대 체크 (10, 8, 5, 3, 2, 1, 0분)
    final importantTimes = [10, 8, 5, 3, 2, 1, 0];
    final isImportantTime = importantTimes.contains(remainingMinutes);

    // 시간이 큰 폭으로 변경되었거나 중요 시간대인 경우 즉시 발화
    if (isImportantTime || (lastSpokenMinutes - remainingMinutes >= 3)) {
      debugPrint('TTS 발화 조건 충족: 현재=$remainingMinutes분, 이전=$lastSpokenMinutes분');

      // 마지막 발화 시간 초기화하여 즉시 발화 보장
      lastSpeakTime = DateTime(2000);
      lastSpokenMinutes = remainingMinutes;

      // 즉시 발화 실행
      await _speakBusTime(remainingMinutes);
    }

    // 마지막 알려진 시간 업데이트
    _lastKnownRemainingMinutes = remainingMinutes;
  }

  /// 버스 도착 시간 TTS 발화
  static Future<void> _speakBusTime(int remainingMinutes) async {
    if (_currentBusNo == null) return;

    final now = DateTime.now();
    final timeSinceLastSpeak = now.difference(lastSpeakTime).inSeconds;

    // 마지막 발화로부터 30초가 지났거나, 중요 시간대인 경우 발화
    if (timeSinceLastSpeak >= 30 ||
        [10, 8, 5, 3, 2, 1, 0].contains(remainingMinutes)) {
      try {
        String message;
        if (remainingMinutes <= 0) {
          message = "$_currentBusNo 번 버스가 곧 도착합니다. 탑승 준비하세요.";
        } else {
          message = "$_currentBusNo 번 버스가 약 $remainingMinutes 분 후 도착 예정입니다.";
        }

        await speakSafely(message);
        lastSpeakTime = now;
        lastSpokenMinutes = remainingMinutes;
        debugPrint('TTS 발화 성공: $message');
      } catch (e) {
        debugPrint('TTS 발화 오류: $e');
      }
    }
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
