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
import '../utils/database_helper.dart';

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
  final SettingsService _settingsService = SettingsService();
  bool get _useTTS => _settingsService.useTts;
  Timer? _alarmCheckTimer;
  final List<alarm_model.AlarmData> _autoAlarms = [];
  bool _initialized = false;
  final Map<String, CachedBusInfo> _cachedBusInfo = {};
  MethodChannel? _methodChannel;
  bool _isInTrackingMode = false;
  String? _trackedRouteId;
  final Set<String> _processedNotifications = {};
  Timer? _refreshTimer;

  List<alarm_model.AlarmData> get activeAlarms => _activeAlarms.values.toList();
  List<alarm_model.AlarmData> get autoAlarms => _autoAlarms;
  bool get isInTrackingMode => _isInTrackingMode;

  AlarmService._internal() {
    initialize();
    _setupMethodChannel();
  }

  void _setupMethodChannel() {
    _methodChannel = const MethodChannel('com.example.daegu_bus_app/bus_api');
    _methodChannel?.setMethodCallHandler(_handleMethodCall);
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onAlarmCanceledFromNotification':
          final Map<String, dynamic> args =
              Map<String, dynamic>.from(call.arguments);
          final String busNo = args['busNo'] ?? '';
          final String routeId = args['routeId'] ?? '';
          final String stationName = args['stationName'] ?? '';

          logMessage(
              '🐛 [DEBUG] 네이티브에서 특정 알람 취소 이벤트 수신: $busNo, $stationName, $routeId',
              level: LogLevel.info);

          // 즉시 Flutter 측 상태 동기화 (낙관적 업데이트)
          final String alarmKey = "${busNo}_${stationName}_$routeId";
          final removedAlarm = _activeAlarms.remove(alarmKey);

          if (removedAlarm != null) {
            // 캐시 정리
            final cacheKey = "${busNo}_$routeId";
            _cachedBusInfo.remove(cacheKey);

            // 추적 상태 업데이트
            if (_trackedRouteId == routeId) {
              _trackedRouteId = null;
              if (_activeAlarms.isEmpty) {
                _isInTrackingMode = false;
              }
            } else if (_activeAlarms.isEmpty) {
              _isInTrackingMode = false;
              _trackedRouteId = null;
            }

            // 상태 저장 및 UI 업데이트
            await _saveAlarms();
            notifyListeners();

            logMessage('🐛 [DEBUG] ✅ 네이티브 이벤트에 따른 Flutter 알람 동기화 완료: $alarmKey',
                level: LogLevel.info);
          } else {
            logMessage(
                '🐛 [DEBUG] ⚠️ 해당 알람($alarmKey)이 Flutter에 없음 - 상태 정리만 수행',
                level: LogLevel.warning);

            // 상태 정리
            if (_activeAlarms.isEmpty && _isInTrackingMode) {
              _isInTrackingMode = false;
              _trackedRouteId = null;
              notifyListeners();
            }
          }

          return true; // Acknowledge event received
        case 'onAllAlarmsCanceled':
          // 모든 알람 취소 이벤트 처리
          logMessage('🚌 네이티브에서 모든 알람 취소 이벤트 수신', level: LogLevel.info);

          // 모든 활성 알람 제거
          if (_activeAlarms.isNotEmpty) {
            _activeAlarms.clear();
            _cachedBusInfo.clear();
            _isInTrackingMode = false;
            _trackedRouteId = null;
            await _saveAlarms();
            logMessage('✅ 모든 알람 취소 완료 (네이티브 이벤트에 의해)', level: LogLevel.info);
            notifyListeners();
          }

          return true;
        default:
          // Ensure other method calls are still handled if any exist
          logMessage('Unhandled method call: ${call.method}',
              level: LogLevel.warning);
          return null;
      }
    } catch (e) {
      logMessage('메서드 채널 핸들러 오류 (${call.method}): $e', level: LogLevel.error);
      return null;
    }
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
        _checkAutoAlarms(); // 자동 알람 체크 추가
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
        try {
          final rootIsolateToken = RootIsolateToken.instance;
          if (rootIsolateToken != null) {
            BackgroundIsolateBinaryMessenger.ensureInitialized(
                rootIsolateToken);
            logMessage('✅ BackgroundIsolateBinaryMessenger 초기화 성공');
          } else {
            logMessage('⚠️ RootIsolateToken이 null입니다. 메인 스레드에서 실행 중인지 확인하세요.',
                level: LogLevel.warning);
          }
        } catch (e) {
          logMessage('⚠️ BackgroundIsolateBinaryMessenger 초기화 오류 (무시): $e',
              level: LogLevel.warning);
        }
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
      // 백그라운드 메신저 상태 확인 및 초기화
      if (!kIsWeb) {
        try {
          final rootIsolateToken = RootIsolateToken.instance;
          if (rootIsolateToken != null) {
            BackgroundIsolateBinaryMessenger.ensureInitialized(
                rootIsolateToken);
            logMessage('✅ 자동 알람용 BackgroundIsolateBinaryMessenger 초기화 성공');
          } else {
            logMessage('⚠️ 자동 알람 - RootIsolateToken이 null입니다',
                level: LogLevel.warning);
          }
        } catch (e) {
          logMessage(
              '⚠️ 자동 알람 BackgroundIsolateBinaryMessenger 초기화 오류 (무시): $e',
              level: LogLevel.warning);
        }
      }

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
      'routeId',
      'stationName',
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
      logMessage('! 자동 알람 데이터 필수 필드 누락: [31m${missingFields.join(", ")}[0m',
          level: LogLevel.error);
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
      _trackedRouteId = effectiveRouteId;
      logMessage(
          '\ud83d\ude8c \ubc84\uc2a4 \ucd94\uc801 \uc2dc\uc791: $_trackedRouteId');
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
      _trackedRouteId = null;
      logMessage(
          '\ud83d\ude8c \ubc84\uc2a4 \ucd94\uc801 \uc911\uc9c0: \ucd94\uc801 \uc544\uc774\ub514 \ucd08\uae30\ud654');
      notifyListeners();

      // 6. TTS로 알림 중지 알림
      try {
        // 이어폰 연결 시에만 TTS 발화
        await SimpleTTSHelper.speak(
          "버스 추적이 중지되었습니다.",
          earphoneOnly: true,
        );
      } catch (e) {
        debugPrint('🚌 TTS 알림 오류: $e');
      }

      debugPrint('🚌 모니터링 서비스 중지 완료, 추적 모드: $_isInTrackingMode');
      return stopSuccess || !_isInTrackingMode;
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

  // 자동 알람 체크 메서드 수정 (Concurrent modification 오류 해결)
  Future<void> _checkAutoAlarms() async {
    try {
      // 자동 알람 설정이 비활성화되어 있으면 실행하지 않음
      final settingsService = SettingsService();
      if (!settingsService.useAutoAlarm) {
        logMessage('⚠️ 자동 알람이 설정에서 비활성화되어 있습니다.', level: LogLevel.warning);
        return;
      }

      final now = DateTime.now();

      // 리스트를 복사해서 순회하여 Concurrent modification 방지
      final alarmsCopy = List<alarm_model.AlarmData>.from(_autoAlarms);

      for (var alarm in alarmsCopy) {
        // 알람 시간이 지났거나 지난 자동 알람 확인 (음수값만)
        final timeUntilAlarm = alarm.scheduledTime.difference(now);

        if (timeUntilAlarm.inMinutes <= 0 && timeUntilAlarm.inMinutes >= -5) {
          logMessage(
              '⚡ 자동 알람 시간 임박: ${alarm.busNo}번, ${timeUntilAlarm.inMinutes}분 남음',
              level: LogLevel.info);

          // 올바른 stationId 가져오기
          String effectiveStationId = alarm.routeId;
          try {
            final dbHelper = DatabaseHelper();
            final resolvedStationId =
                await dbHelper.getStationIdFromWincId(alarm.stationName);
            if (resolvedStationId != null && resolvedStationId.isNotEmpty) {
              effectiveStationId = resolvedStationId;
              logMessage(
                  '✅ 자동 알람 stationId 보정: ${alarm.stationName} → $effectiveStationId',
                  level: LogLevel.debug);
            } else {
              logMessage('⚠️ stationId 보정 실패, 기본값 사용: ${alarm.stationName}',
                  level: LogLevel.warning);
            }
          } catch (e) {
            logMessage('❌ stationId 보정 중 오류: $e', level: LogLevel.error);
          }

          // AutoAlarm 객체로 변환
          final autoAlarm = AutoAlarm(
            id: alarm.getAlarmId().toString(),
            routeNo: alarm.busNo,
            stationName: alarm.stationName,
            stationId: effectiveStationId, // 올바른 stationId 사용
            routeId: alarm.routeId,
            hour: alarm.scheduledTime.hour,
            minute: alarm.scheduledTime.minute,
            repeatDays: [now.weekday], // 오늘 요일
            useTTS: alarm.useTTS,
            isActive: true,
          );

          // 즉시 실행하고 지속적인 모니터링 시작
          await _startContinuousAutoAlarm(autoAlarm);

          // 알람 목록에서 제거 (이미 실행됨)
          _autoAlarms.removeWhere((a) => a.getAlarmId() == alarm.getAlarmId());
          await _saveAutoAlarms();

          logMessage('✅ 자동 알람 실행 완료: ${alarm.busNo}번', level: LogLevel.info);
        }
      }
    } catch (e) {
      logMessage('❌ 자동 알람 체크 오류: $e', level: LogLevel.error);
    }
  }

  // 지속적인 자동 알람 시작 메서드 추가
  Future<void> _startContinuousAutoAlarm(AutoAlarm alarm) async {
    try {
      logMessage('⚡ 지속적인 자동 알람 시작: ${alarm.routeNo}번, ${alarm.stationName}',
          level: LogLevel.info);

      // 버스 모니터링 서비스 시작
      await startBusMonitoringService(
        routeId: alarm.routeId,
        stationId: alarm.stationId,
        busNo: alarm.routeNo,
        stationName: alarm.stationName,
      );

      // 정기적인 업데이트 타이머 시작 (30초마다)
      _refreshTimer?.cancel();
      _refreshTimer =
          Timer.periodic(const Duration(seconds: 30), (timer) async {
        if (!_isInTrackingMode) {
          timer.cancel();
          return;
        }

        try {
          // 실시간 버스 정보 업데이트
          await refreshAutoAlarmBusInfo(alarm);

          // 캐시된 정보 가져오기
          final cacheKey = "${alarm.routeNo}_${alarm.routeId}";
          final cachedInfo = _cachedBusInfo[cacheKey];

          final remainingMinutes = cachedInfo?.remainingMinutes ?? 0;
          final currentStation = cachedInfo?.currentStation ?? '정보 업데이트 중';

          // 알림 업데이트
          final alarmId = getAlarmId(alarm.routeNo, alarm.stationName,
              routeId: alarm.routeId);
          await _notificationService.showNotification(
            id: alarmId,
            busNo: alarm.routeNo,
            stationName: alarm.stationName,
            remainingMinutes: remainingMinutes,
            currentStation: currentStation,
            routeId: alarm.routeId,
            isAutoAlarm: true,
            isOngoing: true, // 지속적인 알림
          );

          logMessage(
              '🔄 자동 알람 업데이트: ${alarm.routeNo}번, $remainingMinutes분 후, 현재: $currentStation',
              level: LogLevel.info);

          // TTS 발화 (1분마다)
          if (timer.tick % 2 == 0) {
            // 1분마다 (30초 * 2)
            if (alarm.useTTS) {
              try {
                await SimpleTTSHelper.speakBusAlert(
                  busNo: alarm.routeNo,
                  stationName: alarm.stationName,
                  remainingMinutes: remainingMinutes,
                  currentStation: currentStation,
                  isAutoAlarm: true,
                );

                logMessage(
                    '🔊 자동 알람 TTS 반복 발화: ${alarm.routeNo}번, $remainingMinutes분 후',
                    level: LogLevel.info);
              } catch (e) {
                logMessage('❌ 자동 알람 TTS 반복 발화 오류: $e', level: LogLevel.error);
              }
            }
          }

          // 버스가 도착했거나 사라진 경우 알람 종료
          if (remainingMinutes <= 0) {
            logMessage('✅ 버스 도착으로 인한 자동 알람 종료: ${alarm.routeNo}번',
                level: LogLevel.info);

            // 마지막 TTS 발화
            if (alarm.useTTS) {
              await SimpleTTSHelper.speakBusAlert(
                busNo: alarm.routeNo,
                stationName: alarm.stationName,
                remainingMinutes: 0,
                currentStation: currentStation,
                isAutoAlarm: true,
              );
            }

            timer.cancel();
            await stopBusMonitoringService();
            await _notificationService.cancelOngoingTracking();
          }
        } catch (e) {
          logMessage('❌ 자동 알람 업데이트 오류: $e', level: LogLevel.error);
        }
      });

      // 초기 실행
      await _executeAutoAlarmImmediately(alarm);

      logMessage('✅ 지속적인 자동 알람 시작 완료: ${alarm.routeNo}번', level: LogLevel.info);
    } catch (e) {
      logMessage('❌ 지속적인 자동 알람 시작 오류: $e', level: LogLevel.error);
    }
  }

  Future<List<DateTime>> getHolidays(int year, int month) async {
    return _fetchHolidays(year, month);
  }

  Future<void> _scheduleAutoAlarm(
      AutoAlarm alarm, DateTime scheduledTime) async {
    // 필수 파라미터 검증
    if (!_validateRequiredFields(alarm.toJson())) {
      logMessage('❌ 필수 파라미터 누락으로 자동 알람 예약 거부: ${alarm.toJson()}',
          level: LogLevel.error);
      return;
    }
    try {
      final now = DateTime.now();
      final id =
          "${alarm.routeNo}_${alarm.stationName}_${alarm.routeId}".hashCode;
      final initialDelay = scheduledTime.difference(now);

      // 너무 먼 미래의 알람은 최대 3일로 제한
      final actualDelay =
          initialDelay.inDays > 3 ? const Duration(days: 3) : initialDelay;

      // 음수 딜레이는 즉시 실행
      final executionDelay =
          actualDelay.isNegative ? Duration.zero : actualDelay;

      // 기존 작업 취소 확인
      try {
        await Workmanager().cancelByUniqueName('autoAlarm_$id');
        logMessage('기존 자동 알람 작업 취소 완료, ID: $id');
      } catch (e) {
        logMessage('기존 작업 취소 오류 (무시): $e', level: LogLevel.warning);
      }

      // 백업 ID 사용 - 충돌 방지
      final uniqueId = 'autoAlarm_${id}_${now.millisecondsSinceEpoch}';

      // 예약 시간에 정확히 실행되도록 수정 (즉시 실행 제거)
      // 음수 딜레이는 즉시 실행하지만, 양수 딜레이는 모두 예약 실행
      if (executionDelay.isNegative || executionDelay.inSeconds <= 30) {
        logMessage(
            '⚡ 즉시 실행 자동 알람: ${alarm.routeNo}번, 딜레이: ${executionDelay.inSeconds}초 (이미 지났거나 30초 이내)',
            level: LogLevel.info);

        // 즉시 알람 실행
        await _executeAutoAlarmImmediately(alarm);

        // 그래도 WorkManager 작업도 등록 (백업용)
        await Workmanager().registerOneOffTask(
          uniqueId,
          'autoAlarmTask',
          initialDelay:
              executionDelay.isNegative ? Duration.zero : executionDelay,
          inputData: {
            'alarmId': id,
            'busNo': alarm.routeNo,
            'stationName': alarm.stationName,
            'remainingMinutes': 0,
            'routeId': alarm.routeId,
            'useTTS': alarm.useTTS,
            'stationId': alarm.stationId,
            'registeredAt': now.millisecondsSinceEpoch,
            'scheduledFor': scheduledTime.millisecondsSinceEpoch,
            'isImmediate': true,
          },
          constraints: Constraints(
            networkType: NetworkType.connected,
            requiresBatteryNotLow: false,
            requiresCharging: false,
            requiresDeviceIdle: false,
            requiresStorageNotLow: false,
          ),
          backoffPolicy: BackoffPolicy.linear,
          existingWorkPolicy: ExistingWorkPolicy.replace,
        );

        logMessage('✅ 자동 알람 즉시 실행 및 백업 작업 등록 완료: ${alarm.routeNo}번',
            level: LogLevel.info);
      } else {
        // 일반적인 지연 실행
        await Workmanager().registerOneOffTask(
          uniqueId,
          'autoAlarmTask',
          initialDelay: executionDelay,
          inputData: {
            'alarmId': id,
            'busNo': alarm.routeNo,
            'stationName': alarm.stationName,
            'remainingMinutes': 0,
            'routeId': alarm.routeId,
            'useTTS': alarm.useTTS,
            'stationId': alarm.stationId,
            'registeredAt': now.millisecondsSinceEpoch,
            'scheduledFor': scheduledTime.millisecondsSinceEpoch,
          },
          constraints: Constraints(
            networkType: NetworkType.connected,
            requiresBatteryNotLow: false,
            requiresCharging: false,
            requiresDeviceIdle: false,
            requiresStorageNotLow: false,
          ),
          backoffPolicy: BackoffPolicy.linear,
          existingWorkPolicy: ExistingWorkPolicy.replace,
        );
      }

      // SharedPreferences에 작업 등록 정보 저장 (검증용)
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'last_scheduled_alarm_$id',
          jsonEncode({
            'workId': uniqueId,
            'busNo': alarm.routeNo,
            'stationName': alarm.stationName,
            'scheduledTime': scheduledTime.toIso8601String(),
            'registeredAt': now.toIso8601String(),
          }));

      logMessage(
          '✅ 자동 알람 예약 성공: ${alarm.routeNo} at $scheduledTime (${executionDelay.inMinutes}분 후), 작업 ID: $uniqueId');

      // 2분 후 백업 알람 등록 (즉시 실행되지 않은 경우만)
      if (executionDelay.inMinutes > 2) {
        _scheduleBackupAlarm(alarm, id, scheduledTime);
        logMessage(
            '✅ 백업 알람 등록: ${alarm.routeNo}번, ${executionDelay.inMinutes}분 후 실행',
            level: LogLevel.info);
      }
    } catch (e) {
      logMessage('❌ 자동 알람 예약 오류: $e', level: LogLevel.error);
      // 오류 발생 시 앱 내 로컬 알림으로 예약 시도
      _scheduleLocalBackupAlarm(alarm, scheduledTime);
    }
  }

  // 즉시 실행 자동 알람 메서드 추가
  Future<void> _executeAutoAlarmImmediately(AutoAlarm alarm) async {
    try {
      // 자동 알람 설정이 비활성화되어 있으면 실행하지 않음
      final settingsService = SettingsService();
      if (!settingsService.useAutoAlarm) {
        logMessage('⚠️ 자동 알람이 설정에서 비활성화되어 있어 실행하지 않습니다: ${alarm.routeNo}번',
            level: LogLevel.warning);
        return;
      }

      logMessage('⚡ 즉시 자동 알람 실행: ${alarm.routeNo}번, ${alarm.stationName}',
          level: LogLevel.info);

      // 실시간 버스 정보 가져오기
      await refreshAutoAlarmBusInfo(alarm);

      // 캐시된 정보 가져오기
      final cacheKey = "${alarm.routeNo}_${alarm.routeId}";
      final cachedInfo = _cachedBusInfo[cacheKey];

      final remainingMinutes = cachedInfo?.remainingMinutes ?? 0;
      final currentStation = cachedInfo?.currentStation ?? '정보 업데이트 중';

      // 알림 표시
      final alarmId =
          getAlarmId(alarm.routeNo, alarm.stationName, routeId: alarm.routeId);
      await _notificationService.showNotification(
        id: alarmId,
        busNo: alarm.routeNo,
        stationName: alarm.stationName,
        remainingMinutes: remainingMinutes,
        currentStation: currentStation,
        routeId: alarm.routeId,
        isAutoAlarm: true,
        isOngoing: false, // 일회성 알림
      );

      // 자동 알람 실행 시 activeAlarms에도 추가하여 UI에 표시
      final alarmData = alarm_model.AlarmData(
        busNo: alarm.routeNo,
        stationName: alarm.stationName,
        remainingMinutes: remainingMinutes,
        routeId: alarm.routeId,
        scheduledTime: DateTime.now()
            .add(Duration(minutes: remainingMinutes.clamp(0, 60))),
        currentStation: currentStation,
        useTTS: alarm.useTTS,
      );

      // activeAlarms에 추가하여 ActiveAlarmPanel에서 표시되도록 함
      final alarmKey = "${alarm.routeNo}_${alarm.stationName}_${alarm.routeId}";
      _activeAlarms[alarmKey] = alarmData;
      await _saveAlarms();

      logMessage(
          '✅ 자동 알람을 activeAlarms에 추가: ${alarm.routeNo}번 ($remainingMinutes분 후)',
          level: LogLevel.info);

      // TTS는 WorkManager(AutoAlarmWorker)에서 처리하므로 여기서는 제거
      // 중복 TTS 방지

      logMessage('✅ 즉시 자동 알람 실행 완료: ${alarm.routeNo}번', level: LogLevel.info);

      // UI 업데이트
      notifyListeners();
    } catch (e) {
      logMessage('❌ 즉시 자동 알람 실행 오류: $e', level: LogLevel.error);
    }
  }

  // 로컬 백업 알람 등록 함수
  Future<void> _scheduleLocalBackupAlarm(
      AutoAlarm alarm, DateTime scheduledTime) async {
    try {
      logMessage('⏰ 로컬 백업 알람 등록 시도: ${alarm.routeNo}, ${alarm.stationName}',
          level: LogLevel.debug);

      // TTS 및 알림으로 사용자에게 정보 제공
      try {
        await SimpleTTSHelper.speak(
            "${alarm.routeNo}번 버스 자동 알람 예약에 문제가 발생했습니다. 앱을 다시 실행해 주세요.");
      } catch (e) {
        logMessage('🔊 TTS 알림 실패: $e', level: LogLevel.error);
      }

      // 메인 앱이 실행될 때 처리할 수 있도록 정보 저장
      final prefs = await SharedPreferences.getInstance();
      final alarmInfo = {
        'routeNo': alarm.routeNo,
        'stationName': alarm.stationName,
        'scheduledTime': scheduledTime.toIso8601String(),
        'registeredAt': DateTime.now().toIso8601String(),
        'hasSchedulingError': true,
      };

      await prefs.setString('alarm_scheduling_error', jsonEncode(alarmInfo));
      await prefs.setBool('has_alarm_scheduling_error', true);

      logMessage('⏰ 로컬 백업 알람 정보 저장 완료', level: LogLevel.debug);
    } catch (e) {
      logMessage('❌ 로컬 백업 알람 등록 실패: $e', level: LogLevel.error);
    }
  }

  // 백업 알람 등록 함수 추가
  Future<void> _scheduleBackupAlarm(
      AutoAlarm alarm, int id, DateTime scheduledTime) async {
    try {
      final backupTime = scheduledTime.subtract(const Duration(minutes: 5));
      final now = DateTime.now();
      if (backupTime.isBefore(now)) return; // 이미 지난 시간이면 등록 취소

      final backupId = 'autoAlarm_backup_${id}_${now.millisecondsSinceEpoch}';
      final backupDelay = backupTime.difference(now);

      await Workmanager().registerOneOffTask(
        backupId,
        'autoAlarmTask',
        initialDelay: backupDelay,
        inputData: {
          'alarmId': id,
          'busNo': alarm.routeNo,
          'stationName': alarm.stationName,
          'remainingMinutes': 0,
          'routeId': alarm.routeId,
          'useTTS': alarm.useTTS,
          'stationId': alarm.stationId,
          'isBackup': true,
        },
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: false,
          requiresCharging: false,
          requiresDeviceIdle: false,
          requiresStorageNotLow: false,
        ),
        existingWorkPolicy: ExistingWorkPolicy.replace,
      );

      logMessage(
          '✅ 백업 자동 알람 예약 성공: ${alarm.routeNo} at $backupTime (${backupDelay.inMinutes}분 후)');
    } catch (e) {
      logMessage('❌ 백업 알람 예약 오류: $e', level: LogLevel.error);
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
      // 백그라운드 메신저 상태 확인 및 초기화
      if (!kIsWeb) {
        try {
          final rootIsolateToken = RootIsolateToken.instance;
          if (rootIsolateToken != null) {
            BackgroundIsolateBinaryMessenger.ensureInitialized(
                rootIsolateToken);
            logMessage(
                '✅ updateAutoAlarms - BackgroundIsolateBinaryMessenger 초기화 성공');
          } else {
            logMessage('⚠️ updateAutoAlarms - RootIsolateToken이 null입니다',
                level: LogLevel.warning);
          }
        } catch (e) {
          logMessage(
              '⚠️ updateAutoAlarms - BackgroundIsolateBinaryMessenger 초기화 오류 (무시): $e',
              level: LogLevel.warning);
        }
      }

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

        // 알람 시간이 이미 지났거나 지난 경우만 즉시 실행 (음수 또는 0분)
        if (timeUntilAlarm.inMinutes <= 0) {
          logMessage('  ⚡ 알람 시간이 지났음 - 즉시 실행 (${timeUntilAlarm.inMinutes}분)');
          await _executeAutoAlarmImmediately(alarm);
        } else if (timeUntilAlarm.inMinutes <= 10) {
          logMessage(
              '  ⏰ 10분 이내 알람 - 예약만 등록, 정확한 시간에 실행됨 (${timeUntilAlarm.inMinutes}분 남음)');
          // 예약만 하고 즉시 실행하지 않음 - 정확한 시간에 WorkManager가 실행
        } else {
          logMessage('  ⏰ 알람 예약: ${timeUntilAlarm.inMinutes}분 후 실행');
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

  /// 알람 시작
  Future<void> startAlarm(
      String busNo, String stationName, int remainingMinutes,
      {bool isAutoAlarm = false}) async {
    try {
      // TTS 발화
      if (_useTTS) {
        await SimpleTTSHelper.speakBusAlert(
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          earphoneOnly: !isAutoAlarm, // 일반 알람은 이어폰 전용, 자동 알람은 설정된 모드 사용
        );
      }

      // 알람 해제 시에도 설정된 모드 유지
      await _notificationService.showBusArrivingSoon(
        busNo: busNo,
        stationName: stationName,
      );
    } catch (e) {
      logMessage('❌ 알람 시작 오류: $e', level: LogLevel.error);
    }
  }

  /// 자동 알람 중지 메서드 추가
  Future<bool> stopAutoAlarm(
      String busNo, String stationName, String routeId) async {
    try {
      logMessage('📋 자동 알람 중지 요청: $busNo번, $stationName', level: LogLevel.info);

      // 새로고침 타이머 중지
      _refreshTimer?.cancel();
      _refreshTimer = null;

      // 버스 모니터링 서비스 중지
      await stopBusMonitoringService();

      // 알림 취소
      await _notificationService.cancelOngoingTracking();

      // 자동 알람 목록에서 제거
      _autoAlarms.removeWhere((alarm) =>
          alarm.busNo == busNo &&
          alarm.stationName == stationName &&
          alarm.routeId == routeId);
      await _saveAutoAlarms();

      // TTS 중지 알림
      try {
        await SimpleTTSHelper.speak(
          "$busNo번 버스 자동 알람이 중지되었습니다.",
          force: true,
          earphoneOnly: false,
        );
      } catch (e) {
        logMessage('❌ TTS 중지 알림 오류: $e', level: LogLevel.error);
      }

      logMessage('✅ 자동 알람 중지 완료: $busNo번', level: LogLevel.info);

      notifyListeners();
      return true;
    } catch (e) {
      logMessage('❌ 자동 알람 중지 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  /// 알람 해제
  Future<void> stopAlarm(String busNo, String stationName,
      {bool isAutoAlarm = false}) async {
    try {
      // TTS로 알람 해제 안내
      if (_useTTS) {
        await SimpleTTSHelper.speak(
          "$busNo번 버스 알람이 해제되었습니다.",
          earphoneOnly: !isAutoAlarm, // 일반 알람은 이어폰 전용, 자동 알람은 설정된 모드 사용
        );
      }

      // 알림 제거
      await _notificationService.cancelOngoingTracking();
    } catch (e) {
      logMessage('❌ 알람 해제 오류: $e', level: LogLevel.error);
    }
  }

  int getAlarmId(String busNo, String stationName, {String routeId = ''}) {
    return ("${busNo}_${stationName}_$routeId").hashCode;
  }

  bool hasAlarm(String busNo, String stationName, String routeId) {
    // 일반 승차 알람만 확인 (자동 알람 제외)
    final bool hasRegularAlarm = _activeAlarms.values.any((alarm) =>
        alarm.busNo == busNo &&
        alarm.stationName == stationName &&
        alarm.routeId == routeId);

    // 자동 알람 여부 확인
    final bool hasAutoAlarm = _autoAlarms.any((alarm) =>
        alarm.busNo == busNo &&
        alarm.stationName == stationName &&
        alarm.routeId == routeId);

    // 추적 중인지 여부 확인
    final bool isTracking = isInTrackingMode;
    bool isThisBusTracked = false;
    if (isTracking && _trackedRouteId != null) {
      // 현재 추적 중인 버스와 동일한지 확인
      isThisBusTracked = _trackedRouteId == routeId;
    }

    // 자동 알람이 있으면 승차 알람은 비활성화
    return hasRegularAlarm &&
        !hasAutoAlarm &&
        (!isTracking || isThisBusTracked);
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

      // 알림 표시 (일반 알람 전용)
      try {
        await _notificationService.showNotification(
          id: alarmId,
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          currentStation: currentStation ?? '정보 없음',
          routeId: routeId,
          isAutoAlarm: false, // 일반 알람
          isOngoing: true, // 지속적인 알림
        );
        logMessage('✅ 일반 알람 알림 표시 완료: $busNo번', level: LogLevel.info);
      } catch (e) {
        logMessage('❌ 일반 알람 알림 표시 오류: $e', level: LogLevel.error);
      }

      // TTS 알림 시작 (설정된 경우 - 일반 알람 -> 이어폰 전용)
      if (useTTS) {
        try {
          await SimpleTTSHelper.initialize();
          await SimpleTTSHelper.setVolume(volume); // 볼륨 설정

          // 이어폰 전용 모드로 TTS 발화
          await SimpleTTSHelper.speak(
            "$busNo번 버스가 $remainingMinutes분 후 도착 예정입니다.",
            earphoneOnly: true, // 이어폰 전용 모드 명시
          );

          logMessage('🔊 일반 알람 TTS 발화 완료 (이어폰 전용 모드, 볼륨: ${volume * 100}%)');
        } catch (e) {
          logMessage('🔊 일반 알람 TTS 발화 오료: $e', level: LogLevel.error);
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

  // 특정 추적 중지 메서드 추가
  Future<bool> stopSpecificTracking({
    required String busNo,
    required String stationName,
    required String routeId,
  }) async {
    try {
      logMessage('🐛 [DEBUG] 특정 추적 중지 요청: $busNo번 버스, $stationName, $routeId');

      // 1. 네이티브 서비스에 특정 추적 중지 요청
      await _methodChannel?.invokeMethod('stopSpecificTracking', {
        'busNo': busNo,
        'routeId': routeId,
        'stationName': stationName,
      });

      // 2. Flutter 측 상태 업데이트
      await cancelAlarmByRoute(busNo, stationName, routeId);

      logMessage('🐛 [DEBUG] ✅ 특정 추적 중지 완료: $busNo번 버스');
      return true;
    } catch (e) {
      logMessage('❌ [ERROR] 특정 추적 중지 실패: $e', level: LogLevel.error);
      return false;
    }
  }

  // 모든 추적 중지 메서드 개선
  Future<bool> stopAllTracking() async {
    try {
      logMessage('🐛 [DEBUG] 모든 추적 중지 요청: ${_activeAlarms.length}개');

      // 1. 네이티브 서비스 완전 중지
      await _methodChannel?.invokeMethod('stopBusTrackingService');

      // 2. TTS 추적 중지
      await _methodChannel?.invokeMethod('stopTtsTracking');

      // 3. 모든 알림 취소
      await _notificationService.cancelAllNotifications();

      // 4. Flutter 측 상태 완전 정리
      _activeAlarms.clear();
      _cachedBusInfo.clear();
      _isInTrackingMode = false;
      _trackedRouteId = null;
      _processedNotifications.clear();

      // 5. 타이머 정리
      _refreshTimer?.cancel();
      _refreshTimer = null;

      // 6. 상태 저장 및 UI 업데이트
      await _saveAlarms();
      notifyListeners();

      logMessage('🐛 [DEBUG] ✅ 모든 추적 중지 완료');
      return true;
    } catch (e) {
      logMessage('❌ [ERROR] 모든 추적 중지 실패: $e', level: LogLevel.error);
      return false;
    }
  }

  /// 알람 취소 메서드
  Future<bool> cancelAlarmByRoute(
    String busNo,
    String stationName,
    String routeId,
  ) async {
    logMessage(
        '🚌 [Request] 알람 취소 요청: $busNo번 버스, $stationName, routeId: $routeId');

    final String alarmKey = "${busNo}_${stationName}_$routeId";
    final String cacheKey = "${busNo}_$routeId";
    bool shouldForceStopNative = false;

    try {
      // --- Perform Flutter state update immediately ---
      final removedAlarm = _activeAlarms.remove(alarmKey);
      if (removedAlarm != null) {
        logMessage('[$alarmKey] Flutter activeAlarms 목록에서 즉시 제거',
            level: LogLevel.debug);
      } else {
        logMessage('⚠️ 취소 요청한 알람($alarmKey)이 Flutter 활성 알람 목록에 없음 (취소 전).',
            level: LogLevel.warning);
      }

      _cachedBusInfo.remove(cacheKey);
      logMessage('[$cacheKey] 버스 정보 캐시 즉시 제거', level: LogLevel.debug);

      // Check if the route being cancelled is the one being tracked OR if it's the last alarm
      if (_trackedRouteId == routeId) {
        _trackedRouteId = null;
        logMessage('추적 Route ID 즉시 초기화됨 (취소된 알람과 일치)', level: LogLevel.debug);
        if (_activeAlarms.isEmpty) {
          _isInTrackingMode = false;
          shouldForceStopNative = true; // Last tracked alarm removed
          logMessage('추적 모드 즉시 비활성화 (활성 알람 없음)', level: LogLevel.debug);
        } else {
          _isInTrackingMode = true;
          logMessage('다른 활성 알람 존재, 추적 모드 유지', level: LogLevel.debug);
          // Decide if we need to start tracking the next alarm? For now, no.
        }
      } else if (_activeAlarms.isEmpty) {
        // If the cancelled alarm wasn't the tracked one, but it was the *last* one
        _isInTrackingMode = false;
        _trackedRouteId = null;
        shouldForceStopNative = true; // Last alarm overall removed
        logMessage('마지막 활성 알람 취소됨, 추적 모드 비활성화', level: LogLevel.debug);
      }

      await _saveAlarms(); // Persist the removal immediately
      notifyListeners(); // Update UI immediately
      logMessage('[$alarmKey] Flutter 상태 즉시 업데이트 및 리스너 알림 완료',
          level: LogLevel.debug);
      // --- End immediate Flutter state update ---

      // --- Send request to Native ---
      try {
        if (shouldForceStopNative) {
          logMessage('마지막 알람 취소됨, 네이티브 강제 전체 중지 요청', level: LogLevel.debug);
          await _methodChannel?.invokeMethod('forceStopTracking');
          logMessage('✅ 네이티브 강제 전체 중지 요청 전송 완료', level: LogLevel.debug);
        } else {
          // If not the last alarm, just cancel the specific notification/route tracking
          logMessage('다른 알람 존재, 네이티브 특정 알람($routeId) 취소 요청',
              level: LogLevel.debug);
          await _methodChannel?.invokeMethod('cancelAlarmNotification',
              {'routeId': routeId, 'busNo': busNo, 'stationName': stationName});
          logMessage('✅ 네이티브 특정 알람 취소 요청 전송 완료', level: LogLevel.debug);
        }
      } catch (nativeError) {
        logMessage('❌ 네이티브 요청 전송 오류: $nativeError', level: LogLevel.error);
        return false; // Indicate that the native part failed
      }
      // --- End Native request ---

      return true; // Return true as the action was initiated and Flutter state updated.
    } catch (e) {
      logMessage('❌ 알람 취소 처리 중 오류 (Flutter 업데이트): $e', level: LogLevel.error);
      notifyListeners();
      return false;
    }
  }

  Future<bool> refreshAutoAlarmBusInfo(AutoAlarm alarm) async {
    try {
      if (!alarm.isActive) {
        logMessage('비활성화된 알람은 정보를 업데이트하지 않습니다', level: LogLevel.debug);
        return false;
      }

      logMessage(
          '🔄 자동 알람 버스 정보 업데이트 시작: [36m${alarm.routeNo}번, ${alarm.stationName}[0m',
          level: LogLevel.debug);

      // ✅ stationId 보정 로직 개선
      String effectiveStationId = alarm.stationId;
      if (effectiveStationId.isEmpty ||
          effectiveStationId.length < 10 ||
          !effectiveStationId.startsWith('7')) {
        try {
          final dbHelper = DatabaseHelper();
          final resolvedStationId =
              await dbHelper.getStationIdFromWincId(alarm.stationName);
          if (resolvedStationId != null && resolvedStationId.isNotEmpty) {
            effectiveStationId = resolvedStationId;
            logMessage(
                '✅ 자동 알람 stationId 보정: ${alarm.stationName} → $effectiveStationId',
                level: LogLevel.debug);
          } else {
            logMessage('⚠️ stationId 보정 실패: ${alarm.stationName}',
                level: LogLevel.warning);
            return false;
          }
        } catch (e) {
          logMessage('❌ stationId 보정 중 오류: $e', level: LogLevel.error);
          return false;
        }
      }

      // ✅ API 호출을 통한 버스 실시간 정보 가져오기
      try {
        const methodChannel =
            MethodChannel('com.example.daegu_bus_app/bus_api');
        final result =
            await methodChannel.invokeMethod('getBusArrivalByRouteId', {
          'stationId': effectiveStationId,
          'routeId': alarm.routeId,
        });

        logMessage('🚌 [API 응답] 자동 알람 응답 수신: ${result?.runtimeType}',
            level: LogLevel.debug);

        if (result != null) {
          try {
            // ✅ 응답 파싱 로직 개선
            dynamic parsedData;
            List<dynamic> arrivals = [];

            // 응답 타입별 처리
            if (result is String) {
              logMessage('🚌 [API 파싱] String 형식 응답 처리', level: LogLevel.debug);
              try {
                parsedData = jsonDecode(result);
              } catch (e) {
                logMessage('❌ JSON 파싱 오류: $e', level: LogLevel.error);
                return false;
              }
            } else if (result is List) {
              logMessage('🚌 [API 파싱] List 형식 응답 처리', level: LogLevel.debug);
              parsedData = result;
            } else if (result is Map) {
              logMessage('🚌 [API 파싱] Map 형식 응답 처리', level: LogLevel.debug);
              parsedData = result;
            } else {
              logMessage('❌ 지원되지 않는 응답 타입: ${result.runtimeType}',
                  level: LogLevel.error);
              return false;
            }

            // ✅ parsedData 구조 분석 및 arrivals 추출
            if (parsedData is List) {
              arrivals = parsedData;
            } else if (parsedData is Map) {
              // 자동 알람 응답 형식: { "routeNo": "623", "arrList": [...] }
              if (parsedData.containsKey('arrList')) {
                arrivals = parsedData['arrList'] as List? ?? [];
                logMessage(
                    '🚌 [API 파싱] arrList에서 도착 정보 추출: ${arrivals.length}개',
                    level: LogLevel.debug);
              } else if (parsedData.containsKey('bus')) {
                arrivals = parsedData['bus'] as List? ?? [];
                logMessage('🚌 [API 파싱] bus에서 도착 정보 추출: ${arrivals.length}개',
                    level: LogLevel.debug);
              } else {
                logMessage('❌ 예상치 못한 Map 구조: ${parsedData.keys}',
                    level: LogLevel.error);
                return false;
              }
            }

            logMessage('🚌 [API 파싱] 파싱된 arrivals: ${arrivals.length}개 항목',
                level: LogLevel.debug);

            if (arrivals.isNotEmpty) {
              // ✅ 버스 정보 추출 및 필터링
              dynamic busInfo;
              bool found = false;

              // 알람에 설정된 노선 번호와 일치하는 버스 찾기
              for (var bus in arrivals) {
                if (bus is Map) {
                  final busRouteNo = bus['routeNo']?.toString() ?? '';
                  final busRouteId = bus['routeId']?.toString() ?? '';
                  // routeNo 또는 routeId로 매칭
                  if (busRouteNo == alarm.routeNo ||
                      busRouteId == alarm.routeId) {
                    busInfo = bus;
                    found = true;
                    logMessage(
                        '✅ 일치하는 노선 찾음: ${alarm.routeNo} (routeNo: $busRouteNo, routeId: $busRouteId)',
                        level: LogLevel.debug);
                    break;
                  }
                }
              }

              // 일치하는 노선이 없으면 첫 번째 항목 사용
              if (!found && arrivals.isNotEmpty) {
                busInfo = arrivals.first;
                final routeNo = busInfo['routeNo']?.toString() ?? '정보 없음';
                logMessage('⚠️ 일치하는 노선 없음, 첫 번째 항목 사용: $routeNo',
                    level: LogLevel.warning);
              }

              if (busInfo != null) {
                // ✅ 도착 정보 추출 - 다양한 필드명 지원
                final estimatedTime = busInfo['arrState'] ??
                    busInfo['estimatedTime'] ??
                    busInfo['도착예정소요시간'] ??
                    "정보 없음";

                final currentStation = busInfo['bsNm'] ??
                    busInfo['currentStation'] ??
                    busInfo['현재정류소'] ??
                    '정보 없음';

                final int remainingMinutes =
                    _parseRemainingMinutes(estimatedTime);

                logMessage(
                    '🚌 [정보 추출] estimatedTime: $estimatedTime, currentStation: $currentStation, remainingMinutes: $remainingMinutes',
                    level: LogLevel.debug);

                // ✅ 캐시에 저장
                final cachedInfo = CachedBusInfo(
                  remainingMinutes: remainingMinutes,
                  currentStation: currentStation,
                  stationName: alarm.stationName,
                  busNo: alarm.routeNo,
                  routeId: alarm.routeId,
                  lastUpdated: DateTime.now(),
                );

                final key = "${alarm.routeNo}_${alarm.routeId}";
                _cachedBusInfo[key] = cachedInfo;

                logMessage(
                    '✅ 자동 알람 버스 정보 업데이트 완료: ${alarm.routeNo}번, $remainingMinutes분 후 도착, 위치: $currentStation',
                    level: LogLevel.info);

                // ✅ 알림 업데이트
                final alarmId = getAlarmId(alarm.routeNo, alarm.stationName,
                    routeId: alarm.routeId);

                try {
                  await _notificationService.showNotification(
                    id: alarmId,
                    busNo: alarm.routeNo,
                    stationName: alarm.stationName,
                    remainingMinutes: remainingMinutes,
                    currentStation: currentStation,
                    routeId: alarm.routeId,
                    isAutoAlarm: true,
                    isOngoing: true,
                  );
                  logMessage(
                      '✅ 자동 알람 알림 업데이트: ${alarm.routeNo}번, $remainingMinutes분 후, $currentStation',
                      level: LogLevel.debug);
                } catch (e) {
                  logMessage('❌ 자동 알람 알림 업데이트 오류: $e', level: LogLevel.error);
                }

                // ✅ 버스 모니터링 서비스 시작 (10분 이내일 때)
                if (remainingMinutes <= 10 && remainingMinutes >= 0) {
                  try {
                    await startBusMonitoringService(
                      routeId: alarm.routeId,
                      stationId: effectiveStationId,
                      busNo: alarm.routeNo,
                      stationName: alarm.stationName,
                    );
                    logMessage(
                        '✅ 자동 알람 버스 모니터링 시작: ${alarm.routeNo}번 ($remainingMinutes분 후 도착)',
                        level: LogLevel.info);
                  } catch (e) {
                    logMessage('❌ 자동 알람 버스 모니터링 시작 실패: $e',
                        level: LogLevel.error);
                  }
                }

                // UI 업데이트
                notifyListeners();
                return true;
              }
            } else {
              logMessage('⚠️ 도착 정보 없음', level: LogLevel.warning);
            }
          } catch (e) {
            logMessage('❌ 버스 정보 파싱 오류: $e', level: LogLevel.error);
            logMessage('원본 응답: $result', level: LogLevel.debug);
          }
        } else {
          logMessage('⚠️ API 응답이 null입니다', level: LogLevel.warning);
        }
      } catch (e) {
        logMessage('❌ 버스 API 호출 오류: $e', level: LogLevel.error);
      }

      return false;
    } catch (e) {
      logMessage('❌ 자동 알람 버스 정보 업데이트 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  // ✅ 문자열 형태의 도착 시간을 분 단위 정수로 변환하는 메서드 개선
  int _parseRemainingMinutes(dynamic estimatedTime) {
    if (estimatedTime == null) return -1;

    final String timeStr = estimatedTime.toString().trim();

    // 곧 도착 관련
    if (timeStr == '곧 도착' || timeStr == '전' || timeStr == '도착') return 0;

    // 운행 종료 관련
    if (timeStr == '운행종료' || timeStr == '-' || timeStr == '운행종료.') return -1;

    // 출발 예정 관련
    if (timeStr.contains('출발예정') || timeStr.contains('기점출발')) return -1;

    // 숫자 + '분' 형태 처리
    if (timeStr.contains('분')) {
      final numericValue = timeStr.replaceAll(RegExp(r'[^0-9]'), '');
      return numericValue.isEmpty ? -1 : int.tryParse(numericValue) ?? -1;
    }

    // 순수 숫자인 경우
    final numericValue = timeStr.replaceAll(RegExp(r'[^0-9]'), '');
    if (numericValue.isNotEmpty) {
      final minutes = int.tryParse(numericValue);
      if (minutes != null && minutes >= 0 && minutes <= 180) {
        // 3시간 이내만 유효
        return minutes;
      }
    }

    logMessage('⚠️ 파싱할 수 없는 도착 시간 형식: "$timeStr"', level: LogLevel.warning);
    return -1;
  }
}
