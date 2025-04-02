import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:daegu_bus_app/screens/profile_screen.dart';
import 'package:daegu_bus_app/utils/alarm_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import '../models/bus_arrival.dart';
import '../services/notification_service.dart';
import '../utils/tts_helper.dart';

class AlarmData {
  final String busNo;
  final String stationName;
  final int remainingMinutes;
  final String routeId;
  final DateTime scheduledTime;
  DateTime targetArrivalTime;
  final String? currentStation;
  int _currentRemainingMinutes;

  void updateTargetArrivalTime(DateTime newTargetTime) {
    targetArrivalTime = newTargetTime;
  }

  AlarmData({
    required this.busNo,
    required this.stationName,
    required this.remainingMinutes,
    required this.routeId,
    required this.scheduledTime,
    DateTime? targetArrivalTime,
    this.currentStation,
  })  : targetArrivalTime =
            targetArrivalTime ?? scheduledTime.add(const Duration(minutes: 3)),
        _currentRemainingMinutes = remainingMinutes;

  Map<String, dynamic> toJson() => {
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'routeId': routeId,
        'scheduledTime': scheduledTime.toIso8601String(),
        'targetArrivalTime': targetArrivalTime.toIso8601String(),
        'currentStation': currentStation,
      };

  factory AlarmData.fromJson(Map<String, dynamic> json) {
    final scheduledTime = DateTime.parse(json['scheduledTime']);
    final remainingMinutes = json['remainingMinutes'];
    return AlarmData(
      busNo: json['busNo'],
      stationName: json['stationName'],
      remainingMinutes: remainingMinutes,
      routeId: json['routeId'] ?? '',
      scheduledTime: scheduledTime,
      targetArrivalTime: json.containsKey('targetArrivalTime')
          ? DateTime.parse(json['targetArrivalTime'])
          : scheduledTime.add(const Duration(minutes: 3)),
      currentStation: json['currentStation'],
    );
  }

  int getCurrentAlarmMinutes() {
    final now = DateTime.now();
    final difference = scheduledTime.difference(now);
    return difference.inSeconds > 0 ? (difference.inSeconds / 60).ceil() : 0;
  }

  int getCurrentArrivalMinutes() {
    return _currentRemainingMinutes;
  }

  void updateRemainingMinutes(int minutes) {
    _currentRemainingMinutes = minutes;
  }

  int getAlarmId() {
    return "${busNo}_${stationName}_$routeId".hashCode;
  }
}

// 캐시된 버스 정보 클래스
class CachedBusInfo {
  final String busNo;
  final String routeId;
  int remainingMinutes;
  String currentStation;
  DateTime lastUpdated;

  CachedBusInfo({
    required this.busNo,
    required this.routeId,
    required this.remainingMinutes,
    required this.currentStation,
    required this.lastUpdated,
  });

  int getRemainingMinutes() {
    // 마지막 업데이트로부터 경과 시간 계산
    final elapsedMinutes = DateTime.now().difference(lastUpdated).inMinutes;

    // 현재 예상 남은 시간 = 마지막으로 알려진 남은 시간 - 경과 시간
    final currentEstimate = remainingMinutes - elapsedMinutes;

    // 음수가 되지 않도록 함
    return currentEstimate > 0 ? currentEstimate : 0;
  }
}

class AlarmService extends ChangeNotifier {
  List<AlarmData> _activeAlarms = [];
  Timer? _refreshTimer;
  final List<AlarmData> _alarmCache = [];
  bool _initialized = false;
  // BusInfo 객체 대신 CachedBusInfo 객체 사용
  final Map<String, CachedBusInfo> _cachedBusInfo = {};
  MethodChannel? _methodChannel;

  static final AlarmService _instance = AlarmService._internal();
  bool _isInTrackingMode = false;
  bool get isInTrackingMode => _isInTrackingMode;
  final Set<String> _processedNotifications = {};

  factory AlarmService() {
    return _instance;
  }

