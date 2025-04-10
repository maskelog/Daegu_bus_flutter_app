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
import '../services/settings_service.dart';
import '../utils/tts_switcher.dart';
import '../utils/simple_tts_helper.dart';

class AlarmData {
  final String busNo;
  final String stationName;
  final int remainingMinutes;
  final String routeId;
  final DateTime scheduledTime;
  DateTime targetArrivalTime;
  final String? currentStation;
  int _currentRemainingMinutes;
  final bool useTTS;

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
    this.useTTS = true,
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
        'useTTS': useTTS,
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
      useTTS: json['useTTS'] ?? true,
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
    return ("${busNo}_${stationName}_$routeId").hashCode;
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
    // 마지막 업데이트로부터 경과 시간 계산 (분 단위)
    final elapsedMinutes = DateTime.now().difference(lastUpdated).inMinutes;

    // 분 단위로 경과 시간이 30초보다 클 경우에만 시간 차감
    if (elapsedMinutes > 0) {
      // 경과 시간이 지난 경우 차감 로직 적용
      final currentEstimate = remainingMinutes - elapsedMinutes;
      return currentEstimate > 0 ? currentEstimate : 0;
    } else {
      // 경과 시간이 1분 미만인 경우 원래 값 그대로 사용
      return remainingMinutes;
    }
  }
}

class AlarmService extends ChangeNotifier {
  List<AlarmData> _activeAlarms = [];
  final List<AlarmData> _autoAlarms = []; // 자동 알람을 위한 별도 리스트 추가
  Timer? _refreshTimer;
  final List<AlarmData> _alarmCache = [];
  bool _initialized = false;
  final Map<String, CachedBusInfo> _cachedBusInfo = {};
  MethodChannel? _methodChannel;

  static final AlarmService _instance = AlarmService._internal();
  bool _isInTrackingMode = false;
  bool get isInTrackingMode => _isInTrackingMode;
  final Set<String> _processedNotifications = {};

  // 자동 알람과 일반 알람을 구분하여 가져오는 getter 추가
  List<AlarmData> get activeAlarms => _activeAlarms;
  List<AlarmData> get autoAlarms => _autoAlarms;

  factory AlarmService() {
    return _instance;
  }

  AlarmService._internal() {
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initialized) return;

    debugPrint('🔔 AlarmService 초기화 시작: ${DateTime.now()}');

    // 초기화 작업을 백그라운드에서 동시에 시작
    final List<Future> initTasks = [
      // 알람 로드
      loadAlarms().catchError((e) {
        debugPrint('⚠️ 일반 알람 로드 실패: $e');
        return null; // 실패해도 계속 진행
      }),

      // 자동 알람 로드
      loadAutoAlarms().catchError((e) {
        debugPrint('⚠️ 자동 알람 로드 실패: $e');
        return null; // 실패해도 계속 진행
      }),
    ];

