import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart' as xml;
import '../models/auto_alarm.dart';
import '../models/alarm_data.dart' as alarm_model;
import '../utils/simple_tts_helper.dart';
import 'notification_service.dart';
import '../main.dart' show logMessage, LogLevel;

class CachedBusInfo {
  int remainingMinutes;
  String currentStation;
  String stationName;
  String busNo;
  String routeId;
  DateTime _lastUpdated;

  CachedBusInfo({
    required this.remainingMinutes,
    required this.currentStation,
    required this.stationName,
    required this.busNo,
    required this.routeId,
    required DateTime lastUpdated,
  }) : _lastUpdated = lastUpdated;

  DateTime get lastUpdated => _lastUpdated;

  factory CachedBusInfo.fromBusInfo({
    required dynamic busInfo,
    required String busNumber,
    required String routeId,
  }) {
    return CachedBusInfo(
      remainingMinutes: busInfo.getRemainingMinutes(),
      currentStation: busInfo.currentStation,
      stationName: busInfo.currentStation, // 현재 정류장을 stationName으로 사용
      busNo: busNumber,
      routeId: routeId,
      lastUpdated: DateTime.now(),
    );
  }

  int getRemainingMinutes() {
    final now = DateTime.now();
    final difference = now.difference(_lastUpdated);
    return (remainingMinutes - difference.inMinutes).clamp(0, remainingMinutes);
  }
}

class AlarmService extends ChangeNotifier {
  static final AlarmService _instance = AlarmService._internal();
  factory AlarmService() => _instance;

  final Map<String, alarm_model.AlarmData> _activeAlarms = {};
  final NotificationService _notificationService = NotificationService();
  Timer? _alarmCheckTimer;
  final List<alarm_model.AlarmData> _autoAlarms = [];
  bool _initialized = false;
  final Map<String, CachedBusInfo> _cachedBusInfo = {};
  MethodChannel? _methodChannel;
  bool _isInTrackingMode = false;
  final Set<String> _processedNotifications = {};
  Timer? _refreshTimer;

  List<alarm_model.AlarmData> get activeAlarms => _activeAlarms.values.toList();
  List<alarm_model.AlarmData> get autoAlarms => _autoAlarms;
  bool get isInTrackingMode => _isInTrackingMode;

  AlarmService._internal() {
    initialize();
  }

  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await _notificationService.initialize();
      await loadAlarms();
      await loadAutoAlarms();