  AlarmService._internal() {
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    await loadAlarms();
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      loadAlarms();
    });
    _setupMethodChannel();
    await _registerBusArrivalReceiver();
    _initialized = true;
  }

  void _setupMethodChannel() {
    _methodChannel = const MethodChannel('com.example.daegu_bus_app/bus_api');
    _methodChannel?.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onBusArrival':
          try {
            final Map<String, dynamic> data =
                jsonDecode(call.arguments as String);
            final busNumber = data['busNumber'] as String;
            final stationName = data['stationName'] as String;
            final currentStation = data['currentStation'] as String;
            final routeId = data['routeId'] as String? ?? '';

            debugPrint(
                '버스 도착 이벤트 수신: $busNumber, $stationName, $currentStation');

            final notificationKey = '${busNumber}_${stationName}_$routeId';
            if (_isNotificationProcessed(busNumber, stationName, routeId)) {
              debugPrint('이미 처리된 알림입니다: $notificationKey');
              return true;
            }

            // TTS 초기화 확인 및 재시도
            try {
              await TTSHelper.initialize();
              debugPrint('TTS 엔진 초기화됨');
            } catch (ttsInitError) {
              debugPrint('TTS 초기화 오류: $ttsInitError');
            }

            // 알림과 TTS를 동시에 실행
            await Future.wait([
              // 알림 표시
              NotificationService()
                  .showBusArrivingSoon(
                busNo: busNumber,
                stationName: stationName,
                currentStation: currentStation,
              )
                  .catchError((error) {
                debugPrint('알림 표시 오류: $error');
                return false;
              }),

              // TTS로 알림 (3번 시도)
              _retryTTS(busNumber, stationName, currentStation),
            ]);

            _markNotificationAsProcessed(busNumber, stationName, routeId);
            return true;
          } catch (e) {
            debugPrint('버스 도착 이벤트 처리 오류: $e');

            // 예외가 발생해도 TTS 시도
            try {
              final busNumber =
                  jsonDecode(call.arguments as String)['busNumber']
                          as String? ??
                      "알 수 없음";
              final stationName =
                  jsonDecode(call.arguments as String)['stationName']
                          as String? ??
                      "알 수 없음";
              TTSHelper.speak(
                  "$busNumber 번 버스가 $stationName 정류장에 곧 도착합니다. 탑승 준비하세요.",
                  priority: true);
            } catch (ttsError) {
              debugPrint('예외 상황에서 TTS 시도 실패: $ttsError');
            }

            return false;
          }

        case 'onBusLocationUpdate':
          try {
            final Map<String, dynamic> data =
                jsonDecode(call.arguments as String);
            final String busNumber = data['busNumber'] ?? '';
            final String currentStation = data['currentStation'] ?? '';
            final int remainingMinutes = data['remainingMinutes'] ?? 0;
            final String routeId = data['routeId'] ?? '';

            debugPrint(
                '버스 위치 업데이트: $busNumber, 남은 시간: $remainingMinutes분, 현재 위치: $currentStation');

            // 캐시 업데이트
            _updateBusLocationCache(
                busNumber, routeId, remainingMinutes, currentStation);

            // 남은 시간이 5분 이하일 때 TTS 알림
            if (remainingMinutes > 0 && remainingMinutes <= 5) {
              // 키 생성
              final ttsKey = '${busNumber}_${routeId}_$remainingMinutes';
              // 동일한 메시지가 2분 내에 반복되지 않도록 체크
              if (!_processedNotifications.contains(ttsKey)) {
                TTSHelper.speak(
                    "$busNumber 번 버스가 약 $remainingMinutes 분 후 도착 예정입니다. 현재 $currentStation 위치입니다.");
                _processedNotifications.add(ttsKey);
                // 2분 후 키 제거 - 같은 메시지를 또 읽을 수 있도록
                Future.delayed(const Duration(minutes: 2), () {
                  _processedNotifications.remove(ttsKey);
                });
              }
            }

            // UI 갱신 알림
            notifyListeners();
            return true;
          } catch (e) {
            debugPrint('버스 위치 업데이트 처리 오류: $e');
            return false;
          }

        case 'onTrackingCancelled':
          _isInTrackingMode = false;
          _processedNotifications.clear();
          notifyListeners();
          return true;

        case 'stopBusMonitoringService':
          _isInTrackingMode = false;
          notifyListeners();
          return true;
      }

      return null;
    });
  }

  Future<void> _registerBusArrivalReceiver() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarms = prefs.getStringList('auto_alarms') ?? [];
      for (var json in alarms) {
        final data = jsonDecode(json);
        final autoAlarm = AutoAlarm.fromJson(data);
        if (autoAlarm.isActive) {
          await _methodChannel?.invokeMethod('registerBusArrivalReceiver', {
            'stationId': autoAlarm.stationId,
            'stationName': autoAlarm.stationName,
            'routeId': autoAlarm.routeId,
          });
        }
      }
      debugPrint('버스 도착 이벤트 리시버 등록 완료');
    } catch (e) {
      debugPrint('버스 도착 이벤트 리시버 등록 오류: $e');
    }
  }

  Future<bool> startBusMonitoringService({
    required String stationId,
    required String stationName,
    String routeId = '',
  }) async {
    try {
      if (_isInTrackingMode) {
        await stopBusMonitoringService();
      }

      // routeId가 빈 문자열이면 stationId를 사용
      String effectiveRouteId = routeId.isEmpty ? stationId : routeId;

      // TTS 추적을 먼저 시작
      try {
        debugPrint('🚌 버스 추적 알림 시작: $stationId, $effectiveRouteId');
        await _methodChannel?.invokeMethod('startTtsTracking', {
          'routeId': effectiveRouteId,
          'stationId': stationId,
          'busNo': effectiveRouteId,
          'stationName': stationName
        });
      } catch (e) {
        debugPrint('TTS 추적 시작 오류 (계속 진행): $e');
      }

      final result = await _methodChannel?.invokeMethod(
        'startBusMonitoringService',
        {
          'stationId': stationId,
          'routeId': effectiveRouteId,
          'stationName': stationName,
        },
      );
      if (result == true) {
        _isInTrackingMode = true;
        _markExistingAlarmsAsTracked(effectiveRouteId);
        notifyListeners();
      }
      debugPrint('버스 모니터링 서비스 시작: $result, 트래킹 모드: $_isInTrackingMode');
      return result == true;
    } catch (e) {
      debugPrint('버스 모니터링 서비스 시작 오류: $e');
      // 오류가 발생해도 기본적인 추적 상태로 설정
      _isInTrackingMode = true;
      notifyListeners();
      return true; // 실패해도 true를 반환하여 진행
    }
  }

  Future<bool> stopBusMonitoringService() async {
    try {
      final result =
          await _methodChannel?.invokeMethod('stopBusMonitoringService');
      if (result == true) {
        _isInTrackingMode = false;
        _processedNotifications.clear();
        notifyListeners();
      }
      await NotificationService().cancelOngoingTracking();
      debugPrint('버스 모니터링 서비스 중지: $result');
      return result == true;
    } catch (e) {
      debugPrint('버스 모니터링 서비스 중지 오류: $e');
      return false;
    }
  }

  bool _isNotificationProcessed(String busNo, String stationName,
      [String? routeId]) {
    final key = '${busNo}_${stationName}_${routeId ?? ""}';
    return _processedNotifications.contains(key);
  }

  void _markNotificationAsProcessed(String busNo, String stationName,
      [String? routeId]) {
    final key = '${busNo}_${stationName}_${routeId ?? ""}';
    _processedNotifications.add(key);
    if (_processedNotifications.length > 100) {
      _processedNotifications.remove(_processedNotifications.first);
    }
  }

  List<AlarmData> get activeAlarms => _activeAlarms;

  // BusInfo 클래스가 아닌 CachedBusInfo를 반환하도록 수정
  CachedBusInfo? getCachedBusInfo(String busNo, String routeId) {
    final key = "${busNo}_$routeId";
    return _cachedBusInfo[key];
  }
  
  // 현재 추적 중인 버스 정보 가져오기
  Map<String, dynamic>? getTrackingBusInfo() {
    if (!_isInTrackingMode) return null;
    
    // 해당 알람 정보가 있는 경우 우선 사용
    if (_activeAlarms.isNotEmpty) {
      final alarm = _activeAlarms.first;
      final key = "${alarm.busNo}_${alarm.routeId}";
      final cachedInfo = _cachedBusInfo[key];
      
      // 캐시된 실시간 정보가 있는 경우
      if (cachedInfo != null) {
        final remainingMinutes = cachedInfo.getRemainingMinutes();
        final isRecent = DateTime.now().difference(cachedInfo.lastUpdated).inMinutes < 10;
        
        if (isRecent) {
          return {
            'busNumber': alarm.busNo,
            'stationName': alarm.stationName,
            'remainingMinutes': remainingMinutes,
            'currentStation': cachedInfo.currentStation,
            'routeId': alarm.routeId,
          };
        }
      }
      
      // 캐시된 정보가 없거나 최신 정보가 아니면 알람에서 가져오기
      return {
        'busNumber': alarm.busNo,
        'stationName': alarm.stationName,
        'remainingMinutes': alarm.getCurrentArrivalMinutes(),
        'currentStation': alarm.currentStation ?? '',
        'routeId': alarm.routeId,
      };
    }
    
    // 알람이 없는 경우, 캡시된 정보에서 최신 것 찾기
    for (var entry in _cachedBusInfo.entries) {
      final key = entry.key;
      final cachedInfo = entry.value;
      
      // 현재 시간 기준으로 남은 시간 계산
      final remainingMinutes = cachedInfo.getRemainingMinutes();
      
      // 만약 정보가 10분 이내로 업데이트되었다면 유효한 정보로 간주 
      final isRecent = DateTime.now().difference(cachedInfo.lastUpdated).inMinutes < 10;
      
      if (isRecent) {
        final parts = key.split('_');
        if (parts.length >= 1) {
          final busNumber = parts[0];
          final routeId = parts.length > 1 ? parts[1] : '';
          
          // 정류장 이름 찾기 (없는 경우 기본값)
          String stationName = '정류장';
          
          return {
            'busNumber': busNumber,
            'stationName': stationName,
            'remainingMinutes': remainingMinutes,
            'currentStation': cachedInfo.currentStation,
            'routeId': routeId,
          };
        }
      }
    }
    
    return null;
  }

  // BusArrival.dart의 BusInfo 객체를 사용하는 메서드
  void updateBusInfoCache(
      String busNo, String routeId, BusInfo busInfo, int remainingTime) {
    final key = "${busNo}_$routeId";

    // CachedBusInfo로 변환하여 저장
    CachedBusInfo cachedInfo = CachedBusInfo(
      busNo: busNo,
      routeId: routeId,
      remainingMinutes: remainingTime,
      currentStation: busInfo.currentStation,
      lastUpdated: DateTime.now(),
    );

    bool shouldUpdate = true;
    CachedBusInfo? existingInfo = _cachedBusInfo[key];

    if (existingInfo != null) {
      shouldUpdate = existingInfo.getRemainingMinutes() != remainingTime ||
          existingInfo.currentStation != busInfo.currentStation;
    }

    if (shouldUpdate) {
      _cachedBusInfo[key] = cachedInfo;
      bool alarmUpdated = false;

      for (var alarm in _activeAlarms) {
        if ("${alarm.busNo}_${alarm.routeId}" == key) {
          alarm.updateRemainingMinutes(remainingTime);
          alarm.updateTargetArrivalTime(
              DateTime.now().add(Duration(minutes: remainingTime)));
          alarmUpdated = true;
        }
      }

      if (alarmUpdated) {
        debugPrint('BusInfo Cache 업데이트: $busNo, 남은 시간: $remainingTime분');
        // 알림도 업데이트
        _updateTrackingNotification(busNo, routeId);
        notifyListeners();
      }
    }
  }

  // 버스 위치 정보 캐시 업데이트 헬퍼 메서드
  void _updateBusLocationCache(String busNo, String routeId,
      int remainingMinutes, String currentStation) {
    // 캐시 키 생성
    final cacheKey = "${busNo}_$routeId";

    // 기존 캐시 정보 확인
    final existingBusInfo = _cachedBusInfo[cacheKey];

    // 캐시 업데이트
    if (existingBusInfo != null) {
      // 기존 정보 업데이트
      existingBusInfo.remainingMinutes = remainingMinutes;
      existingBusInfo.currentStation = currentStation;
      existingBusInfo.lastUpdated = DateTime.now();
      _cachedBusInfo[cacheKey] = existingBusInfo;

      debugPrint(
          '버스 위치 캐시 업데이트: $busNo, 남은 시간: $remainingMinutes분, 위치: $currentStation');
    } else {
      // 새 정보 생성 및 저장
      final cachedInfo = CachedBusInfo(
        busNo: busNo,
        routeId: routeId,
        remainingMinutes: remainingMinutes,
        currentStation: currentStation,
        lastUpdated: DateTime.now(),
      );
      _cachedBusInfo[cacheKey] = cachedInfo;

      debugPrint(
          '버스 위치 캐시 생성: $busNo, 남은 시간: $remainingMinutes분, 위치: $currentStation');
    }

    // 관련 알람의 남은 시간 업데이트
    for (var alarm in _activeAlarms) {
      if (alarm.busNo == busNo && alarm.routeId == routeId) {
        alarm.updateRemainingMinutes(remainingMinutes);
        alarm.updateTargetArrivalTime(
            DateTime.now().add(Duration(minutes: remainingMinutes)));
        debugPrint('알람 정보 업데이트: ${alarm.busNo}, 남은 시간: $remainingMinutes분');
      }
    }

    // 알림도 업데이트
    _updateTrackingNotification(busNo, routeId);
  }

  // 추적 알림 업데이트 요청
  Future<void> _updateTrackingNotification(String busNo, String routeId) async {
    try {
      final cacheKey = "${busNo}_$routeId";
      final cachedInfo = _cachedBusInfo[cacheKey];
      if (cachedInfo == null) {
        debugPrint('캐시된 버스 정보 없음: $cacheKey');
        return;
      }

      // 관련 알람 찾기
      AlarmData? relatedAlarm;
      for (var alarm in _activeAlarms) {
        if (alarm.busNo == busNo && alarm.routeId == routeId) {
          relatedAlarm = alarm;
          break;
        }
      }

      if (relatedAlarm != null) {
        debugPrint(
            '버스 추적 알림 업데이트 호출: $busNo, 남은 시간: ${cachedInfo.remainingMinutes}분, 위치: ${cachedInfo.currentStation}');

        try {
          // 이제 bus_api 채널에 메서드가 있음
          await _methodChannel?.invokeMethod('updateBusTrackingNotification', {
            'busNo': busNo,
            'stationName': relatedAlarm.stationName,
            'remainingMinutes': cachedInfo.remainingMinutes,
            'currentStation': cachedInfo.currentStation,
          });
          debugPrint('버스 추적 알림 업데이트 성공: $busNo');
        } catch (e) {
          debugPrint('버스 추적 알림 업데이트 오류: $e');
        }
      } else {
        debugPrint('관련 알람을 찾을 수 없음: $busNo, $routeId');
      }
    } catch (e) {
      debugPrint('버스 추적 알림 업데이트 요청 오류: $e');
    }
  }

  void _markExistingAlarmsAsTracked(String routeId) {
    for (var alarm in _activeAlarms) {
      if (alarm.routeId == routeId) {
        final notificationKey =
            '${alarm.busNo}_${alarm.stationName}_${alarm.routeId}';
        _processedNotifications.add(notificationKey);
      }
    }
  }

  // loadAlarms 메소드에서 자동 알람은 로드하지 않도록 수정
  Future<void> loadAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      // 중요: auto_alarm_ 접두사가 붙은 키는 제외하고 일반 알람만 로드
      final alarmKeys = keys
          .where((key) =>
              key.startsWith('alarm_') && !key.startsWith('auto_alarm_'))
          .toList();

      debugPrint('알람 로드 시작: ${alarmKeys.length}개');
      _activeAlarms = [];
      final keysToRemove = <String>[];

      for (var key in alarmKeys) {
        try {
          final String? jsonString = prefs.getString(key);
          if (jsonString == null || jsonString.isEmpty) {
            keysToRemove.add(key);
            continue;
          }

          final Map<String, dynamic> jsonData = jsonDecode(jsonString);
          final AlarmData alarm = AlarmData.fromJson(jsonData);

          final now = DateTime.now();
          if (alarm.targetArrivalTime
              .isBefore(now.subtract(const Duration(minutes: 5)))) {
            debugPrint('만료된 알람 발견: ${alarm.busNo}, ${alarm.stationName}');
            keysToRemove.add(key);
            continue;
          }

          _activeAlarms.add(alarm);
        } catch (e) {
          debugPrint('알람 데이터 손상 ($key): $e');
          keysToRemove.add(key);
        }
      }

      for (var key in keysToRemove) {
        await prefs.remove(key);
        debugPrint('불필요한 알람 키 정리: $key');
      }

      debugPrint('알람 로드 완료: ${_activeAlarms.length}개');
      notifyListeners();
    } catch (e) {
      debugPrint('알람 로드 오류: $e');
    }
  }

  // TTS 재시도 함수 추가
  Future<void> _retryTTS(
      String busNumber, String stationName, String currentStation) async {
    const maxRetries = 3;
    Exception? lastError;

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        await TTSHelper.speakBusAlert(
          busNo: busNumber,
          stationName: stationName,
          remainingMinutes: 0,
          currentStation: currentStation,
          priority: true,
        );
        debugPrint('TTS 실행 성공 (시도 ${attempt + 1}/$maxRetries)');
        return; // 성공하면 즉시 반환
      } catch (e) {
        lastError = e as Exception;
        debugPrint('TTS 실행 오류 (시도 ${attempt + 1}/$maxRetries): $e');

        // 백업 메시지 전달 시도
        try {
          await TTSHelper.speak(
              "$busNumber 번 버스가 $stationName 정류장에 곧 도착합니다. 탑승 준비하세요.",
              priority: true);
          debugPrint('백업 TTS 실행 성공');
          return; // 백업이 성공하면 반환
        } catch (backupError) {
          debugPrint('백업 TTS 실행 오류: $backupError');
        }

        // 재시도 전 잠시 대기
        await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
      }
    }

    // 모든 시도가 실패하면 네이티브 코드에 직접 요청
    try {
      await _methodChannel?.invokeMethod('speakTTS',
          {'message': "$busNumber 번 버스가 $stationName 정류장에 곧 도착합니다. 탑승 준비하세요."});
      debugPrint('네이티브 TTS 직접 호출 시도');
    } catch (e) {
      debugPrint('네이티브 TTS 직접 호출 오류: $e');
      throw lastError ?? Exception('모든 TTS 시도 실패');
    }
  }

  Future<bool> setOneTimeAlarm({
    required int id,
    required DateTime alarmTime,
    required Duration preNotificationTime,
    required String busNo,
    required String stationName,
    required int remainingMinutes,
    String routeId = '',
    String? currentStation,
    BusInfo? busInfo,
  }) async {
    try {
      // 디버그 로그 추가
      debugPrint('❗ 알람 설정 시도: busNo=$busNo, stationName=$stationName');
      debugPrint('❗ 알람 시간: $alarmTime, 사전 알림 시간: $preNotificationTime');

      // 트래킹 모드 확인 로직 개선
      bool skipNotification = _isInTrackingMode &&
          _activeAlarms.any((alarm) => alarm.routeId == routeId);

      if (skipNotification) {
        debugPrint('❗ 트래킹 모드에서 알람 예약 (알림 없음): $busNo, $stationName');
        final notificationKey = '${busNo}_${stationName}_$routeId';
        _processedNotifications.add(notificationKey);
      }

      DateTime notificationTime = alarmTime.subtract(preNotificationTime);
      final alarmData = AlarmData(
        busNo: busNo,
        stationName: stationName,
        remainingMinutes: remainingMinutes,
        routeId: routeId,
        scheduledTime: notificationTime,
        targetArrivalTime: alarmTime,
        currentStation: currentStation,
      );

      // 디버그 로그 추가
      debugPrint('❗ 알림 예정 시간: $notificationTime');
      debugPrint('❗ 현재 시간: ${DateTime.now()}');

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('alarm_$id', jsonEncode(alarmData.toJson()));

      // 알람 목록 최신화
      await loadAlarms();
      notifyListeners();

      // 알림 즉시 트리거 조건
      if (notificationTime.isBefore(DateTime.now()) || !skipNotification) {
        debugPrint('❗ 즉시 알림 트리거');
        await NotificationService().showNotification(
          id: id,
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          currentStation: currentStation,
        );
        // 하단 코드 제거 - 알람 데이터를 삭제하지 않음
        // await prefs.remove('alarm_$id');
        notifyListeners();

        // 트래킹 모드 설정 추가
        _isInTrackingMode = true;
        return true;
      }

      // WorkManager 작업 등록
      final uniqueTaskName = 'busAlarm_$id';
      final initialDelay = notificationTime.difference(DateTime.now());
      final inputData = {
        'alarmId': id,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': currentStation,
        'routeId': routeId,
        'skipNotification': skipNotification,
      };

      // 디버그 로그 추가
      debugPrint('❗ WorkManager 작업 등록: 초기 지연 시간 = ${initialDelay.inMinutes}분');

      await Workmanager().registerOneOffTask(
        uniqueTaskName,
        'busAlarmTask',
        initialDelay: initialDelay,
        inputData: inputData,
        constraints: Constraints(
          networkType: NetworkType.not_required,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      // 트래킹 모드가 아닌 경우 백그라운드 서비스 시작
      if (!_isInTrackingMode) {
        await NotificationService().showNotification(
          id: id,
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          currentStation: currentStation,
        );

        await startBusMonitoringService(
          stationId: busNo.contains("_") ? busNo.split("_")[0] : busNo,
          stationName: stationName,
          routeId: routeId,
        );
      }

      debugPrint(
          '❗ 버스 알람 예약 성공: $busNo, $stationName, ${initialDelay.inMinutes}분 후 실행');
      await loadAlarms();
      return true;
    } catch (e) {
      debugPrint('❗ 알람 설정 오류: $e');
      return false;
    }
  }

  Future<bool> cancelAlarm(int id) async {
    try {
      debugPrint('알람 취소 시작: $id');

      AlarmData? alarmToCancel;
      for (var alarm in _activeAlarms) {
        if (alarm.getAlarmId() == id) {
          alarmToCancel = alarm;
          break;
        }
      }
      final String? busNumber = alarmToCancel?.busNo;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove("alarm_$id");
      debugPrint('SharedPreferences에서 알람 제거: alarm_$id');

      final uniqueTaskName = 'busAlarm_$id';
      try {
        debugPrint('WorkManager 작업 취소 시작: $uniqueTaskName');
        await Workmanager().cancelByUniqueName(uniqueTaskName);
        debugPrint('WorkManager 작업 취소 완료: $uniqueTaskName');
      } catch (e) {
        debugPrint('WorkManager 작업 취소 오류 (계속 진행): $e');
      }

      _activeAlarms.removeWhere((alarm) => alarm.getAlarmId() == id);
      debugPrint('알람 목록에서 제거 완료, 남은 알람 수: ${_activeAlarms.length}');

      if (busNumber != null) {
        try {
          await Future.delayed(const Duration(seconds: 2));
          await TTSHelper.initialize();
          await TTSHelper.speakAlarmCancel(busNumber);
        } catch (e) {
          debugPrint('알람 취소 TTS 오류: $e');
        }
      }

      notifyListeners();
      debugPrint('알람 취소 UI 갱신 요청');

      await NotificationService().cancelNotification(id);
      debugPrint('알림 취소 완료: $id');

      debugPrint('알람 취소 성공: $id');
      return true;
    } catch (e) {
      debugPrint('알람 취소 오류: $e');
      return false;
    }
  }

  int getAlarmId(String busNo, String stationName, {String routeId = ''}) {
    return (busNo + stationName + routeId).hashCode;
  }

  Future<bool> cancelAlarmByRoute(
      String busNo, String stationName, String routeId) async {
    try {
      int id = getAlarmId(busNo, stationName, routeId: routeId);
      bool success = await AlarmHelper.cancelAlarm(id);

      final notificationService = NotificationService();
      await notificationService.initialize();
      await notificationService.cancelNotification(id);
      await notificationService.cancelOngoingTracking();

      _alarmCache.removeWhere((alarm) =>
          alarm.busNo == busNo &&
          alarm.stationName == stationName &&
          alarm.routeId == routeId);

      notifyListeners();
      debugPrint('🚫 알람 취소: $busNo, $stationName ($routeId), ID: $id');
      return success;
    } catch (e) {
      debugPrint('🚫 알람 취소 오류: $e');
      return false;
    }
  }

  bool hasAlarm(String busNo, String stationName, String routeId) {
    return _activeAlarms.any((alarm) =>
        alarm.busNo == busNo &&
        alarm.stationName == stationName &&
        alarm.routeId == routeId);
  }

  AlarmData? findAlarm(String busNo, String stationName, String routeId) {
    try {
      return _activeAlarms.firstWhere((alarm) =>
          alarm.busNo == busNo &&
          alarm.stationName == stationName &&
          alarm.routeId == routeId);
    } catch (e) {
      return null;
    }
  }

  Future<void> refreshAlarms() async {
    await loadAlarms();
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void removeFromCacheBeforeCancel(
      String busNo, String stationName, String routeId) {
    _alarmCache.removeWhere((alarm) =>
        alarm.busNo == busNo &&
        alarm.stationName == stationName &&
        alarm.routeId == routeId);

    final key = "${busNo}_$routeId";
    _cachedBusInfo.remove(key);

    notifyListeners();
  }

  Future<List<DateTime>> _fetchHolidays(int year, int month) async {
    final String serviceKey = dotenv.env['SERVICE_KEY'] ?? '';
    final String url =
        'http://apis.data.go.kr/B090041/openapi/service/SpcdeInfoService/getRestDeInfo'
        '?serviceKey=$serviceKey'
        '&solYear=$year'
        '&solMonth=${month.toString().padLeft(2, '0')}'
        '&numOfRows=100';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        // XML 응답 처리
        try {
          final holidays = <DateTime>[];
          final xmlDoc = xml.XmlDocument.parse(response.body);

          // 'item' 요소 찾기
          final items = xmlDoc.findAllElements('item');

          for (var item in items) {
            final isHoliday = item.findElements('isHoliday').first.innerText;
            if (isHoliday == 'Y') {
              final locdate = item.findElements('locdate').first.innerText;
              // YYYYMMDD 형식을 DateTime으로 변환
              final year = int.parse(locdate.substring(0, 4));
              final month = int.parse(locdate.substring(4, 6));
              final day = int.parse(locdate.substring(6, 8));
              holidays.add(DateTime(year, month, day));
            }
          }

          debugPrint('공휴일 목록 ($year-$month): ${holidays.length}개 공휴일 발견');
          return holidays;
        } catch (e) {
          debugPrint('XML 파싱 오류: $e');
          return [];
        }
      } else {
        debugPrint('공휴일 API 응답 오류: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      debugPrint('공휴일 API 호출 오류: $e');
      return [];
    }
  }

  Future<void> updateAutoAlarms(List<AutoAlarm> autoAlarms) async {
    try {
      debugPrint('자동 알람 갱신 시작: ${autoAlarms.length}개');
      final now = DateTime.now();

      // 공휴일 정보 가져오기
      final holidays = await _fetchHolidays(now.year, now.month);

      for (var alarm in autoAlarms) {
        if (!alarm.isActive) continue;

        final alarmId = alarm.id.hashCode;
        final todayWeekday = now.weekday;

        // 반복 요일 체크
        if (!alarm.repeatDays.contains(todayWeekday)) continue;

        // 주말 제외 옵션 체크
        if (alarm.excludeWeekends && (todayWeekday == 6 || todayWeekday == 7)) {
          continue;
        }

        // 공휴일 제외 옵션 체크
        bool isHoliday = holidays.any((holiday) =>
            holiday.year == now.year &&
            holiday.month == now.month &&
            holiday.day == now.day);
        if (alarm.excludeHolidays && isHoliday) continue;

        // 예약 시간 설정
        DateTime scheduledTime = DateTime(
          now.year,
          now.month,
          now.day,
          alarm.hour,
          alarm.minute,
        );

        // 이미 지난 시간이면 다음 날로 설정
        if (scheduledTime.isBefore(now)) {
          scheduledTime = scheduledTime.add(const Duration(days: 1));
        }

        // 자동 알람 ID에 특별한 접두사 사용
        final autoAlarmId = "auto_$alarmId";

        // 알림 시간 계산 (지정된 시간 - 미리 알림 시간)
        final notificationTime =
            scheduledTime.subtract(Duration(minutes: alarm.beforeMinutes));
        final initialDelay = notificationTime.difference(now);

        // 자동 알람용 WorkManager 태스크 등록
        final inputData = {
          'alarmId': alarmId,
          'busNo': alarm.routeNo,
          'stationName': alarm.stationName,
          'remainingMinutes': alarm.beforeMinutes,
          'routeId': alarm.routeId,
          'isAutoAlarm': true,
          'showNotification': true, // 명시적으로 알림 표시 활성화
          'startTracking': true, // 실시간 추적 시작 플래그 추가
          'stationId': alarm.stationId, // 정류장 ID 추가
          'shouldFetchRealtime': true, // 실시간 데이터 가져오기 플래그
          'useTTS': true, // TTS 사용 플래그
          'notificationTime':
              notificationTime.millisecondsSinceEpoch, // 알림 시간 저장
        };

        // 실시간 버스 도착 모니터링을 위한 사전 등록
        try {
          await _methodChannel?.invokeMethod('registerBusArrivalReceiver', {
            'stationId': alarm.stationId,
            'stationName': alarm.stationName,
            'routeId': alarm.routeId,
          });
        } catch (e) {
          debugPrint('버스 도착 이벤트 리시버 등록 오류: $e');
        }

        await Workmanager().registerOneOffTask(
          'autoAlarm_$alarmId',
          'autoAlarmTask',
          initialDelay: initialDelay,
          inputData: inputData,
          constraints: Constraints(
            networkType: NetworkType.connected, // 네트워크 연결 필요
            requiresBatteryNotLow: false,
            requiresCharging: false,
            requiresDeviceIdle: false,
            requiresStorageNotLow: false,
          ),
          existingWorkPolicy: ExistingWorkPolicy.replace,
        );

        // 알람 정보 저장
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(autoAlarmId, jsonEncode(alarm.toJson()));

        debugPrint(
            '자동 알람 예약: ${alarm.routeNo}, ${alarm.stationName}, ${alarm.hour}:${alarm.minute}, ${initialDelay.inMinutes}분 후 알림');
      }

      notifyListeners();
    } catch (e) {
      debugPrint('자동 알람 갱신 오류: $e');
    }
  }
}
