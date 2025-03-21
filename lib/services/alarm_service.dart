import 'dart:async';
import 'dart:convert';
import 'package:daegu_bus_app/screens/profile_screen.dart';
import 'package:daegu_bus_app/utils/alarm_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:http/http.dart' as http;
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

class AlarmService extends ChangeNotifier {
  List<AlarmData> _activeAlarms = [];
  Timer? _refreshTimer;
  final List<AlarmData> _alarmCache = [];
  bool _initialized = false;
  final Map<String, BusInfo> _busInfoCache = {};
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
      if (call.method == 'onBusArrival') {
        try {
          final Map<String, dynamic> data =
              jsonDecode(call.arguments as String);
          final busNumber = data['busNumber'] as String;
          final stationName = data['stationName'] as String;
          final currentStation = data['currentStation'] as String;
          final routeId = data['routeId'] as String? ?? '';

          debugPrint('버스 도착 이벤트 수신: $busNumber, $stationName, $currentStation');

          final notificationKey = '${busNumber}_${stationName}_$routeId';
          if (_isNotificationProcessed(busNumber, stationName, routeId)) {
            debugPrint('이미 처리된 알림입니다: $notificationKey');
            return true;
          }

          await NotificationService().showBusArrivingSoon(
            busNo: busNumber,
            stationName: stationName,
            currentStation: currentStation,
          );
          await TTSHelper.speakBusAlert(
            busNo: busNumber,
            stationName: stationName,
            remainingMinutes: 0,
            currentStation: currentStation,
            priority: true,
          );
          _markNotificationAsProcessed(busNumber, stationName, routeId);
          return true;
        } catch (e) {
          debugPrint('버스 도착 이벤트 처리 오류: $e');
          return false;
        }
      }
      return null;
    });
  }

  Future<void> _registerBusArrivalReceiver() async {
    try {
      await _methodChannel?.invokeMethod('registerBusArrivalReceiver');
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
      final result = await _methodChannel?.invokeMethod(
        'startBusMonitoringService',
        {
          'stationId': stationId,
          'routeId': routeId,
          'stationName': stationName,
        },
      );
      if (result == true) {
        _isInTrackingMode = true;
        _markExistingAlarmsAsTracked(routeId);
        notifyListeners();
      }
      debugPrint('버스 모니터링 서비스 시작: $result, 트래킹 모드: $_isInTrackingMode');
      return result == true;
    } catch (e) {
      debugPrint('버스 모니터링 서비스 시작 오류: $e');
      return false;
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

  BusInfo? getCachedBusInfo(String busNo, String routeId) {
    final key = "${busNo}_$routeId";
    return _busInfoCache[key];
  }

  void updateBusInfoCache(
      String busNo, String routeId, BusInfo busInfo, int remainingTime) {
    final key = "${busNo}_$routeId";
    BusInfo? existingInfo = _busInfoCache[key];
    bool shouldUpdate = existingInfo == null ||
        existingInfo.getRemainingMinutes() != remainingTime ||
        existingInfo.currentStation != busInfo.currentStation;
    if (shouldUpdate) {
      _busInfoCache[key] = busInfo;
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
        notifyListeners();
      }
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

  Future<void> loadAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final alarmKeys = keys.where((key) => key.startsWith('alarm_')).toList();
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
      bool skipNotification = _isInTrackingMode &&
          _activeAlarms.any((alarm) => alarm.routeId == routeId);
      if (skipNotification) {
        debugPrint('트래킹 모드에서 알람 예약 (알림 없음): $busNo, $stationName');
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
      if (busInfo != null) {
        _busInfoCache["${busNo}_$routeId"] = busInfo;
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('alarm_$id', jsonEncode(alarmData.toJson()));
      if (notificationTime.isBefore(DateTime.now()) && !skipNotification) {
        await NotificationService().showNotification(
          id: id,
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          currentStation: currentStation,
        );
        await prefs.remove('alarm_$id');
        return true;
      }
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
      if (!_isInTrackingMode) {
        await NotificationService().showOngoingBusTracking(
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
        debugPrint('포그라운드 서비스 시작 요청: stationId=$busNo, routeId=$routeId');
      }
      debugPrint(
          '버스 알람 예약 성공: $busNo, $stationName, ${initialDelay.inMinutes}분 후 실행${skipNotification ? ' (알림 없음)' : ''}');
      await loadAlarms();
      return true;
    } catch (e) {
      debugPrint('알람 설정 오류: $e');
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
    _busInfoCache.remove(key);

    notifyListeners();
  }

  Future<List<DateTime>> _fetchHolidays(int year, int month) async {
    const String serviceKey =
        'U5x6XR0zMipv1m9CQk72BiQp3Goghg6YttuJm3BNnCnf2dda1ywYcAbqdWkt1Kkug3DdpZS77wXCpioS0y9WYA==';
    final String url =
        'http://apis.data.go.kr/B090041/openapi/service/SpcdeInfoService/getRestDeInfo'
        '?serviceKey=$serviceKey'
        '&solYear=$year'
        '&solMonth=${month.toString().padLeft(2, '0')}'
        '&numOfRows=100';

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        final items = jsonData['response']['body']['items']?['item'] ?? [];
        final holidays = <DateTime>[];

        if (items is List) {
          for (var item in items) {
            if (item['isHoliday'] == 'Y') {
              final locdate = item['locdate'].toString();
              final holiday = DateTime.parse(locdate);
              holidays.add(holiday);
            }
          }
        } else if (items is Map && items['isHoliday'] == 'Y') {
          final locdate = items['locdate'].toString();
          holidays.add(DateTime.parse(locdate));
        }

        debugPrint('공휴일 목록 ($year-$month): $holidays');
        return holidays;
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

      final holidays = await _fetchHolidays(now.year, now.month);

      for (var alarm in autoAlarms) {
        if (!alarm.isActive) continue;

        final alarmId = alarm.id.hashCode;
        final todayWeekday = now.weekday;

        if (!alarm.repeatDays.contains(todayWeekday)) continue;

        if (alarm.excludeWeekends && (todayWeekday == 6 || todayWeekday == 7)) {
          continue;
        }

        bool isHoliday = holidays.any((holiday) =>
            holiday.year == now.year &&
            holiday.month == now.month &&
            holiday.day == now.day);
        if (alarm.excludeHolidays && isHoliday) continue;

        DateTime scheduledTime = DateTime(
          now.year,
          now.month,
          now.day,
          alarm.hour,
          alarm.minute,
        );

        if (scheduledTime.isBefore(now)) {
          scheduledTime = scheduledTime.add(const Duration(days: 1));
        }

        await setOneTimeAlarm(
          id: alarmId,
          alarmTime: scheduledTime,
          preNotificationTime: Duration(minutes: alarm.beforeMinutes),
          busNo: alarm.routeNo,
          stationName: alarm.stationName,
          remainingMinutes: alarm.beforeMinutes,
          routeId: alarm.routeId,
        );

        debugPrint(
            '자동 알람 예약: ${alarm.routeNo}, ${alarm.stationName}, ${alarm.hour}:${alarm.minute}');
      }
      await loadAlarms();
      notifyListeners();
    } catch (e) {
      debugPrint('자동 알람 갱신 오류: $e');
    }
  }
}
