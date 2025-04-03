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
  // 마지막으로 알려진 남은 시간을 저장하는 변수
  static int _lastKnownRemainingMinutes = 0;
  // 마지막 발화 시간 기록용 맵
  static final Map<String, DateTime> _lastNotificationTimes = {};

  static Future<void> startTtsTracking({
    required String routeId,
    required String stationId,
    required String busNo,
    required String stationName,
    required int remainingMinutes, // 초기 남은 시간을 필수로 설정
    BusRemainingTimeCallback? getRemainingTimeCallback, // 실시간 업데이트 콜백
  }) async {
    try {
      // 유효성 검사 및 기본값 설정
      String effectiveBusNo = busNo.isEmpty ? '알 수 없음' : busNo;
      String effectiveRouteId = routeId.isEmpty ? effectiveBusNo : routeId;

      // 초기 시간 값을 캐싱
      _lastKnownRemainingMinutes = remainingMinutes;

      // 현재 버스 번호 저장
      _currentBusNo = effectiveBusNo;

      // 콜백 함수 저장 - 콜백 래퍼 추가
      _getRemainingTimeCallback = getRemainingTimeCallback != null
          ? () async {
              try {
                final newTime = await getRemainingTimeCallback();
                _lastKnownRemainingMinutes = newTime; // 새 값 캐싱
                debugPrint('콜백에서 가져온 실시간 남은 시간(래핑됨): $newTime분');
                return newTime;
              } catch (e) {
                debugPrint('시간 콜백 오류: $e');
                return _lastKnownRemainingMinutes;
              }
            }
          : null;

      // 시작 메시지 발화
      await speakSafely('$effectiveBusNo번 버스 승차알람이 설정되었습니다.');

      debugPrint(
          '네이티브 TTS 추적 시작됨: $effectiveBusNo, 초기 남은 시간: $remainingMinutes분, 노선ID: $effectiveRouteId');

      // 주기적인 TTS 알림 설정
      _setupPeriodicBusAlertWithTime(
          effectiveBusNo, stationName, remainingMinutes);
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

    // 키 생성 (TTS 중복 방지용)
    final baseKey = "${busNo}_$stationName";

    // 초기 발화 및 초기화
    if (remainingMinutes > 0) {
      speakSafely('$busNo번 버스가 약 $remainingMinutes분 후 도착 예정입니다.');
      _lastNotificationTimes["${baseKey}_$remainingMinutes"] = DateTime.now();
      lastSpokenMinutes = remainingMinutes; // 초기화
    } else {
      speakSafely('$busNo번 버스가 곧 도착합니다.');
      _lastNotificationTimes["${baseKey}_0"] = DateTime.now();
      lastSpokenMinutes = 0; // 초기화
    }

    // 마지막 발화 시간 타임스탬프 저장
    // 주요 시간대 정의 (알림을 발화할 중요 시점) - 더 많은 시점 추가
    final List<int> importantTimes = [15, 12, 10, 8, 7, 6, 5, 4, 3, 2, 1, 0];
    // 마지막 발화 타임스탬프 저장
    DateTime lastSpeakTime = DateTime.now();

    // 20초 간격 타이머 설정 (더 빠른 간격으로 체크)
    _busAlertTimer = Timer.periodic(const Duration(seconds: 20), (timer) async {
      try {
        int previousMinutes = remainingMinutes;

        if (_getRemainingTimeCallback != null) {
          // 콜백으로 실시간 남은 시간 가져오기
          try {
            remainingMinutes = await _getRemainingTimeCallback!();
            debugPrint('콜백에서 가져온 실시간 남은 시간: $remainingMinutes분');
          } catch (callbackError) {
            debugPrint('콜백 오류 발생, 직접 계산: $callbackError');
            // 콜백 실패시 직접 계산
            remainingMinutes =
                _decrementRemainingTime(remainingMinutes, 0.33); // 20초는 0.33분
          }
        } else {
          // 콜백이 없으면 20초씩 감소 (20초 타이머에 맞춤)
          remainingMinutes = _decrementRemainingTime(remainingMinutes, 0.33);
          debugPrint('콜백 없음, 남은 시간 감소: $remainingMinutes분');
        }

        // 남은 시간이 음수가 되지 않도록 보정
        if (remainingMinutes < 0) remainingMinutes = 0;

        // 시간이 다르거나 근접할 때 처리 (반올림 오차 감안)
        bool minutesChanged = remainingMinutes != previousMinutes;
        bool minutesCloseEnough =
            (remainingMinutes - previousMinutes).abs() <= 1;

        if (minutesChanged ||
            (importantTimes.contains(remainingMinutes) && minutesCloseEnough)) {
          // 발화 조건 체크
          bool isImportantTime = importantTimes.contains(remainingMinutes);
          bool timeElapsed =
              DateTime.now().difference(lastSpeakTime).inSeconds >=
                  45; // 45초 이상 경과
          bool significantChange =
              (previousMinutes - remainingMinutes).abs() >= 1; // 1분 이상 차이

          // 중요 시간대이거나, 시간이 크게 변경되었을 때 발화
          // 중요 시간대는 조금 더 적극적으로 발화 처리 (중복 방지)
          final ttsKey = "${baseKey}_$remainingMinutes";
          bool alreadyNotified = _lastNotificationTimes.containsKey(ttsKey) &&
              DateTime.now()
                      .difference(_lastNotificationTimes[ttsKey]!)
                      .inSeconds <
                  60; // 1분 이내 발화 여부

          debugPrint('발화 조건 평가 - 중요시간: $isImportantTime, 시간경과: $timeElapsed, '
              '변화량: ${previousMinutes - remainingMinutes}, 이미알림: $alreadyNotified');

          if ((isImportantTime || significantChange) &&
              timeElapsed &&
              !alreadyNotified) {
            if (remainingMinutes <= 0) {
              await speakSafely('$busNo번 버스가 곧 도착합니다.');
              _lastNotificationTimes["${baseKey}_0"] = DateTime.now();
              // 마지막 발화 시간 갱신
              lastSpeakTime = DateTime.now();
              lastSpokenMinutes = 0;

              timer.cancel();
              _busAlertTimer = null;
              debugPrint('도착 임박으로 타이머 종료');
            } else if (remainingMinutes != lastSpokenMinutes) {
              await speakSafely('$busNo번 버스가 약 $remainingMinutes분 후 도착 예정입니다.');
              _lastNotificationTimes[ttsKey] = DateTime.now();

              // 마지막 발화 시간 갱신
              lastSpeakTime = DateTime.now();
              lastSpokenMinutes = remainingMinutes;
              debugPrint('TTS 발화 성공: $busNo번 버스, 남은 시간 $remainingMinutes분');
            }
          } else {
            debugPrint('발화 조건 미충족으로 TTS 생략');
          }
        } else {
          debugPrint('남은 시간 변화 없음: $remainingMinutes분, 발화 생략');
        }
      } catch (e) {
        debugPrint('타이머 실행 중 오류: $e');
        // 오류 시에도 시간은 감소
        remainingMinutes = _decrementRemainingTime(remainingMinutes, 0.33);
      }
    });
  }

// 남은 시간을 감소시키는 헬퍼 메서드 (단위 시간만큼 감소)
  static int _decrementRemainingTime(
      int currentMinutes, double decrementAmount) {
    if (currentMinutes <= 0) return 0;

    // 소수점 처리를 위해 실수로 계산 후 반올림
    double newValue = currentMinutes - decrementAmount;
    // 더 정확한 반올림을 위해 소수점 두 자리에서 반올림
    newValue = (newValue * 100).round() / 100;
    return newValue > 0 ? newValue.round() : 0;
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
