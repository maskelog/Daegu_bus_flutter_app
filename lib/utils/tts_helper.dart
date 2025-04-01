import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TTSHelper {
  static FlutterTts? _flutterTts;
  static const MethodChannel _channel =
      MethodChannel('com.example.daegu_bus_app/tts');
  static bool _initialized = false;
  static bool _speaking = false;
  static final List<String> _messageQueue = [];

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

        // Google TTS 엔진 우선 설정
        final List<dynamic>? engines = await _flutterTts!.getEngines;
        if (engines != null && engines.isNotEmpty) {
          for (var engine in engines) {
            if (engine.toString().toLowerCase().contains('google')) {
              await _flutterTts!.setEngine(engine.toString());
              debugPrint('TTS 엔진 설정됨: $engine');
              break;
            }
          }
        }

        // 완료 및 에러 콜백 설정
        _flutterTts!.setCompletionHandler(() {
          debugPrint('TTS 발화 완료');
          _speaking = false;
          _processQueue();
        });

        _flutterTts!.setErrorHandler((error) {
          debugPrint('TTS 오류 발생: $error');
          _speaking = false;
          _processQueue();
        });

        // 이어폰 전용 설정 (네이티브 호출)
        await _channel.invokeMethod('forceEarphoneOutput');
      }

      _initialized = true;
      debugPrint('TTS 초기화 완료');
    } catch (e) {
      debugPrint('TTS 초기화 중 오류: $e');
      _initialized = false;
    }
  }

  /// 문장을 작은 단위로 분할하는 헬퍼 메서드
  static List<String> _splitIntoSentences(String text) {
    // 문장 구분자로 분할 (마침표, 느낌표, 물음표 등)
    final sentenceDelimiters = RegExp(r'[.!?]');
    final List<String> sentences = [];

    // 먼저 문장 단위로 분할 시도
    final parts = text.split(sentenceDelimiters);

    if (parts.length > 1) {
      // 문장 구분자가 있으면 그대로 분할
      for (int i = 0; i < parts.length; i++) {
        if (parts[i].trim().isNotEmpty) {
          String sentence = parts[i].trim();
          // 마지막 문장이 아니고 원래 문장에서 구분자가 있었으면 구분자 복원
          if (i < parts.length - 1) {
            final match = sentenceDelimiters.firstMatch(text.substring(
                text.indexOf(parts[i]),
                text.indexOf(parts[i]) + parts[i].length + 5));
            if (match != null && match.group(0) != null) {
              sentence += match.group(0)!;
            }
          }
          sentences.add(sentence);
        }
      }
    } else {
      // 문장 구분자가 없으면 쉼표나 공백으로 분할 시도
      final commaDelimited = text.split(',');
      if (commaDelimited.length > 1 &&
          commaDelimited.every((part) => part.trim().length < 30)) {
        for (var part in commaDelimited) {
          if (part.trim().isNotEmpty) {
            sentences.add(part.trim());
          }
        }
      } else {
        // 길이에 따라 임의로 분할
        const maxLength = 20; // 더 짧은 문장으로 분할
        var remaining = text;
        while (remaining.length > maxLength) {
          // 공백을 기준으로 적절한 분할 지점 찾기
          int cutPoint = maxLength;
          while (cutPoint > 0 && remaining[cutPoint] != ' ') {
            cutPoint--;
          }
          // 공백을 찾지 못했으면 그냥 maxLength에서 자르기
          if (cutPoint == 0) cutPoint = maxLength;

          sentences.add(remaining.substring(0, cutPoint).trim());
          remaining = remaining.substring(cutPoint).trim();
        }
        if (remaining.isNotEmpty) {
          sentences.add(remaining);
        }
      }
    }

    // 빈 문장 필터링 및 결과 반환
    return sentences.where((s) => s.isNotEmpty).toList();
  }

  /// 대기열 처리
  static Future<void> _processQueue() async {
    if (_messageQueue.isEmpty || _speaking || _flutterTts == null) return;

    try {
      _speaking = true;
      final message = _messageQueue.removeAt(0);
      debugPrint('TTS 발화: $message');

      // 이어폰 전용 출력 보장
      await _channel.invokeMethod('forceEarphoneOutput');

      // 우선 네이티브 TTS로 시도
      try {
        await _channel.invokeMethod('speakTTS', {'message': message});
        await Future.delayed(
            const Duration(milliseconds: 300)); // 발화 완료를 위한 짧은 대기
      } catch (e) {
        debugPrint('네이티브 TTS 실패, Flutter TTS 시도: $e');
      }

      // Flutter TTS도 시도 (이중 보장)
      final result = await _flutterTts!.speak(message);
      if (result == 0) {
        debugPrint('TTS 발화 실패, 잠시 후 재시도');
        await Future.delayed(const Duration(milliseconds: 500));
        _speaking = false;
        _processQueue();
      } else {
        // 다음 메시지를 위한 짧은 딜레이
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (e) {
      debugPrint('TTS 대기열 처리 중 오류: $e');
      _speaking = false;
      _processQueue();
    }
  }

  /// 이어폰 전용 TTS 발화
  static Future<void> speakEarphoneOnly(String message,
      {bool priority = false}) async {
    if (!_initialized) await initialize();
    if (_flutterTts == null) return;

    if (priority) {
      _messageQueue.clear();
      if (_speaking) {
        await _flutterTts!.stop();
        _speaking = false;
      }
    }

    // 메시지가 너무 길면 문장 단위로 나누기
    if (message.length > 20) {
      final sentences = _splitIntoSentences(message);
      for (var sentence in sentences) {
        _messageQueue.add(sentence.trim());
        debugPrint('TTS 대기열에 추가 (분할): ${sentence.trim()}');
      }
    } else {
      _messageQueue.add(message);
      debugPrint('TTS 대기열에 추가: $message');
    }

    // 네이티브 speakEarphoneOnly 호출
    try {
      final result = await _channel
          .invokeMethod('speakEarphoneOnly', {'message': message});
      if (result == true) {
        debugPrint('이어폰 전용 TTS 발화 성공: $message');
      } else {
        debugPrint('이어폰/블루투스 연결 없음, 발화 생략');
      }
    } catch (e) {
      debugPrint('네이티브 이어폰 TTS 발화 오류: $e');
    }

    if (!_speaking) {
      await _processQueue();
    }
  }

  /// 버스 알림 발화
  static Future<void> speakBusAlert({
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String? currentStation,
    bool priority = false,
  }) async {
    try {
      if (!_initialized) await initialize();

      // 긴 메시지 대신 짧은 메시지로 분할
      String part1, part2 = "";

      if (remainingMinutes <= 0) {
        // 도착임박
        part1 = '$busNo번 버스가 곧 도착합니다.';
        part2 = '$stationName 정류장 탑승 준비하세요.';
      } else {
        // 남은 시간 있음
        part1 = '$busNo번 버스, $stationName 정류장';
        part2 = '약 $remainingMinutes분 후 도착 예정입니다.';
      }

      // 현재 위치 정보가 있으면 별도 문장으로
      String? part3;
      if (currentStation != null && currentStation.isNotEmpty) {
        part3 = '현재 $currentStation 위치입니다.';
      }

      // 순차적으로 발화
      await speakEarphoneOnly(part1, priority: priority);
      await Future.delayed(const Duration(milliseconds: 500));

      await speakEarphoneOnly(part2, priority: false);
      await Future.delayed(const Duration(milliseconds: 500));

      if (part3 != null) {
        await speakEarphoneOnly(part3, priority: false);
      }

      // 백업으로 네이티브 메서드 직접 호출
      String fullMessage = "$part1 $part2";
      if (part3 != null) fullMessage += " $part3";

      try {
        await _channel.invokeMethod('speakTTS', {'message': fullMessage});
      } catch (backupError) {
        debugPrint('백업 TTS 발화 오류 (무시): $backupError');
      }
    } catch (e) {
      debugPrint('버스 알림 발화 오류: $e');

      // 오류 발생 시 직접 네이티브 호출 시도
      try {
        String message = remainingMinutes <= 0
            ? '$busNo번 버스가 $stationName 정류장에 곧 도착합니다.'
            : '$busNo번 버스가 $stationName 정류장에 약 $remainingMinutes분 후 도착합니다.';

        await _channel.invokeMethod('speakTTS', {'message': message});
      } catch (backupError) {
        debugPrint('백업 TTS 발화 오류: $backupError');
      }
    }
  }

  /// 알림 취소 발화
  static Future<void> speakAlarmCancel(String busNo) async {
    try {
      if (!_initialized) await initialize();

      // 메시지 분할
      final part1 = '$busNo번 버스';
      const part2 = '알림이 취소되었습니다.';

      await speakEarphoneOnly(part1, priority: true);
      await Future.delayed(const Duration(milliseconds: 300));
      await speakEarphoneOnly(part2, priority: false);

      // 백업으로 네이티브 메서드 직접 호출
      try {
        await _channel.invokeMethod('speakTTS', {
          'message': '$busNo번 버스 알림이 취소되었습니다.',
        });
      } catch (backupError) {
        debugPrint('백업 TTS 발화 오류 (무시): $backupError');
      }
    } catch (e) {
      debugPrint('알림 취소 발화 오류: $e');
      // 백업 방법 시도
      try {
        await _channel.invokeMethod('speakTTS', {
          'message': '$busNo번 버스 알림이 취소되었습니다.',
        });
      } catch (backupError) {
        debugPrint('알림 취소 백업 발화 오류: $backupError');
      }
    }
  }

  /// 알람 설정 발화
  static Future<void> speakAlarmSet(String busNo) async {
    try {
      if (!_initialized) await initialize();

      // 메시지 분할
      final part1 = '$busNo번 버스';
      const part2 = '승차 알람이 설정되었습니다.';

      await speakEarphoneOnly(part1, priority: true);
      await Future.delayed(const Duration(milliseconds: 300));
      await speakEarphoneOnly(part2, priority: false);

      // 백업으로 네이티브 메서드 직접 호출
      try {
        await _channel.invokeMethod('speakTTS', {
          'message': '$busNo번 버스 승차 알람이 설정되었습니다.',
        });
      } catch (backupError) {
        debugPrint('백업 TTS 발화 오류 (무시): $backupError');
      }
    } catch (e) {
      debugPrint('알람 설정 발화 오류: $e');
      // 백업 방법 시도
      try {
        await _channel.invokeMethod('speakTTS', {
          'message': '$busNo번 버스 승차 알람이 설정되었습니다.',
        });
      } catch (backupError) {
        debugPrint('알람 설정 백업 발화 오류: $backupError');
      }
    }
  }

  /// 네이티브 TTS 추적 시작
  static Future<void> startNativeTtsTracking({
    required String routeId,
    required String stationId,
    required String busNo,
    required String stationName,
  }) async {
    try {
      if (!_initialized) await initialize();

      // 입력값 유효성 검사 - 빈 문자열이 아닌지 확인
      if (routeId.isEmpty) {
        debugPrint('경고: routeId가 비어있어 busNo 값을 사용합니다');
        routeId = busNo;
      }
      if (stationId.isEmpty) {
        debugPrint('경고: stationId가 비어있어 routeId 값을 사용합니다');
        stationId = routeId;
      }
      if (busNo.isEmpty) {
        debugPrint('경고: busNo가 비어있어 routeId 값을 사용합니다');
        busNo = routeId;
      }

      // 네이티브에 TTS 추적 시작 요청
      debugPrint(
          'TTS 추적 요청 - routeId: $routeId, stationId: $stationId, busNo: $busNo, stationName: $stationName');

      // 분할된 초기 메시지 발화
      final part1 = '$busNo번 버스, $stationName 정류장';
      const part2 = '승차 알림을 시작합니다. 추적을 시작합니다.';

      await speakEarphoneOnly(part1, priority: true);
      await Future.delayed(const Duration(milliseconds: 300));
      await speakEarphoneOnly(part2, priority: false);

      // 네이티브 추적 시작
      await _channel.invokeMethod('startTtsTracking', {
        'routeId': routeId,
        'stationId': stationId,
        'busNo': busNo,
        'stationName': stationName,
      });
      debugPrint('네이티브 TTS 추적 시작: $busNo, $stationName');
    } catch (e) {
      debugPrint('네이티브 TTS 추적 시작 오류: $e');

      // 오류 발생 시 직접 채널 호출 시도
      try {
        await Future.delayed(const Duration(milliseconds: 500));
        final result = await _channel.invokeMethod('speakTTS', {
          'message': '$busNo번 버스 승차 알림을 시작합니다. 현재 추적 중입니다.',
        });
        debugPrint('백업 TTS 발화 결과: $result');
      } catch (backupError) {
        debugPrint('백업 TTS 발화 오류: $backupError');
      }
    }
  }

  /// 네이티브 TTS 추적 중지
  static Future<void> stopNativeTtsTracking() async {
    try {
      await _channel.invokeMethod('stopTtsTracking');
      debugPrint('네이티브 TTS 추적 중지');
    } catch (e) {
      debugPrint('네이티브 TTS 추적 중지 오류: $e');
    }
  }

  /// 일반 발화
  static Future<void> speak(String message, {bool priority = false}) async {
    await speakEarphoneOnly(message, priority: priority);
  }

  /// TTS 정지
  static Future<void> stop() async {
    _speaking = false;
    _messageQueue.clear();

    if (_flutterTts != null) {
      try {
        await _flutterTts!.stop();
        debugPrint('Flutter TTS 정지');
      } catch (e) {
        debugPrint('Flutter TTS 정지 오류: $e');
      }
    }

    try {
      await _channel.invokeMethod('stopTTS');
      debugPrint('네이티브 TTS 정지');
    } catch (e) {
      debugPrint('네이티브 TTS 정지 오류: $e');
    }
  }

  /// 자원 해제
  static Future<void> dispose() async {
    try {
      if (_flutterTts != null) {
        await _flutterTts!.stop();
        _flutterTts = null;
      }
    } catch (e) {
      debugPrint('TTS 자원 해제 오류: $e');
    } finally {
      _initialized = false;
      _speaking = false;
      _messageQueue.clear();
      debugPrint('TTS 모든 자원 초기화 완료');
    }
  }
}
