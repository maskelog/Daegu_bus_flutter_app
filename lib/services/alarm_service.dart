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
import 'settings_service.dart';
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

  Future<void> loadAutoAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarms = prefs.getStringList('auto_alarms') ?? [];
      logMessage('자동 알람 데이터 로드 시작: ${alarms.length}개');

      _autoAlarms.clear();

      for (var alarmJson in alarms) {
        try {
          final Map<String, dynamic> data = jsonDecode(alarmJson);

          // 필수 필드 검증
          if (!_validateRequiredFields(data)) {
            logMessage('⚠️ 자동 알람 데이터 필수 필드 누락: $data', level: LogLevel.warning);
            continue;
          }

          final alarm = alarm_model.AlarmData(
            busNo: data['routeNo'] ?? '',
            stationName: data['stationName'] ?? '',
            remainingMinutes: 0,
            routeId: data['routeId'] ?? '',
            scheduledTime: DateTime(
              DateTime.now().year,
              DateTime.now().month,
              DateTime.now().day,
              data['hour'] ?? 0,
              data['minute'] ?? 0,
            ),
            useTTS: data['useTTS'] ?? true,
          );

          _autoAlarms.add(alarm);
          logMessage('✅ 자동 알람 로드: ${alarm.busNo}, ${alarm.stationName}');
        } catch (e) {
          logMessage('❌ 자동 알람 파싱 오류: $e', level: LogLevel.error);
          continue;
        }
      }

      logMessage('✅ 자동 알람 로드 완료: ${_autoAlarms.length}개');
      notifyListeners();
    } catch (e) {
      logMessage('❌ 자동 알람 로드 실패: $e', level: LogLevel.error);
    }
  }

  bool _validateRequiredFields(Map<String, dynamic> data) {
    final requiredFields = [
      'routeNo',
      'stationId',
      'hour',
      'minute',
      'repeatDays'
    ];
    final missingFields = requiredFields
        .where((field) =>
            data[field] == null ||
            (data[field] is String && data[field].isEmpty) ||
            (data[field] is List && (data[field] as List).isEmpty))
        .toList();

    if (missingFields.isNotEmpty) {
      logMessage('! 자동 알람 데이터 필수 필드 누락: ${missingFields.join(", ")}');
      return false;
    }
    return true;
  }

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

  CachedBusInfo? getCachedBusInfo(String busNo, String routeId) {
    final key = "${busNo}_$routeId";
    return _cachedBusInfo[key];
  }

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

  Future<void> _updateNextAlarmTime(AutoAlarm alarm) async {
    final nextAlarmTime = alarm.getNextAlarmTime();
    if (nextAlarmTime != null) {
      logMessage(
          '[AlarmService] Updated next alarm time for ${alarm.routeNo} to ${nextAlarmTime.toString()}');
    }
  }

  Future<void> updateAutoAlarms(List<AutoAlarm> autoAlarms) async {
    try {
      logMessage('🔄 자동 알람 업데이트 시작: ${autoAlarms.length}개');

      _autoAlarms.clear();
      final now = DateTime.now();

      for (var alarm in autoAlarms) {
        logMessage('📝 알람 처리 중:');
        logMessage('  - 버스: ${alarm.routeNo}번');
        logMessage('  - 정류장: ${alarm.stationName}');
        logMessage('  - 시간: ${alarm.hour}:${alarm.minute}');
        logMessage('  - 반복: ${alarm.repeatDays.map((d) => [
              '월',
              '화',
              '수',
              '목',
              '금',
              '토',
              '일'
            ][d - 1]).join(', ')}');
        logMessage('  - 활성화: ${alarm.isActive}');

        if (!alarm.isActive) {
          logMessage('  ⚠️ 비활성화된 알람 건너뛰기');
          continue;
        }

        // 다음 알람 시간 업데이트
        await _updateNextAlarmTime(alarm);

        // 오늘 예약 시간 계산
        DateTime scheduledTime =
            DateTime(now.year, now.month, now.day, alarm.hour, alarm.minute);

        // 오늘이 반복 요일이 아니거나 이미 지난 시간이면 다음 반복 요일 찾기
        if (!alarm.repeatDays.contains(now.weekday) ||
            scheduledTime.isBefore(now)) {
          logMessage('  🔄 다음 유효한 알람 시간 계산 중...');
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
              logMessage('  ✅ 다음 알람 시간 찾음: ${scheduledTime.toString()}');
              break;
            }
            daysToAdd++;
          }

          if (!foundValidDay) {
            logMessage('  ⚠️ 유효한 반복 요일을 찾지 못함: ${alarm.routeNo}',
                level: LogLevel.warning);
            continue;
          }
        }

        // 알람 시간까지 남은 시간 계산
        final timeUntilAlarm = scheduledTime.difference(now);
        logMessage('  ⏰ 다음 알람까지 ${timeUntilAlarm.inMinutes}분 남음');

        // 알람 시간이 10분 이내면 버스 모니터링 시작
        if (timeUntilAlarm.inMinutes <= 10) {
          logMessage('  🚌 10분 이내 알람 - 버스 모니터링 시작');
          await startBusMonitoringService(
            routeId: alarm.routeId,
            stationId: alarm.stationId,
            busNo: alarm.routeNo,
            stationName: alarm.stationName,
          );
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
        logMessage('  ✅ 알람 데이터 생성 완료');

        // 알람 예약
        await _scheduleAutoAlarm(alarm, scheduledTime);
      }

      await _saveAutoAlarms();
      logMessage('✅ 자동 알람 업데이트 완료: ${_autoAlarms.length}개');

      // 저장된 알람 정보 출력
      for (var alarm in _autoAlarms) {
        logMessage('📋 저장된 알람 정보:');
        logMessage('  - 버스: ${alarm.busNo}번');
        logMessage('  - 정류장: ${alarm.stationName}');
        logMessage('  - 예약 시간: ${alarm.scheduledTime.toString()}');
      }
    } catch (e) {
      logMessage('❌ 자동 알람 업데이트 오류: $e', level: LogLevel.error);
      logMessage('  - 스택 트레이스: ${e is Error ? e.stackTrace : "없음"}');
    }
  }

  Future<void> _saveAutoAlarms() async {
    try {
      logMessage('🔄 자동 알람 저장 시작...');
      final prefs = await SharedPreferences.getInstance();
      final List<String> alarms = _autoAlarms.map((alarm) {
        // 현재 요일을 기준으로 반복 요일 설정
        final now = DateTime.now();
        List<int> repeatDays = [];

        // 월요일부터 일요일까지 체크
        for (int i = 1; i <= 7; i++) {
          final checkDate = now.add(Duration(days: i - now.weekday));
          if (checkDate.difference(alarm.scheduledTime).inDays % 7 == 0) {
            repeatDays.add(i);
          }
        }

        // 반복 요일이 없으면 기본값으로 평일 설정
        if (repeatDays.isEmpty) {
          repeatDays = [1, 2, 3, 4, 5];
        }

        final autoAlarm = AutoAlarm(
          id: alarm.getAlarmId().toString(),
          routeNo: alarm.busNo,
          stationName: alarm.stationName,
          stationId: alarm.routeId,
          routeId: alarm.routeId,
          hour: alarm.scheduledTime.hour,
          minute: alarm.scheduledTime.minute,
          repeatDays: repeatDays,
          useTTS: alarm.useTTS,
          isActive: true,
        );

        final json = autoAlarm.toJson();
        final jsonString = jsonEncode(json);

        // 각 알람의 데이터 로깅
        logMessage('📝 알람 데이터 변환: ${alarm.busNo}번 버스');
        logMessage('  - ID: ${autoAlarm.id}');
        logMessage('  - 시간: ${autoAlarm.hour}:${autoAlarm.minute}');
        logMessage(
            '  - 정류장: ${autoAlarm.stationName} (${autoAlarm.stationId})');
        logMessage('  - 반복: ${repeatDays.map((d) => [
              '월',
              '화',
              '수',
              '목',
              '금',
              '토',
              '일'
            ][d - 1]).join(", ")}');
        logMessage('  - JSON: $jsonString');

        return jsonString;
      }).toList();

      // 저장 전 데이터 확인
      logMessage('📊 저장할 알람 수: ${alarms.length}개');

      // SharedPreferences에 저장
      await prefs.setStringList('auto_alarms', alarms);

      // 저장 후 확인
      final savedAlarms = prefs.getStringList('auto_alarms') ?? [];
      logMessage('✅ 자동 알람 저장 완료');
      logMessage('  - 저장된 알람 수: ${savedAlarms.length}개');
      if (savedAlarms.isNotEmpty) {
        final firstAlarm = jsonDecode(savedAlarms.first);
        logMessage('  - 첫 번째 알람 정보:');
        logMessage('    • 버스: ${firstAlarm['routeNo']}');
        logMessage('    • 시간: ${firstAlarm['hour']}:${firstAlarm['minute']}');
        logMessage('    • 반복: ${(firstAlarm['repeatDays'] as List).map((d) => [
              '월',
              '화',
              '수',
              '목',
              '금',
              '토',
              '일'
            ][d - 1]).join(", ")}');
      }
    } catch (e) {
      logMessage('❌ 자동 알람 저장 오류: $e', level: LogLevel.error);
      logMessage('  - 스택 트레이스: ${e is Error ? e.stackTrace : "없음"}');
    }
  }

  Future<bool> startAlarm(
      String busNo, String stationName, int remainingMinutes) async {
    try {
      debugPrint(
          '🔔 startAlarm 호출 (자동 알람 가정): $busNo, $stationName, $remainingMinutes분');

      // 알람 ID 생성
      final int id = getAlarmId(busNo, stationName);

      // 설정된 알람 볼륨 가져오기
      final settingsService = SettingsService();
      await settingsService.initialize();
      final volume = settingsService.autoAlarmVolume;

      // TTS 발화 시도 (자동 알람 -> 스피커 우선)
      try {
        await SimpleTTSHelper.initialize();
        await SimpleTTSHelper.setAudioOutputMode(1); // 스피커 모드 설정
        await SimpleTTSHelper.setVolume(volume); // 볼륨 설정
        if (remainingMinutes <= 0) {
          await SimpleTTSHelper.speak(
              "$busNo번 버스가 $stationName 정류장에 곧 도착합니다. 탑승 준비하세요.");
        } else {
          await SimpleTTSHelper.speak(
              "$busNo번 버스가 약 $remainingMinutes분 후 $stationName 정류장에 도착 예정입니다.");
        }
        await SimpleTTSHelper.setAudioOutputMode(2); // 자동 모드로 복원 (선택 사항)
        debugPrint('🔊 TTS 발화 성공 (스피커 모드, 볼륨: ${volume * 100}%)');
      } catch (e) {
        debugPrint('🔊 TTS 발화 오류: $e');
        await SimpleTTSHelper.setAudioOutputMode(2); // 오류 시 자동 모드로 복원
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

  bool hasAutoAlarm(String busNo, String stationName, String routeId) {
    return _autoAlarms.any((alarm) =>
        alarm.busNo == busNo &&
        alarm.stationName == stationName &&
        alarm.routeId == routeId);
  }

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
      logMessage(
          '🚌 일반 알람 설정 시작: $busNo번 버스, $stationName, $remainingMinutes분');

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

      // 설정된 알람 볼륨 가져오기
      final settingsService = SettingsService();
      await settingsService.initialize();
      final volume = settingsService.autoAlarmVolume;

      // TTS 알림 시작 (설정된 경우 - 일반 알람 -> 이어폰 우선)
      if (useTTS) {
        try {
          await SimpleTTSHelper.initialize();
          await SimpleTTSHelper.setAudioOutputMode(0); // 이어폰 모드 설정
          await SimpleTTSHelper.setVolume(volume); // 볼륨 설정
          await SimpleTTSHelper.speak(
              "$busNo번 버스가 $stationName 정류장에 $remainingMinutes분 후 도착 예정입니다.");
          await SimpleTTSHelper.setAudioOutputMode(2); // 자동 모드로 복원 (선택 사항)
          logMessage('🔊 TTS 발화 성공 (이어폰 모드, 볼륨: ${volume * 100}%)');
        } catch (e) {
          logMessage('🔊 TTS 발화 오류: $e', level: LogLevel.error);
          await SimpleTTSHelper.setAudioOutputMode(2); // 오류 시 자동 모드로 복원
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