    try {
      // 모든 초기화 작업을 동시에 실행
      await Future.wait(initTasks);

      // 주기적 리프레시 타이머 설정 (더 긴 간격으로 변경)
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        loadAlarms();
        loadAutoAlarms();
      });

      // 메서드 채널 설정
      try {
        _setupMethodChannel();
        debugPrint('✅ 메서드 채널 설정 성공');
      } catch (e) {
        debugPrint('⚠️ 메서드 채널 설정 실패: $e');
      }

      // 버스 도착 수신기 등록
      try {
        await _registerBusArrivalReceiver();
        debugPrint('✅ 버스 도착 수신기 등록 성공');
      } catch (e) {
        debugPrint('⚠️ 버스 도착 수신기 등록 실패: $e');
      }

      // 초기화 성공 표시
      _initialized = true;
      debugPrint('✅ AlarmService 초기화 완료: ${DateTime.now()}');
    } catch (e) {
      debugPrint('❌ AlarmService 초기화 실패: $e');

      // 초기화가 실패해도 앱이 동작할 수 있도록 기본 상태 설정
      _initialized = true;
      _activeAlarms = [];
      _autoAlarms.clear();
      _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        try {
          loadAlarms();
          loadAutoAlarms();
        } catch (e) {
          debugPrint('⚠️ 알람 주기적 로드 실패: $e');
        }
      });
    }
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

            await _handleBusArrival(
                busNumber, stationName, currentStation, routeId);

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
              SimpleTTSHelper.speak(
                  "$busNumber 번 버스가 $stationName 정류장에 곧 도착합니다. 탑승 준비하세요.");
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
            final String stationName = data['stationName'] ?? '';

            debugPrint(
                '버스 위치 업데이트: $busNumber, 남은 시간: $remainingMinutes분, 현재 위치: $currentStation');

            await _handleBusLocationUpdate(busNumber, routeId, remainingMinutes,
                currentStation, stationName);

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
    String busNo = '',
  }) async {
    try {
      // 현재 트래킹 중이면 먼저 중지
      if (_isInTrackingMode) {
        await stopBusMonitoringService();
      }

      // routeId가 빈 문자열이면 stationId를 사용
      String effectiveRouteId = routeId.isEmpty ? stationId : routeId;
      // busNo가 빈 문자열이면 정류장ID를 사용 (나중에 버스 번호로 교체 가능)
      String effectiveBusNo = busNo.isEmpty
          ? (stationId.contains('_') ? stationId.split('_')[0] : stationId)
          : busNo;

      debugPrint(
          '🚌 버스 모니터링 시작 - 버스: $effectiveBusNo, 정류장: $stationName, 노선: $effectiveRouteId');

      // 추적 정보 초기화
      final cacheKey = "${effectiveBusNo}_$effectiveRouteId";
      if (!_cachedBusInfo.containsKey(cacheKey)) {
        // 캐시에 초기 정보 생성
        _cachedBusInfo[cacheKey] = CachedBusInfo(
          busNo: effectiveBusNo,
          routeId: effectiveRouteId,
          remainingMinutes: 0, // 초기값은 0으로 설정
          currentStation: '정보 가져오는 중...',
          lastUpdated: DateTime.now(),
        );
        debugPrint('추적 캐시 생성: $cacheKey');
      }

      // 현재 추적 중인 알람이 있는지 확인
      AlarmData? trackingAlarm;
      for (var alarm in _activeAlarms) {
        if (alarm.busNo == effectiveBusNo ||
            alarm.routeId == effectiveRouteId) {
          trackingAlarm = alarm;
          debugPrint(
              '관련 알람 발견: ${alarm.busNo}, ${alarm.stationName}, 남은 시간: ${alarm.getCurrentArrivalMinutes()}분');
          break;
        }
      }

      // TTS 추적을 먼저 시작
      try {
        // 이미 알람 설정 발화가 있으므로, 여기서는 TTS 발화를 생략
        await _methodChannel?.invokeMethod('startTtsTracking', {
          'routeId': effectiveRouteId,
          'stationId': stationId,
          'busNo': effectiveBusNo,
          'stationName': stationName
        });
        debugPrint('🔊 TTS 추적 시작 성공');
      } catch (e) {
        debugPrint('🔊 TTS 추적 시작 오류 (계속 진행): $e');
      }

      // 버스 모니터링 서비스 시작
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

        // 현재 알림 표시 모드 확인
        final settingsService = SettingsService();
        final isAllBusesMode = settingsService.notificationDisplayMode ==
            NotificationDisplayMode.allBuses;
        String? allBusesSummary;

        // allBuses 모드일 때 모든 버스 정보 요약 생성
        if (isAllBusesMode) {
          try {
            // 정류장의 모든 버스 정보 가져오기 (필요시 구현)
            // allBusesSummary = await _getAllBusesInfoSummary(stationId);
          } catch (e) {
            debugPrint('모든 버스 정보 요약 생성 오류: $e');
          }
        }

        // 알림 표시
        if (trackingAlarm != null) {
          await NotificationService().showNotification(
            id: trackingAlarm.getAlarmId(),
            busNo: trackingAlarm.busNo,
            stationName: trackingAlarm.stationName,
            remainingMinutes: trackingAlarm.getCurrentArrivalMinutes(),
            currentStation: trackingAlarm.currentStation ?? '정보 가져오는 중...',
            isOngoing: true, // 지속적인 알림으로 설정
            routeId: trackingAlarm.routeId,
            allBusesSummary: allBusesSummary, // allBuses 모드일 때만 값이 있음
          );
        } else {
          await NotificationService().showNotification(
            id: ("${effectiveBusNo}_$stationName").hashCode,
            busNo: effectiveBusNo,
            stationName: stationName,
            remainingMinutes: 0,
            currentStation: '정보 가져오는 중...',
            isOngoing: true, // 지속적인 알림으로 설정
            routeId: effectiveRouteId,
            allBusesSummary: allBusesSummary, // allBuses 모드일 때만 값이 있음
          );
        }

        notifyListeners();
      }

      debugPrint('🚌 버스 모니터링 서비스 시작: $result, 트래킹 모드: $_isInTrackingMode');
      return result == true;
    } catch (e) {
      debugPrint('🚌 버스 모니터링 서비스 시작 오류: $e');
      // 오류가 발생해도 기본적인 추적 상태로 설정
      _isInTrackingMode = true;
      notifyListeners();
      return true; // 실패해도 true를 반환하여 진행
    }
  }

  Future<bool> stopBusMonitoringService() async {
    try {
      debugPrint('🚌 버스 모니터링 서비스 중지 시작');

      bool stopSuccess = false;

      // 1. 메서드 채널을 통한 중지 시도
      try {
        final result =
            await _methodChannel?.invokeMethod('stopBusMonitoringService');
        if (result == true) {
          stopSuccess = true;
          debugPrint('🚌 버스 모니터링 서비스 중지 성공 (result: $result)');
        } else {
          debugPrint('🚌 버스 모니터링 서비스 중지 실패 (result: $result)');
        }
      } catch (e) {
        debugPrint('🚌 버스 모니터링 서비스 중지 메서드 호출 오류: $e');
      }

      // 2. TTS 추적 중지 시도
      try {
        await _methodChannel?.invokeMethod('stopTtsTracking');
        debugPrint('🚌 TTS 추적 중지 성공');
      } catch (e) {
        debugPrint('🚌 TTS 추적 중지 오류: $e');
      }

      // 3. 알림 취소 시도
      try {
        await NotificationService().cancelOngoingTracking();
        debugPrint('🚌 진행 중인 추적 알림 취소 성공');

        // 모든 알림도 추가로 취소 시도
        await NotificationService().cancelAllNotifications();
        debugPrint('🚌 모든 알림 취소 성공');
      } catch (e) {
        debugPrint('🚌 알림 취소 시도 오류: $e');
      }

      // 4. 캐시 데이터 정리
      try {
        _processedNotifications.clear();
        debugPrint('🚌 처리된 알림 캐시 정리 완료');
      } catch (e) {
        debugPrint('🚌 캐시 정리 오류: $e');
      }

      // 5. 마지막으로 상태 변경
      _isInTrackingMode = false;
      notifyListeners();

      // 6. TTS로 알림 중지 알림
      try {
        await SimpleTTSHelper.speak("버스 추적이 중지되었습니다.");
      } catch (e) {
        debugPrint('🚌 TTS 알림 오류: $e');
      }

      debugPrint('🚌 모니터링 서비스 중지 완료, 추적 모드: $_isInTrackingMode');
      return stopSuccess || !_isInTrackingMode; // 둘 중 하나라도 성공하면 true 반환
    } catch (e) {
      debugPrint('🚌 버스 모니터링 서비스 중지 오류: $e');

      // 오류 발생해도 강제로 상태 변경
      _isInTrackingMode = false;
      _processedNotifications.clear();
      notifyListeners();

      return false;
    }
  }

  bool _isNotificationProcessed(String busNo, String stationName,
      [String? routeId]) {
    final key = "${busNo}_${stationName}_${routeId ?? ""}";
    return _processedNotifications.contains(key);
  }

  void _markNotificationAsProcessed(String busNo, String stationName,
      [String? routeId]) {
    final key = "${busNo}_${stationName}_${routeId ?? ""}";
    _processedNotifications.add(key);
    if (_processedNotifications.length > 100) {
      _processedNotifications.remove(_processedNotifications.first);
    }
  }

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
        final isRecent =
            DateTime.now().difference(cachedInfo.lastUpdated).inMinutes < 10;

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
      final isRecent =
          DateTime.now().difference(cachedInfo.lastUpdated).inMinutes < 10;

      if (isRecent) {
        final parts = key.split('_');
        if (parts.isNotEmpty) {
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

      // 모든 관련 알람에 대해 업데이트 적용
      for (var alarm in _activeAlarms) {
        // 버스 번호 또는 노선ID가 일치하는 모든 알람에 적용
        if (alarm.busNo == busNo || alarm.routeId == routeId) {
          // 기존 남은 시간 기록
          final oldRemainingTime = alarm.getCurrentArrivalMinutes();

          // 새로운 시간으로 업데이트
          alarm.updateRemainingMinutes(remainingTime);
          alarm.updateTargetArrivalTime(
              DateTime.now().add(Duration(minutes: remainingTime)));

          // SharedPreferences에도 업데이트
          _updateAlarmInStorage(alarm);

          debugPrint(
              '🔔 승차 알람 정보 업데이트: $alarm.busNo, 남은 시간: $oldRemainingTime분 -> $remainingTime분, 위치: $busInfo.currentStation');
          alarmUpdated = true;
        }
      }

      debugPrint(
          '🚌 BusInfo Cache 업데이트: $busNo, 남은 시간: $remainingTime분, 위치: $busInfo.currentStation');

      // 알림 업데이트
      _updateTrackingNotification(busNo, routeId);

      // UI 갱신
      if (alarmUpdated) {
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

    // 업데이트가 필요한지 판단
    bool needsUpdate = false;
    if (existingBusInfo != null) {
      // 시간이 변경되었거나 현재 정류장이 변경된 경우에만 업데이트
      if (existingBusInfo.remainingMinutes != remainingMinutes ||
          existingBusInfo.currentStation != currentStation) {
        needsUpdate = true;
      }
    } else {
      // 기존 정보가 없는 경우 무조건 업데이트
      needsUpdate = true;
    }

    // 업데이트가 필요한 경우에만 처리
    if (needsUpdate) {
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

      // TTSSwitcher에 강제 시간 업데이트 전달
      TTSSwitcher.updateTrackedBusTime(remainingMinutes);

      // 승차 알람에도 정보 업데이트 - 모든 관련 알람 찾기 및 업데이트
      bool alarmUpdated = false;
      for (var alarm in _activeAlarms) {
        // 버스 번호나 노선ID가 일치하는 모든 알람 업데이트
        if (alarm.busNo == busNo || alarm.routeId == routeId) {
          alarm.updateRemainingMinutes(remainingMinutes);
          alarm.updateTargetArrivalTime(
              DateTime.now().add(Duration(minutes: remainingMinutes)));
          debugPrint(
              '🔔 알람 정보 업데이트: $alarm.busNo, 남은 시간: $remainingMinutes분, 위치: $currentStation');
          alarmUpdated = true;

          // SharedPreferences에도 업데이트
          _updateAlarmInStorage(alarm);
        }
      }

      // 알림도 업데이트
      _updateTrackingNotification(busNo, routeId);

      // 알람이 업데이트되었다면 UI 갱신
      if (alarmUpdated) {
        notifyListeners();
      }
    }
  }

  // SharedPreferences에 알람 정보를 저장하는 헬퍼 메서드
  Future<void> _updateAlarmInStorage(AlarmData alarm) async {
    try {
      final id = alarm.getAlarmId();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('alarm_$id', jsonEncode(alarm.toJson()));
      debugPrint(
          '알람 저장소 업데이트 완료: $alarm.busNo, 남은 시간: ${alarm.getCurrentArrivalMinutes()}분');
    } catch (e) {
      debugPrint('알람 저장소 업데이트 오류: $e');
    }
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
            '🚌 버스 추적 알림 업데이트: $busNo, 남은 시간: $cachedInfo.remainingMinutes분, 위치: $cachedInfo.currentStation');

        try {
          // NotificationService를 사용하여 알림 업데이트
          await NotificationService().showNotification(
            id: relatedAlarm.getAlarmId(),
            busNo: busNo,
            stationName: relatedAlarm.stationName,
            remainingMinutes: cachedInfo.remainingMinutes,
            currentStation: cachedInfo.currentStation,
            isOngoing: true, // 지속적인 알림으로 설정
            routeId: routeId,
          );
          debugPrint('🚌 버스 추적 알림 업데이트 성공: $busNo');
        } catch (e) {
          debugPrint('🚌 버스 추적 알림 업데이트 오류: $e');

          // 재시도: 플랫폼 오류가 발생하면 메서드 채널 사용
          try {
            await _methodChannel
                ?.invokeMethod('updateBusTrackingNotification', {
              'busNo': busNo,
              'stationName': relatedAlarm.stationName,
              'remainingMinutes': cachedInfo.remainingMinutes,
              'currentStation': cachedInfo.currentStation,
            });
            debugPrint('🚌 메서드 채널을 통한 알림 업데이트 성공: $busNo');
          } catch (channelError) {
            debugPrint('🚌 메서드 채널을 통한 알림 업데이트 오류: $channelError');
          }
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
        final notificationKey = "${alarm.busNo}_${alarm.stationName}_$routeId";
        _processedNotifications.add(notificationKey);
      }
    }
  }

  // loadAlarms 메소드에서 자동 알람은 로드하지 않도록 수정
  Future<void> loadAlarms() async {
    // 백그라운드에서 알람 로드 실행
    return compute(_loadAlarmsInBackground, null).then((result) {
      _activeAlarms = result;
      notifyListeners();
      debugPrint('✅ 알람 로드 완료: ${_activeAlarms.length}개');
    }).catchError((e) {
      debugPrint('❌ 알람 로드 오류: $e');
      // 오류 발생 시 기존 알람 유지
    });
  }

  // 백그라운드에서 실행될 알람 로드 함수
  static Future<List<AlarmData>> _loadAlarmsInBackground(void _) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final List<AlarmData> loadedAlarms = [];

      // 일반 알람 로드
      final alarmKeys = keys
          .where((key) =>
              key.startsWith('alarm_') && !key.startsWith('auto_alarm_'))
          .toList();
      debugPrint('알람 로드 시작: ${alarmKeys.length}개');

      final keysToRemove = <String>[];

      for (var key in alarmKeys) {
        try {
          final String? jsonString = prefs.getString(key);
          if (jsonString == null || jsonString.isEmpty) {
            keysToRemove.add(key);
            continue;
          }

          final Map<String, dynamic> jsonData = jsonDecode(jsonString);

          // 필수 필드 유효성 검사
          if (!_validateRequiredFields(jsonData)) {
            debugPrint('알람 데이터 필수 필드 누락: $key');
            keysToRemove.add(key);
            continue;
          }

          final AlarmData alarm = AlarmData.fromJson(jsonData);

          final now = DateTime.now();
          if (alarm.targetArrivalTime
              .isBefore(now.subtract(const Duration(minutes: 5)))) {
            debugPrint('만료된 알람 발견: ${alarm.busNo}, ${alarm.stationName}');
            keysToRemove.add(key);
            continue;
          }

          loadedAlarms.add(alarm);
        } catch (e) {
          debugPrint('알람 데이터 손상 ($key): $e');
          keysToRemove.add(key);
        }
      }

      // 자동 알람 로드
      final autoAlarmKeys =
          keys.where((key) => key.startsWith('auto_alarm_')).toList();
      debugPrint('자동 알람 로드 시작: ${autoAlarmKeys.length}개');

      for (var key in autoAlarmKeys) {
        try {
          final String? jsonString = prefs.getString(key);
          if (jsonString == null || jsonString.isEmpty) {
            keysToRemove.add(key);
            continue;
          }

          final Map<String, dynamic> jsonData = jsonDecode(jsonString);

          // 필수 필드 유효성 검사
          if (!_validateRequiredFields(jsonData)) {
            debugPrint('자동 알람 데이터 필수 필드 누락: $key');
            keysToRemove.add(key);
            continue;
          }

          final AlarmData alarm = AlarmData.fromJson(jsonData);

          // 자동 알람은 만료되지 않음
          loadedAlarms.add(alarm);
        } catch (e) {
          debugPrint('자동 알람 데이터 손상 ($key): $e');
          keysToRemove.add(key);
        }
      }

      // 만료되거나 손상된 알람 제거
      for (var key in keysToRemove) {
        await prefs.remove(key);
        debugPrint('불필요한 알람 키 정리: $key');
      }

      // 변경사항이 있으면 저장
      if (keysToRemove.isNotEmpty) {
        // 저장할 알람만 저장
        final alarmsJson = loadedAlarms
            .where((alarm) => !alarm.busNo.startsWith('auto_'))
            .map((alarm) => jsonEncode(alarm.toJson()))
            .toList();
        await prefs.setStringList('active_alarms', alarmsJson);
      }

      debugPrint(
          '알람 로드 완료: ${loadedAlarms.length}개 (일반: ${alarmKeys.length - keysToRemove.length}개, 자동: ${autoAlarmKeys.length}개)');
      return loadedAlarms;
    } catch (e) {
      debugPrint('알람 로드 중 오류 발생: $e');
      return []; // 오류 발생 시 빈 리스트 반환
    }
  }

  // 필수 필드 유효성 검사 함수
  static bool _validateRequiredFields(Map<String, dynamic> data) {
    final requiredFields = [
      'busNo',
      'stationName',
      'remainingMinutes',
      'routeId',
      'scheduledTime',
    ];

    for (var field in requiredFields) {
      if (!data.containsKey(field) || data[field] == null) {
        return false;
      }

      // String 필드의 경우 빈 문자열 검사
      if ((field == 'busNo' || field == 'stationName' || field == 'routeId') &&
          (data[field] as String).isEmpty) {
        return false;
      }
    }

    return true;
  }

  // TTS 재시도 함수 추가
  Future<bool> _retryTTS(
      String busNo, String stationName, String currentStation) async {
    int retryCount = 0;
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 1);

    while (retryCount < maxRetries) {
      try {
        // 현재 시간에 맞는 인사말 추가
        final now = DateTime.now();
        String greeting = '';
        if (now.hour < 12) {
          greeting = '안녕하세요. ';
        } else if (now.hour < 18) {
          greeting = '안녕하세요. ';
        } else {
          greeting = '안녕하세요. ';
        }

        // 현재 정류장이 있는 경우와 없는 경우를 구분하여 메시지 생성
        String message;
        if (currentStation.isNotEmpty) {
          message =
              '$greeting$busNo번 버스가 $currentStation 정류장을 지나 $stationName 정류장으로 향하고 있습니다.';
        } else {
          message = '$greeting$busNo번 버스가 $stationName 정류장으로 향하고 있습니다.';
        }

        await SimpleTTSHelper.speak(message);
        debugPrint('TTS 알림 성공: $message');
        return true;
      } catch (e) {
        retryCount++;
        debugPrint('TTS 시도 $retryCount 실패: $e');
        if (retryCount < maxRetries) {
          await Future.delayed(retryDelay);
        }
      }
    }
    return false;
  }

  Future<void> _handleBusArrival(String busNo, String stationName,
      String currentStation, String routeId) async {
    final notificationKey = "${busNo}_${stationName}_$routeId";
    if (_isNotificationProcessed(busNo, stationName, routeId)) {
      debugPrint('이미 처리된 알림입니다: $notificationKey');
      return;
    }

    // 해당 알람의 TTS 설정 확인
    final autoAlarm = _activeAlarms.firstWhere(
      (alarm) => alarm.busNo == busNo && alarm.stationName == stationName,
      orElse: () => AlarmData(
        busNo: busNo,
        stationName: stationName,
        remainingMinutes: 3,
        routeId: routeId,
        scheduledTime: DateTime.now(),
        useTTS: true,
      ),
    );

    // 알림과 TTS를 동시에 실행
    await Future.wait([
      // 알림 표시 (지속적인 알림으로 설정)
      NotificationService()
          .showNotification(
        id: autoAlarm.getAlarmId(),
        busNo: busNo,
        stationName: stationName,
        remainingMinutes: autoAlarm.getCurrentArrivalMinutes(),
        currentStation: currentStation,
        isOngoing: true, // 지속적인 알림으로 설정
        routeId: routeId,
      )
          .catchError((error) {
        debugPrint('알림 표시 오류: $error');
        return false;
      }),

      // TTS 알림 (설정된 경우에만)
      if (autoAlarm.useTTS) _retryTTS(busNo, stationName, currentStation),
    ]);

    // 알림을 처리된 목록에 추가하지 않음 (지속적인 알림을 위해)
    _markNotificationAsProcessed(busNo, stationName, routeId);
  }

  // 버스 위치 업데이트 처리 메서드 수정
  Future<void> _handleBusLocationUpdate(String busNo, String routeId,
      int remainingMinutes, String currentStation, String stationName) async {
    final cacheKey = "${busNo}_$routeId";
    final previousInfo = _cachedBusInfo[cacheKey];
    final int previousMinutes = previousInfo?.remainingMinutes ?? -1;

    // 캐시 업데이트
    _updateBusLocationCache(busNo, routeId, remainingMinutes, currentStation);

    // 주요 시간대 정의 (TTS를 발화할 중요 시점)
    final List<int> importantTimes = [10, 8, 5, 3, 2, 1, 0];

    // 시간이 변경되었을 때만 처리
    if (previousMinutes != remainingMinutes) {
      debugPrint('시간 변경 감지: $previousMinutes분 -> $remainingMinutes분');

      // 1. 주요 시간대에 도달했을 때 TTS 발화
      if (importantTimes.contains(remainingMinutes)) {
        final ttsKey = "${busNo}_${routeId}_$remainingMinutes";

        if (!_processedNotifications.contains(ttsKey)) {
          debugPrint('주요 시간대 TTS 발화 트리거: $remainingMinutes분');

          // 메시지 생성
          String message;
          if (remainingMinutes <= 0) {
            message = "$busNo 번 버스가 곧 도착합니다. 탑승 준비하세요.";
          } else {
            message = "$busNo 번 버스가 약 $remainingMinutes 분 후 도착 예정입니다.";
            if (currentStation.isNotEmpty) {
              message += " 현재 $currentStation 위치입니다.";
            }
          }

          // TTS 발화 시도
          try {
            await SimpleTTSHelper.speak(message);
            debugPrint('TTS 발화 성공: $message');
          } catch (ttsError) {
            debugPrint('TTS 발화 오류, 네이티브 채널 직접 시도: $ttsError');
            try {
              await _methodChannel
                  ?.invokeMethod('speakTTS', {'message': message});
            } catch (e) {
              debugPrint('네이티브 TTS 발화 오류: $e');
            }
          }

          // 처리된 알림으로 표시 (TTS 발화 제한을 위해)
          _processedNotifications.add(ttsKey);

          // 30초 후 키 제거 (짧은 시간으로 설정하여 중요 시점마다 발화 보장)
          Future.delayed(const Duration(seconds: 30), () {
            _processedNotifications.remove(ttsKey);
          });
        }
      }
      // 2. 주요 시간대가 아니더라도 큰 폭으로 시간이 변경되었을 때 TTS 발화
      else if (previousMinutes - remainingMinutes >= 3) {
        final ttsKey = "${busNo}_${routeId}_jump_$remainingMinutes";

        if (!_processedNotifications.contains(ttsKey)) {
          debugPrint(
              '시간 점프 TTS 발화 트리거: $previousMinutes분 -> $remainingMinutes분');

          try {
            await SimpleTTSHelper.speak(
                "$busNo 번 버스 도착 시간이 업데이트 되었습니다. 약 $remainingMinutes 분 후 도착 예정입니다.");
          } catch (e) {
            debugPrint('시간 점프 TTS 발화 오류: $e');
          }

          _processedNotifications.add(ttsKey);

          // 1분 후 키 제거
          Future.delayed(const Duration(minutes: 1), () {
            _processedNotifications.remove(ttsKey);
          });
        }
      }

      // 현재 알림 표시 모드 확인
      final settingsService = SettingsService();
      final isAllBusesMode = settingsService.notificationDisplayMode ==
          NotificationDisplayMode.allBuses;
      String? allBusesSummary;

      // allBuses 모드일 때 모든 버스 정보 요약 생성
      if (isAllBusesMode) {
        try {
          // 정류장의 모든 버스 정보 가져오기 (필요시 구현)
          // allBusesSummary = await _getAllBusesInfoSummary(stationId);
        } catch (e) {
          debugPrint('모든 버스 정보 요약 생성 오류: $e');
        }
      }

      // 알림 업데이트
      await NotificationService().showNotification(
        id: ("${busNo}_${stationName}_$routeId").hashCode,
        busNo: busNo,
        stationName: stationName,
        remainingMinutes: remainingMinutes,
        currentStation: currentStation,
        isOngoing: true, // 지속적인 알림으로 설정
        routeId: routeId,
        allBusesSummary: allBusesSummary, // allBuses 모드일 때만 값이 있음
      );
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
        final notificationKey = "${busNo}_${stationName}_$routeId";
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
        useTTS: true,
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

      // 알람이 설정되었음을 알리는 TTS 발화
      try {
        await SimpleTTSHelper.speakBusAlarmStart(busNo, stationName);
        debugPrint('🔔 알람 설정 TTS 발화 성공');
      } catch (e) {
        debugPrint('🔔 알람 설정 TTS 발화 오류: $e');
      }

      // 트래킹 모드가 아닌 경우 백그라운드 서비스 시작
      // 중요: 이미 TTS를 발화했으므로 추가 음성 알림은 하지 않도록 busNo를 전달하지 않음
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
          // 드라이버 전송 방지, 이미 알람 설정 TTS가 발화됨
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
      debugPrint('🔔 알람 취소 시작: $id');

      // 취소할 알람 찾기
      AlarmData? alarmToCancel;
      for (var alarm in _activeAlarms) {
        if (alarm.getAlarmId() == id) {
          alarmToCancel = alarm;
          break;
        }
      }

      if (alarmToCancel == null) {
        debugPrint('🔔 취소할 알람을 찾을 수 없음: $id');
        return false;
      }

      final String busNumber = alarmToCancel.busNo;
      final String stationName = alarmToCancel.stationName;
      final String routeId = alarmToCancel.routeId;

      debugPrint('🔔 취소할 알람 찾음: $busNumber, $stationName, $routeId');

      // SharedPreferences에서 알람 제거
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove("alarm_$id");
      debugPrint('🔔 SharedPreferences에서 알람 제거: alarm_$id');

      // 캠시에서 알람 제거
      final cacheKey = "${busNumber}_$routeId";
      _cachedBusInfo.remove(cacheKey);
      debugPrint('🔔 캠시에서 알람 제거: $cacheKey');

      // WorkManager 작업 취소
      final uniqueTaskName = 'busAlarm_$id';
      try {
        debugPrint('🔔 WorkManager 작업 취소 시작: $uniqueTaskName');
        await Workmanager().cancelByUniqueName(uniqueTaskName);
        debugPrint('🔔 WorkManager 작업 취소 완료: $uniqueTaskName');
      } catch (e) {
        debugPrint('🔔 WorkManager 작업 취소 오류 (계속 진행): $e');
      }

      // 알람 목록에서 제거
      _activeAlarms.removeWhere((alarm) => alarm.getAlarmId() == id);
      debugPrint('🔔 알람 목록에서 제거 완료, 남은 알람 수: ${_activeAlarms.length}개');

      // 알림 음성 시도
      try {
        await SimpleTTSHelper.initialize();
        await SimpleTTSHelper.speak("$busNumber 번 버스 알림이 취소되었습니다.");
        debugPrint('🔔 알람 취소 TTS 성공');
      } catch (e) {
        debugPrint('🔔 알람 취소 TTS 오류: $e');
      }

      // 로컬 알림 취소
      await NotificationService().cancelNotification(id);
      debugPrint('🔔 로컬 알림 취소 완료: $id');

      // 시스템 알림 취소
      await NotificationService().cancelOngoingTracking();
      debugPrint('🔔 시스템 알림 취소 완료');

      // 모니터링 서비스 중지 (가장 중요한 부분)
      if (_isInTrackingMode) {
        try {
          await stopBusMonitoringService();
          debugPrint('🔔 버스 모니터링 서비스 중지 성공');
        } catch (e) {
          debugPrint('🔔 버스 모니터링 서비스 중지 오류: $e');

          // 여러 방법을 사용해 중지 시도
          try {
            // 메서드 채널을 통한 방법 시도
            await _methodChannel?.invokeMethod('stopBusMonitoringService');
            await _methodChannel?.invokeMethod('stopTtsTracking');
            _isInTrackingMode = false; // 강제로 상태 변경
            debugPrint('🔔 메서드 채널을 통한 버스 모니터링 서비스 중지 시도');
          } catch (e2) {
            debugPrint('🔔 메서드 채널을 통한 중지 시도 오류: $e2');
            // 여기서도 오류가 발생하면 강제로 상태를 변경시켜야 함
            _isInTrackingMode = false;
            notifyListeners();
          }
        }
      }

      // UI 갱신
      notifyListeners();
      debugPrint('🔔 알람 취소 성공: $id');

      return true;
    } catch (e) {
      debugPrint('🔔 알람 취소 오류: $e');
      // 오류가 발생해도 알람 상태를 초기화해야 함
      try {
        _isInTrackingMode = false;
        await NotificationService().cancelAllNotifications();
        await _methodChannel?.invokeMethod('stopBusMonitoringService');
        notifyListeners();
      } catch (resetError) {
        debugPrint('�� 오류 발생 후 알람 초기화 시도 중 추가 오류: $resetError');
      }
      return false;
    }
  }

  int getAlarmId(String busNo, String stationName, {String routeId = ''}) {
    return ("${busNo}_${stationName}_$routeId").hashCode;
  }

  Future<bool> cancelAlarmByRoute(
      String busNo, String stationName, String routeId) async {
    try {
      int id = getAlarmId(busNo, stationName, routeId: routeId);
      debugPrint('🚫 경로별 알람 취소 시작: $busNo, $stationName, $routeId, ID: $id');

      // 1. 저장된 알람 제거
      try {
        final prefs = await SharedPreferences.getInstance();
        // 일반 알람 제거
        await prefs.remove("alarm_$id");
        // 자동 알람 제거
        final autoAlarms = prefs.getStringList('auto_alarms') ?? [];
        final updatedAlarms = autoAlarms.where((json) {
          final data = jsonDecode(json);
          final autoAlarm = AutoAlarm.fromJson(data);
          return !(autoAlarm.routeNo == busNo &&
              autoAlarm.stationName == stationName &&
              autoAlarm.routeId == routeId);
        }).toList();
        await prefs.setStringList('auto_alarms', updatedAlarms);
        debugPrint('🚫 SharedPreferences에서 알람 제거 완료');
      } catch (e) {
        debugPrint('🚫 SharedPreferences 알람 제거 오류: $e');
      }

      // 2. WorkManager 작업 취소
      try {
        await Workmanager().cancelByUniqueName('busAlarm_$id');
        await Workmanager().cancelByUniqueName('autoAlarm_$id');
        debugPrint('🚫 WorkManager 작업 취소 완료');
      } catch (e) {
        debugPrint('🚫 WorkManager 작업 취소 오류: $e');
      }

      // 3. AlarmHelper를 통한 취소 시도
      try {
        await AlarmHelper.cancelAlarm(id);
        debugPrint('🚫 AlarmHelper를 통한 알람 취소 완료');
      } catch (e) {
        debugPrint('🚫 AlarmHelper 취소 오류: $e');
      }

      // 4. 알림 취소
      final notificationService = NotificationService();
      await notificationService.initialize();
      await notificationService.cancelNotification(id);
      await notificationService.cancelOngoingTracking();
      await notificationService.cancelAllNotifications();
      debugPrint('🚫 모든 알림 취소 완료');

      // 5. 캠시 제거
      _alarmCache.removeWhere((alarm) =>
          alarm.busNo == busNo &&
          alarm.stationName == stationName &&
          alarm.routeId == routeId);

      final cacheKey = "${busNo}_$routeId";
      _cachedBusInfo.remove(cacheKey);
      debugPrint('🚫 캠시에서 알람 제거: $cacheKey');

      // 6. 연관 알람 제거 (일반 알람과 자동 알람 모두)
      _activeAlarms.removeWhere((alarm) =>
          alarm.busNo == busNo &&
          alarm.stationName == stationName &&
          alarm.routeId == routeId);

      _autoAlarms.removeWhere((alarm) =>
          alarm.busNo == busNo &&
          alarm.stationName == stationName &&
          alarm.routeId == routeId);

      debugPrint(
          '🚫 알람 목록에서 제거 완료, 남은 알람 수: ${_activeAlarms.length + _autoAlarms.length}개');

      // 7. 버스 모니터링 서비스 중지
      if (_isInTrackingMode) {
        try {
          await stopBusMonitoringService();
          debugPrint('🚫 버스 모니터링 서비스 중지 성공');
        } catch (e) {
          debugPrint('🚫 버스 모니터링 서비스 중지 오류: $e');

          // 네이티브 메서드 직접 호출 시도
          try {
            await _methodChannel?.invokeMethod('stopBusMonitoringService');
            await _methodChannel?.invokeMethod('stopTtsTracking');
            debugPrint('🚫 메서드 채널을 통한 중지 시도 성공');
          } catch (e2) {
            debugPrint('🚫 메서드 채널을 통한 중지 시도 오류: $e2');
          }

          // 강제로 추적 모드 중지
          _isInTrackingMode = false;
        }
      }

      // 8. TTS 알림
      try {
        await SimpleTTSHelper.speak("$busNo 번 버스 알림이 취소되었습니다.");
        debugPrint('🚫 알람 취소 TTS 성공');
      } catch (e) {
        debugPrint('🚫 알람 취소 TTS 오류: $e');
      }

      // 9. UI 갱신
      notifyListeners();

      debugPrint('🚫 경로별 알람 취소 성공: $busNo, $stationName');
      return true;
    } catch (e) {
      debugPrint('🚫 경로별 알람 취소 오류: $e');

      // 오류가 발생하더라도 알람을 강제로 중지
      try {
        _isInTrackingMode = false;
        await NotificationService().cancelAllNotifications();
        await _methodChannel?.invokeMethod('stopBusMonitoringService');
        await _methodChannel?.invokeMethod('stopTtsTracking');
        notifyListeners();
      } catch (resetError) {
        debugPrint('🚫 오류 발생 후 알람 초기화 시도 중 추가 오류: $resetError');
      }

      return false;
    }
  }

  bool hasAlarm(String busNo, String stationName, String routeId) {
    return _activeAlarms.any((alarm) =>
            alarm.busNo == busNo &&
            alarm.stationName == stationName &&
            alarm.routeId == routeId) ||
        _autoAlarms.any((alarm) =>
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
      try {
        return _autoAlarms.firstWhere((alarm) =>
            alarm.busNo == busNo &&
            alarm.stationName == stationName &&
            alarm.routeId == routeId);
      } catch (e) {
        return null;
      }
    }
  }

  Future<void> refreshAlarms() async {
    await loadAlarms();
    await loadAutoAlarms();
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

    // 자동 알람과 일반 알람 모두에서 제거
    _autoAlarms.removeWhere((alarm) =>
        alarm.busNo == busNo &&
        alarm.stationName == stationName &&
        alarm.routeId == routeId);

    _activeAlarms.removeWhere((alarm) =>
        alarm.busNo == busNo &&
        alarm.stationName == stationName &&
        alarm.routeId == routeId);

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

  // 공휴일 목록을 가져오는 public 메서드
  Future<List<DateTime>> getHolidays(int year, int month) async {
    return _fetchHolidays(year, month);
  }

  Future<void> updateAutoAlarms(List<AutoAlarm> autoAlarms) async {
    _autoAlarms.clear();
    final now = DateTime.now();

    for (var alarm in autoAlarms) {
      if (!alarm.isActive) continue;

      DateTime scheduledTime =
          DateTime(now.year, now.month, now.day, alarm.hour, alarm.minute);
      if (!alarm.repeatDays.contains(now.weekday) ||
          scheduledTime.isBefore(now)) {
        int daysToAdd = 1;
        while (daysToAdd <= 7) {
          final nextDate = now.add(Duration(days: daysToAdd));
          if (alarm.repeatDays.contains(nextDate.weekday)) {
            scheduledTime = DateTime(nextDate.year, nextDate.month,
                nextDate.day, alarm.hour, alarm.minute);
            break;
          }
          daysToAdd++;
        }
      }

      final alarmData = AlarmData(
        busNo: alarm.routeNo,
        stationName: alarm.stationName,
        remainingMinutes: 3,
        routeId: alarm.routeId,
        scheduledTime: scheduledTime,
        useTTS: alarm.useTTS,
      );
      _autoAlarms.add(alarmData);

      // 첫 번째 알람 예약
      final id = alarmData.getAlarmId();
      final initialDelay = scheduledTime.difference(now);
      await Workmanager().registerOneOffTask(
        'autoAlarm_$id',
        'autoAlarmTask',
        initialDelay: initialDelay,
        inputData: {
          'alarmId': id,
          'busNo': alarm.routeNo,
          'stationName': alarm.stationName,
          'remainingMinutes': 3,
          'routeId': alarm.routeId,
          'useTTS': alarm.useTTS,
        },
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );
      debugPrint('자동 알람 예약: ${alarm.routeNo} at $scheduledTime');

      // 다음 반복 알람 예약
      await scheduleNextAutoAlarm(alarm);
    }
    await _saveAutoAlarms();
  }

  Future<void> scheduleNextAutoAlarm(AutoAlarm alarm) async {
    final now = DateTime.now();
    int daysToAdd = 1;

    while (daysToAdd <= 7) {
      final nextDate = now.add(Duration(days: daysToAdd));
      if (alarm.repeatDays.contains(nextDate.weekday)) {
        final nextTime = DateTime(nextDate.year, nextDate.month, nextDate.day,
            alarm.hour, alarm.minute);
        final id =
            "${alarm.routeNo}_${alarm.stationName}_${alarm.routeId}".hashCode;

        await Workmanager().registerOneOffTask(
          'autoAlarm_$id',
          'autoAlarmTask',
          initialDelay: nextTime.difference(now),
          inputData: {
            'alarmId': id,
            'busNo': alarm.routeNo,
            'stationName': alarm.stationName,
            'remainingMinutes': 3,
            'routeId': alarm.routeId,
            'useTTS': alarm.useTTS,
          },
          existingWorkPolicy: ExistingWorkPolicy.replace,
        );

        debugPrint('다음 자동 알람 예약: ${alarm.routeNo} at $nextTime');
        break;
      }
      daysToAdd++;
    }
  }

  Future<void> _saveAutoAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarmsJson =
          _autoAlarms.map((alarm) => jsonEncode(alarm.toJson())).toList();
      await prefs.setStringList('auto_alarms', alarmsJson);
      notifyListeners();
    } catch (e) {
      debugPrint('자동 알람 저장 오류: $e');
    }
  }

  // 자동 알람 로드 메서드 추가
  Future<void> loadAutoAlarms() async {
    // 백그라운드에서 자동 알람 로드 실행
    return compute(_loadAutoAlarmsInBackground, null).then((result) {
      _autoAlarms.clear();
      _autoAlarms.addAll(result);
      notifyListeners();
      debugPrint('✅ 자동 알람 로드 완료: ${_autoAlarms.length}개');
    }).catchError((e) {
      debugPrint('❌ 자동 알람 로드 오류: $e');
      // 오류 발생 시 기존 자동 알람 유지
    });
  }

  // 백그라운드에서 실행될 자동 알람 로드 함수
  static Future<List<AlarmData>> _loadAutoAlarmsInBackground(void _) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarmsJson = prefs.getStringList('auto_alarms') ?? [];
      final List<AlarmData> loadedAutoAlarms = [];
      final now = DateTime.now();

      for (var json in alarmsJson) {
        try {
          final Map<String, dynamic> data = jsonDecode(json);

          // 필수 필드 유효성 검사
          if (!_validateAutoAlarmFields(data)) {
            debugPrint('자동 알람 데이터 필수 필드 누락');
            continue;
          }

          final autoAlarm = AutoAlarm.fromJson(data);

          // 오늘의 예약 시간 계산
          DateTime scheduledTime = DateTime(
            now.year,
            now.month,
            now.day,
            autoAlarm.hour,
            autoAlarm.minute,
          );

          // 이미 지난 시간이면 다음 반복 요일로 설정
          if (scheduledTime.isBefore(now)) {
            // 다음 반복 요일 찾기
            int daysToAdd = 1;
            while (daysToAdd <= 7) {
              final nextDate = now.add(Duration(days: daysToAdd));
              final nextWeekday = nextDate.weekday;
              if (autoAlarm.repeatDays.contains(nextWeekday)) {
                scheduledTime = DateTime(
                  nextDate.year,
                  nextDate.month,
                  nextDate.day,
                  autoAlarm.hour,
                  autoAlarm.minute,
                );
                break;
              }
              daysToAdd++;
            }
          }

          loadedAutoAlarms.add(AlarmData(
            busNo: autoAlarm.routeNo,
            stationName: autoAlarm.stationName,
            remainingMinutes: 3,
            routeId: autoAlarm.routeId,
            scheduledTime: scheduledTime,
            useTTS: autoAlarm.useTTS,
          ));
        } catch (e) {
          debugPrint('자동 알람 데이터 파싱 오류: $e');
        }
      }

      debugPrint('자동 알람 로드 완료: ${loadedAutoAlarms.length}개');
      return loadedAutoAlarms;
    } catch (e) {
      debugPrint('자동 알람 로드 중 오류 발생: $e');
      return []; // 오류 발생 시 빈 리스트 반환
    }
  }

  // 자동 알람 필수 필드 유효성 검사 함수
  static bool _validateAutoAlarmFields(Map<String, dynamic> data) {
    final requiredFields = [
      'routeNo',
      'stationName',
      'stationId',
      'routeId',
      'hour',
      'minute',
      'repeatDays',
    ];

    for (var field in requiredFields) {
      if (!data.containsKey(field) || data[field] == null) {
        return false;
      }

      // String 필드의 경우 빈 문자열 검사
      if ((field == 'routeNo' ||
              field == 'stationName' ||
              field == 'stationId' ||
              field == 'routeId') &&
          (data[field] as String).isEmpty) {
        return false;
      }

      // repeatDays가 리스트인지 확인
      if (field == 'repeatDays' && data[field] is! List) {
        return false;
      }
    }

    return true;
  }
}