      _alarmCheckTimer?.cancel();
      _alarmCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        refreshAlarms();
      });

      _initialized = true;
      logMessage('✅ AlarmService 초기화 완료');
    } catch (e) {
      logMessage('❌ AlarmService 초기화 오류: $e', level: LogLevel.error);
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _initialized = false;
    _alarmCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> loadAlarms() async {
    try {
      // 백그라운드 메신저 상태 확인 및 초기화
      if (!kIsWeb) {
        final rootIsolateToken = RootIsolateToken.instance!;
        BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);
      }

      final prefs = await SharedPreferences.getInstance();
      final alarms = prefs.getStringList('alarms') ?? [];
      _activeAlarms.clear();

      for (var json in alarms) {
        try {
          final data = jsonDecode(json);
          final alarm = alarm_model.AlarmData.fromJson(data);
          if (_isAlarmValid(alarm)) {
            final key = "${alarm.busNo}_${alarm.stationName}_${alarm.routeId}";
            _activeAlarms[key] = alarm;
          }
        } catch (e) {
          logMessage('알람 데이터 파싱 오류: $e', level: LogLevel.error);
        }
      }

      logMessage('✅ 알람 로드 완료: ${_activeAlarms.length}개');
      notifyListeners();
    } catch (e) {
      logMessage('알람 로드 중 오류 발생: $e', level: LogLevel.error);
      rethrow;
    }
  }

  bool _isAlarmValid(alarm_model.AlarmData alarm) {
    final now = DateTime.now();
    final difference = alarm.scheduledTime.difference(now);
    return difference.inMinutes > -5; // 5분 이상 지난 알람은 제외
  }

  // void _setupMethodChannel() {
  //   _methodChannel = const MethodChannel('com.example.daegu_bus_app/bus_api');
  //   _methodChannel?.setMethodCallHandler((call) async {
  //     switch (call.method) {
  //       case 'onBusArrival':
  //         try {
  //           final Map<String, dynamic> data =
  //               jsonDecode(call.arguments as String);
  //           final busNumber = data['busNumber'] as String;
  //           final stationName = data['stationName'] as String;
  //           final currentStation = data['currentStation'] as String;
  //           final routeId = data['routeId'] as String? ?? '';

  //           debugPrint(
  //               '버스 도착 이벤트 수신: $busNumber, $stationName, $currentStation');

  //           await _handleBusArrival(
  //               busNumber, stationName, currentStation, routeId);

  //           return true;
  //         } catch (e) {
  //           debugPrint('버스 도착 이벤트 처리 오류: $e');

  //           // 예외가 발생해도 TTS 시도
  //           try {
  //             final busNumber =
  //                 jsonDecode(call.arguments as String)['busNumber']
  //                         as String? ??
  //                     "알 수 없음";
  //             final stationName =
  //                 jsonDecode(call.arguments as String)['stationName']
  //                         as String? ??
  //                     "알 수 없음";
  //             SimpleTTSHelper.speak(
  //                 "$busNumber 번 버스가 $stationName 정류장에 곧 도착합니다. 탑승 준비하세요.");
  //           } catch (ttsError) {
  //             debugPrint('예외 상황에서 TTS 시도 실패: $ttsError');
  //           }

  //           return false;
  //         }

  //       case 'onBusLocationUpdate':
  //         try {
  //           final Map<String, dynamic> data =
  //               jsonDecode(call.arguments as String);
  //           final String busNumber = data['busNumber'] ?? '';
  //           final String currentStation = data['currentStation'] ?? '';
  //           final int remainingMinutes = data['remainingMinutes'] ?? 0;
  //           final String routeId = data['routeId'] ?? '';

  //           debugPrint(
  //               '버스 위치 업데이트: $busNumber, 남은 시간: $remainingMinutes분, 현재 위치: $currentStation');

  //           final busInfo = bus_arrival.BusInfo(
  //             busNumber: busNumber,
  //             currentStation: currentStation,
  //             remainingStops: remainingMinutes.toString(),
  //             estimatedTime: remainingMinutes.toString(),
  //             isLowFloor: false,
  //             isOutOfService: false,
  //           );

  //           final cachedInfo = CachedBusInfo.fromBusInfo(
  //             busInfo: busInfo,
  //             busNumber: busNumber,
  //             routeId: routeId,
  //           );

  //           await _handleBusLocationUpdate(cachedInfo);
  //           return true;
  //         } catch (e) {
  //           debugPrint('버스 위치 업데이트 처리 오류: $e');
  //           return false;
  //         }

  //       case 'onTrackingCancelled':
  //         _isInTrackingMode = false;
  //         _processedNotifications.clear();
  //         notifyListeners();
  //         return true;

  //       case 'stopBusMonitoringService':
  //         _isInTrackingMode = false;
  //         notifyListeners();
  //         return true;
  //     }

  //     return null;
  //   });
  // }

  Future<bool> startBusMonitoringService({
    required String stationId,
    required String stationName,
    required String routeId,
    required String busNo,
  }) async {
    try {
      // routeId가 비어있으면 기본값 설정
      final String effectiveRouteId =
          routeId.isEmpty ? '${busNo}_$stationName' : routeId;

      final Map<String, dynamic> arguments = {
        'stationId': stationId,
        'stationName': stationName,
        'routeId': effectiveRouteId,
        'busNo': busNo,
      };

      await _methodChannel?.invokeMethod(
          'startBusMonitoringService', arguments);
      _isInTrackingMode = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('🚌 버스 모니터링 서비스 시작 오류: $e');
      rethrow;
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

  // bool _isNotificationProcessed(String busNo, String stationName,
  //     [String? routeId]) {
  //   final key = "${busNo}_${stationName}_${routeId ?? ""}";
  //   return _processedNotifications.contains(key);
  // }

  // void _markNotificationAsProcessed(String busNo, String stationName,
  //     [String? routeId]) {
  //   final key = "${busNo}_${stationName}_${routeId ?? ""}";
  //   _processedNotifications.add(key);
  //   if (_processedNotifications.length > 100) {
  //     _processedNotifications.remove(_processedNotifications.first);
  //   }
  // }

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
      final alarm = _activeAlarms.values.first;
      final key = "${alarm.busNo}_${alarm.routeId}";
      final cachedInfo = _cachedBusInfo[key];

      // 캐시된 실시간 정보가 있는 경우
      if (cachedInfo != null) {
        final remainingMinutes = cachedInfo.remainingMinutes;
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
      final remainingMinutes = cachedInfo.remainingMinutes;

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
    String busNo,
    String routeId,
    dynamic busInfo,
    int remainingMinutes,
  ) {
    final cachedInfo = CachedBusInfo.fromBusInfo(
      busInfo: busInfo,
      busNumber: busNo,
      routeId: routeId,
    );
    final key = "${busNo}_$routeId";
    _cachedBusInfo[key] = cachedInfo;
    logMessage('🚌 버스 정보 캐시 업데이트: $busNo번, $remainingMinutes분 후');
  }

  // 버스 위치 정보 캐시 업데이트 헬퍼 메서드
  // Future<bool> _handleBusLocationUpdate(CachedBusInfo busInfo) async {
  //   try {
  //     final key = "${busInfo.busNo}_${busInfo.routeId}";
  //     _cachedBusInfo[key] = busInfo;

  //     // 알람이 설정된 버스인지 확인
  //     final alarmKey =
  //         "${busInfo.busNo}_${busInfo.stationName}_${busInfo.routeId}";
  //     final alarm = _activeAlarms[alarmKey];

  //     if (alarm != null) {
  //       // 알람 시간 업데이트
  //       alarm.updateRemainingMinutes(busInfo.getRemainingMinutes());

  //       // 도착 임박 알림 (3분 이하)
  //       if (busInfo.getRemainingMinutes() <= 3) {
  //         await _notificationService.showBusArrivingSoon(
  //           busNo: busInfo.busNo,
  //           stationName: busInfo.stationName,
  //           currentStation: busInfo.currentStation,
  //         );
  //       }
  //     }

  //     return true;
  //   } catch (e) {
  //     logMessage('버스 위치 업데이트 처리 오류: $e', level: LogLevel.error);
  //     return false;
  //   }
  // }

  // SharedPreferences에 알람 정보를 저장하는 헬퍼 메서드
  // Future<void> _updateAlarmInStorage(alarm_model.AlarmData alarm) async {
  //   try {
  //     final id = alarm.getAlarmId();
  //     final prefs = await SharedPreferences.getInstance();
  //     await prefs.setString('alarm_$id', jsonEncode(alarm.toJson()));
  //     debugPrint(
  //         '알람 저장소 업데이트 완료: $alarm.busNo, 남은 시간: ${alarm.getCurrentArrivalMinutes()}분');
  //   } catch (e) {
  //     debugPrint('알람 저장소 업데이트 오류: $e');
  //   }
  // }

  // 추적 알림 업데이트 요청
  // Future<void> _updateTrackingNotification(String busNo, String routeId) async {
  //   try {
  //     final key = "${busNo}_$routeId";
  //     final cachedInfo = _cachedBusInfo[key];

  //     if (cachedInfo != null) {
  //       final remainingMinutes = cachedInfo.getRemainingMinutes();

  //       // 알람이 설정된 버스인지 확인
  //       final alarmKey = "${busNo}_${cachedInfo.stationName}_$routeId";
  //       final alarm = _activeAlarms[alarmKey];

  //       if (alarm != null) {
  //         await _notificationService.showNotification(
  //           id: alarm.getAlarmId(),
  //           busNo: busNo,
  //           stationName: cachedInfo.stationName,
  //           remainingMinutes: remainingMinutes,
  //           currentStation: cachedInfo.currentStation,
  //           isOngoing: true,
  //           routeId: routeId,
  //         );
  //       }
  //     }
  //   } catch (e) {
  //     logMessage('알림 업데이트 오류: $e', level: LogLevel.error);
  //   }
  // }

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
  static Future<List<alarm_model.AlarmData>> _loadAutoAlarmsInBackground(
      void _) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarmsJson = prefs.getStringList('auto_alarms') ?? [];
      final List<alarm_model.AlarmData> loadedAutoAlarms = [];
      final now = DateTime.now();

      for (var json in alarmsJson) {
        try {
          final Map<String, dynamic> data = jsonDecode(json);

          // 필수 필드 유효성 검사
          if (!_validateAutoAlarmFields(data)) {
            debugPrint('⚠️ 자동 알람 데이터 필수 필드 누락');
            continue;
          }

          final autoAlarm = AutoAlarm.fromJson(data);

          // 비활성화된 알람은 건너뛰기
          if (!autoAlarm.isActive) {
            debugPrint('ℹ️ 비활성화된 자동 알람 건너뛰기: ${autoAlarm.routeNo}');
            continue;
          }

          // 오늘의 예약 시간 계산
          DateTime scheduledTime = DateTime(
            now.year,
            now.month,
            now.day,
            autoAlarm.hour,
            autoAlarm.minute,
          );

          // 오늘이 반복 요일이 아니거나 이미 지난 시간이면 다음 반복 요일 찾기
          if (!autoAlarm.repeatDays.contains(now.weekday) ||
              scheduledTime.isBefore(now)) {
            // 다음 반복 요일 찾기
            int daysToAdd = 1;
            bool foundValidDay = false;

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
                foundValidDay = true;
                break;
              }
              daysToAdd++;
            }

            // 유효한 반복 요일을 찾지 못한 경우 건너뛰기
            if (!foundValidDay) {
              debugPrint('⚠️ 유효한 반복 요일을 찾지 못함: ${autoAlarm.routeNo}');
              continue;
            }
          }

          // 알람 시간이 현재로부터 7일 이내인지 확인
          final initialDelay = scheduledTime.difference(now);
          if (initialDelay.inDays > 7) {
            debugPrint(
                '⚠️ 알람 시간이 너무 멀어서 건너뛰기: ${autoAlarm.routeNo}, ${initialDelay.inDays}일 후');
            continue;
          }

          // 알람 데이터 생성 및 추가
          final alarmData = alarm_model.AlarmData(
            busNo: autoAlarm.routeNo,
            stationName: autoAlarm.stationName,
            remainingMinutes: 0,
            routeId: autoAlarm.routeId,
            scheduledTime: scheduledTime,
            useTTS: autoAlarm.useTTS,
          );
          loadedAutoAlarms.add(alarmData);
          debugPrint(
              '✅ 자동 알람 로드: ${autoAlarm.routeNo}, 예정 시간: $scheduledTime (${initialDelay.inDays}일 ${initialDelay.inHours % 24}시간 후)');
        } catch (e) {
          debugPrint('❌ 자동 알람 파싱 오류: $e');
        }
      }

      debugPrint('✅ 자동 알람 로드 완료: ${loadedAutoAlarms.length}개');
      return loadedAutoAlarms;
    } catch (e) {
      debugPrint('❌ 자동 알람 로드 중 오류 발생: $e');
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

  // background_service.dart에서 사용하는 startAlarm 메서드 추가
  Future<bool> startAlarm(
      String busNo, String stationName, int remainingMinutes) async {
    try {
      debugPrint('🔔 startAlarm 호출: $busNo, $stationName, $remainingMinutes분');

      // 알람 ID 생성
      final int id = getAlarmId(busNo, stationName);

      // TTS 발화 시도
      try {
        await SimpleTTSHelper.initialize();
        if (remainingMinutes <= 0) {
          await SimpleTTSHelper.speak(
              "$busNo번 버스가 $stationName 정류장에 곧 도착합니다. 탑승 준비하세요.");
        } else {
          await SimpleTTSHelper.speak(
              "$busNo번 버스가 약 $remainingMinutes분 후 $stationName 정류장에 도착 예정입니다.");
        }
        debugPrint('🔊 TTS 발화 성공');
      } catch (e) {
        debugPrint('🔊 TTS 발화 오류: $e');
      }

      // 알림 표시
      await NotificationService().showNotification(
        id: id,
        busNo: busNo,
        stationName: stationName,
        remainingMinutes: remainingMinutes,
        currentStation: '',
      );

      return true;
    } catch (e) {
      debugPrint('❌ startAlarm 오류: $e');
      return false;
    }
  }

  int getAlarmId(String busNo, String stationName, {String routeId = ''}) {
    return ("${busNo}_${stationName}_$routeId").hashCode;
  }

  bool hasAlarm(String busNo, String stationName, String routeId) {
    return _activeAlarms.values.any((alarm) =>
            alarm.busNo == busNo &&
            alarm.stationName == stationName &&
            alarm.routeId == routeId) ||
        _autoAlarms.any((alarm) =>
            alarm.busNo == busNo &&
            alarm.stationName == stationName &&
            alarm.routeId == routeId);
  }

  // 자동 알람이 있는지 확인하는 메서드 추가
  bool hasAutoAlarm(String busNo, String stationName, String routeId) {
    return _autoAlarms.any((alarm) =>
        alarm.busNo == busNo &&
        alarm.stationName == stationName &&
        alarm.routeId == routeId);
  }

  // 자동 알람 데이터를 가져오는 메서드 추가
  alarm_model.AlarmData? getAutoAlarm(
      String busNo, String stationName, String routeId) {
    try {
      return _autoAlarms.firstWhere((alarm) =>
          alarm.busNo == busNo &&
          alarm.stationName == stationName &&
          alarm.routeId == routeId);
    } catch (e) {
      debugPrint('자동 알람을 찾을 수 없음: $busNo, $stationName, $routeId');
      return null;
    }
  }

  alarm_model.AlarmData? findAlarm(
      String busNo, String stationName, String routeId) {
    try {
      return _activeAlarms.values.firstWhere((alarm) =>
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

  void removeFromCacheBeforeCancel(
      String busNo, String stationName, String routeId) {
    final keysToRemove = <String>[];
    _activeAlarms.forEach((key, alarm) {
      if (alarm.busNo == busNo &&
          alarm.stationName == stationName &&
          alarm.routeId == routeId) {
        keysToRemove.add(key);
      }
    });

    for (var key in keysToRemove) {
      _activeAlarms.remove(key);
    }

    final cacheKey = "${busNo}_$routeId";
    _cachedBusInfo.remove(cacheKey);

    _autoAlarms.removeWhere((alarm) =>
        alarm.busNo == busNo &&
        alarm.stationName == stationName &&
        alarm.routeId == routeId);

    notifyListeners();
  }

  Future<List<DateTime>> _fetchHolidays(int year, int month) async {
    try {
      final String serviceKey = dotenv.env['SERVICE_KEY'] ?? '';
      if (serviceKey.isEmpty) {
        logMessage('❌ SERVICE_KEY가 설정되지 않았습니다', level: LogLevel.error);
        return [];
      }

      final String url =
          'http://apis.data.go.kr/B090041/openapi/service/SpcdeInfoService/getRestDeInfo'
          '?serviceKey=$serviceKey'
          '&solYear=$year'
          '&solMonth=${month.toString().padLeft(2, '0')}'
          '&numOfRows=100';

      try {
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          try {
            final holidays = <DateTime>[];
            final xmlDoc = xml.XmlDocument.parse(response.body);
            final items = xmlDoc.findAllElements('item');

            for (var item in items) {
              final isHoliday =
                  item.findElements('isHoliday').firstOrNull?.innerText;
              if (isHoliday == 'Y') {
                final locdate =
                    item.findElements('locdate').firstOrNull?.innerText;
                if (locdate != null && locdate.length == 8) {
                  final year = int.parse(locdate.substring(0, 4));
                  final month = int.parse(locdate.substring(4, 6));
                  final day = int.parse(locdate.substring(6, 8));
                  holidays.add(DateTime(year, month, day));
                }
              }
            }

            logMessage('✅ 공휴일 목록 ($year-$month): ${holidays.length}개 공휴일 발견');
            return holidays;
          } catch (e) {
            logMessage('❌ XML 파싱 오류: $e', level: LogLevel.error);
            return [];
          }
        } else {
          logMessage('❌ 공휴일 API 응답 오류: ${response.statusCode}',
              level: LogLevel.error);
          return [];
        }
      } catch (e) {
        logMessage('❌ 공휴일 API 호출 오류: $e', level: LogLevel.error);
        return [];
      }
    } catch (e) {
      logMessage('❌ 공휴일 조회 오류: $e', level: LogLevel.error);
      return [];
    }
  }

  // 공휴일 목록을 가져오는 public 메서드
  Future<List<DateTime>> getHolidays(int year, int month) async {
    return _fetchHolidays(year, month);
  }

  Future<void> _scheduleAutoAlarm(
      AutoAlarm alarm, DateTime scheduledTime) async {
    try {
      final now = DateTime.now();
      final id =
          "${alarm.routeNo}_${alarm.stationName}_${alarm.routeId}".hashCode;
      final initialDelay = scheduledTime.difference(now);

      if (initialDelay.inDays <= 7) {
        await Workmanager().registerOneOffTask(
          'autoAlarm_$id',
          'autoAlarmTask',
          initialDelay: initialDelay,
          inputData: {
            'alarmId': id,
            'busNo': alarm.routeNo,
            'stationName': alarm.stationName,
            'remainingMinutes': 0,
            'routeId': alarm.routeId,
            'useTTS': alarm.useTTS,
            'stationId': alarm.stationId,
          },
          constraints: Constraints(
            networkType: NetworkType.connected,
            requiresBatteryNotLow: true,
          ),
          backoffPolicy: BackoffPolicy.linear,
          existingWorkPolicy: ExistingWorkPolicy.replace,
        );

        logMessage(
            '✅ 자동 알람 예약: ${alarm.routeNo} at $scheduledTime (${initialDelay.inDays}일 ${initialDelay.inHours % 24}시간 후)');
      } else {
        logMessage('⚠️ 알람 시간이 너무 멀어서 건너뛰기: ${initialDelay.inDays}일',
            level: LogLevel.warning);
      }
    } catch (e) {
      logMessage('❌ 자동 알람 예약 오류: $e', level: LogLevel.error);
    }
  }

  Future<void> updateAutoAlarms(List<AutoAlarm> autoAlarms) async {
    try {
      _autoAlarms.clear();
      final now = DateTime.now();

      for (var alarm in autoAlarms) {
        if (!alarm.isActive) continue;

        // 오늘 예약 시간 계산
        DateTime scheduledTime =
            DateTime(now.year, now.month, now.day, alarm.hour, alarm.minute);

        // 오늘이 반복 요일이 아니거나 이미 지난 시간이면 다음 반복 요일 찾기
        if (!alarm.repeatDays.contains(now.weekday) ||
            scheduledTime.isBefore(now)) {
          int daysToAdd = 1;
          bool foundValidDay = false;

          while (daysToAdd <= 7) {
            final nextDate = now.add(Duration(days: daysToAdd));
            if (alarm.repeatDays.contains(nextDate.weekday)) {
              scheduledTime = DateTime(
                nextDate.year,
                nextDate.month,
                nextDate.day,
                alarm.hour,
                alarm.minute,
              );
              foundValidDay = true;
              break;
            }
            daysToAdd++;
          }

          if (!foundValidDay) {
            logMessage('⚠️ 유효한 반복 요일을 찾지 못함: ${alarm.routeNo}',
                level: LogLevel.warning);
            continue;
          }
        }

        // 알람 데이터 생성
        final alarmData = alarm_model.AlarmData(
          busNo: alarm.routeNo,
          stationName: alarm.stationName,
          remainingMinutes: 0,
          routeId: alarm.routeId,
          scheduledTime: scheduledTime,
          useTTS: alarm.useTTS,
        );
        _autoAlarms.add(alarmData);

        // 알람 예약
        await _scheduleAutoAlarm(alarm, scheduledTime);
      }

      await _saveAutoAlarms();
      logMessage('✅ 자동 알람 업데이트 완료: ${_autoAlarms.length}개');
    } catch (e) {
      logMessage('❌ 자동 알람 업데이트 오류: $e', level: LogLevel.error);
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

  // Future<void> _handleBusArrival(
  //   String busNo,
  //   String stationName,
  //   String currentStation,
  //   String routeId,
  // ) async {
  //   try {
  //     // 버스 도착 정보를 BusInfo 객체로 생성
  //     final busInfo = bus_arrival.BusInfo(
  //       busNumber: busNo,
  //       currentStation: currentStation,
  //       remainingStops: "0",
  //       estimatedTime: "곧 도착",
  //       isLowFloor: false,
  //       isOutOfService: false,
  //     );

  //     // 캐시 업데이트
  //     final cachedInfo = CachedBusInfo.fromBusInfo(
  //       busInfo: busInfo,
  //       busNumber: busNo,
  //       routeId: routeId,
  //     );

  //     await _handleBusLocationUpdate(cachedInfo);

  //     // 알람이 설정된 버스인지 확인
  //     final alarmKey = "${busNo}_${stationName}_$routeId";
  //     final alarm = _activeAlarms[alarmKey];

  //     if (alarm != null) {
  //       // 도착 알림 표시
  //       await _notificationService.showBusArrivingSoon(
  //         busNo: busNo,
  //         stationName: stationName,
  //         currentStation: currentStation,
  //       );
  //     }
  //   } catch (e) {
  //     logMessage('버스 도착 처리 오류: $e', level: LogLevel.error);
  //   }
  // }

  Future<bool> setOneTimeAlarm(
    String busNo,
    String stationName,
    int remainingMinutes, {
    String routeId = '',
    bool useTTS = true,
    bool isImmediateAlarm = true,
    String? currentStation,
  }) async {
    try {
      logMessage('🚌 알람 설정 시작: $busNo번 버스, $stationName, $remainingMinutes분');

      // 알람 데이터 생성
      final alarmData = alarm_model.AlarmData(
        busNo: busNo,
        stationName: stationName,
        remainingMinutes: remainingMinutes,
        routeId: routeId,
        scheduledTime: DateTime.now().add(Duration(minutes: remainingMinutes)),
        currentStation: currentStation,
        useTTS: useTTS,
      );

      // 알람 ID 생성
      final alarmId = alarmData.getAlarmId();

      // 알람 저장
      _activeAlarms[alarmId.toString()] = alarmData;
      await _saveAlarms();

      // 즉시 알림 표시가 필요한 경우
      if (isImmediateAlarm) {
        await _notificationService.showNotification(
          id: alarmId,
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          currentStation: currentStation,
          isOngoing: true,
          routeId: routeId,
        );

        // TTS 알림 시작 (설정된 경우)
        if (useTTS) {
          await SimpleTTSHelper.speak(
              "$busNo번 버스가 $stationName 정류장에 $remainingMinutes분 후 도착 예정입니다.");
        }
      }

      logMessage('✅ 알람 설정 완료: $busNo번 버스');
      notifyListeners();
      return true;
    } catch (e) {
      logMessage('❌ 알람 설정 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  Future<void> _saveAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> alarms = _activeAlarms.values
          .map((alarm) => jsonEncode(alarm.toJson()))
          .toList();
      await prefs.setStringList('alarms', alarms);
      logMessage('✅ 알람 저장 완료: ${alarms.length}개');
    } catch (e) {
      logMessage('❌ 알람 저장 오류: $e', level: LogLevel.error);
    }
  }

  Future<bool> cancelAlarmByRoute(
    String busNo,
    String stationName,
    String routeId,
  ) async {
    try {
      logMessage('🚌 알람 취소 시작: $busNo번 버스, $stationName');

      // 알람 ID 생성
      final alarmKey = "${busNo}_${stationName}_$routeId";
      final alarm = _activeAlarms[alarmKey];

      if (alarm == null) {
        logMessage('❌ 취소할 알람을 찾을 수 없음: $alarmKey');
        return false;
      }

      // 알람 취소
      _activeAlarms.remove(alarmKey);
      await _saveAlarms();

      // 알림 취소
      await _notificationService.cancelNotification(alarm.getAlarmId());

      // 버스 모니터링 서비스 중지
      await stopBusMonitoringService();

      // TTS 알림 중지
      if (alarm.useTTS) {
        await SimpleTTSHelper.speak("$busNo번 버스 알람이 취소되었습니다.");
      }

      logMessage('✅ 알람 취소 완료: $busNo번 버스');
      notifyListeners();
      return true;
    } catch (e) {
      logMessage('❌ 알람 취소 오류: $e', level: LogLevel.error);
      return false;
    }
  }
}
