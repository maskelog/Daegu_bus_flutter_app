import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../models/bus_arrival.dart';
import '../utils/notification_helper.dart';
import '../utils/tts_helper.dart';

/// 알람 데이터 모델
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

/// WorkManager 콜백 핸들러 - main.dart에서 초기화할 때 사용
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    try {
      debugPrint('WorkManager 태스크 시작: $task');
      await WakelockPlus.enable();

      if (task == 'busAlarmTask') {
        // 입력 데이터 추출
        final int alarmId = inputData!['alarmId'] as int;
        final String busNo = inputData['busNo'] as String;
        final String stationName = inputData['stationName'] as String;
        final int remainingMinutes = inputData['remainingMinutes'] as int;
        final String? currentStation = inputData['currentStation'] as String?;

        debugPrint('버스 알람 실행: $busNo, $stationName, $remainingMinutes분');

        // 알림 표시
        await NotificationHelper.showNotification(
          id: alarmId,
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          currentStation: currentStation,
        );

        // TTS 음성 안내
        await TTSHelper.speakBusAlert(
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          currentStation: currentStation,
        );

        // TTS 완료를 위한 대기
        await Future.delayed(const Duration(seconds: 10));

        // 실행된 알람 데이터 제거
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('alarm_$alarmId');
      }

      return Future.value(true);
    } catch (e) {
      debugPrint('WorkManager 태스크 오류: $e');
      return Future.value(false);
    } finally {
      await WakelockPlus.disable();
      debugPrint('WorkManager 태스크 종료');
    }
  });
}

/// AlarmService: 앱 전체 알람을 관리하는 서비스
class AlarmService extends ChangeNotifier {
  List<AlarmData> _activeAlarms = [];
  Timer? _refreshTimer;
  bool _initialized = false;
  final Map<String, BusInfo> _busInfoCache = {};

  static final AlarmService _instance = AlarmService._internal();

  factory AlarmService() {
    return _instance;
  }

  AlarmService._internal() {
    _initialize();
  }

  // 초기화 메서드
  Future<void> _initialize() async {
    if (_initialized) return;

    // WorkManager 초기화는 main.dart에서 수행

    await loadAlarms();

    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      loadAlarms();
    });

    _initialized = true;
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

  // 알람 데이터 로드 (기존 코드 유지)
  Future<void> loadAlarms() async {
    final prefs = await SharedPreferences.getInstance();
    List<AlarmData> alarms = [];

    try {
      for (String key in prefs.getKeys()) {
        if (key.startsWith('alarm_')) {
          final String? jsonStr = prefs.getString(key);
          if (jsonStr != null) {
            try {
              final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);
              alarms.add(AlarmData.fromJson(jsonMap));
            } catch (e) {
              debugPrint('Failed to parse alarm data for key $key: $e');
            }
          }
        }
      }

      // 지난 알람 자동 삭제
      final now = DateTime.now();
      alarms = alarms.where((alarm) {
        return alarm.targetArrivalTime
            .isAfter(now.subtract(const Duration(minutes: 5)));
      }).toList();

      // 알람 정렬 및 캐시 동기화 (나머지 코드 유지)
      alarms.sort((a, b) => a.targetArrivalTime.compareTo(b.targetArrivalTime));

      bool shouldNotify = false;
      for (var alarm in alarms) {
        final cacheKey = "${alarm.busNo}_${alarm.routeId}";
        if (_busInfoCache.containsKey(cacheKey)) {
          final busInfo = _busInfoCache[cacheKey]!;
          final remainingMinutes = busInfo.getRemainingMinutes();

          if (alarm.getCurrentArrivalMinutes() != remainingMinutes) {
            alarm.updateRemainingMinutes(remainingMinutes);
            shouldNotify = true;
          }
        }
      }

      bool alarmsChanged = _activeAlarms.length != alarms.length;
      if (!alarmsChanged) {
        for (int i = 0; i < alarms.length; i++) {
          if (i >= _activeAlarms.length ||
              _activeAlarms[i].busNo != alarms[i].busNo ||
              _activeAlarms[i].routeId != alarms[i].routeId) {
            alarmsChanged = true;
            break;
          }
        }
      }

      _activeAlarms = alarms;

      if (shouldNotify || alarmsChanged) {
        notifyListeners();
      }

      // 지난 알람 삭제
      for (String key in prefs.getKeys()) {
        if (key.startsWith('alarm_')) {
          final String? jsonStr = prefs.getString(key);
          if (jsonStr != null) {
            try {
              final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);
              final alarm = AlarmData.fromJson(jsonMap);
              if (alarm.targetArrivalTime
                  .isBefore(now.subtract(const Duration(minutes: 5)))) {
                await prefs.remove(key);
              }
            } catch (e) {
              debugPrint('Failed to process expired alarm for key $key: $e');
            }
          }
        }
      }
    } catch (e) {
      debugPrint('알람 로드 중 오류 발생: $e');
    }
  }

  // WorkManager를 사용한 일회성 알람 설정
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
      // 예약 알람 시각 계산
      DateTime notificationTime = alarmTime.subtract(preNotificationTime);

      // 실제 도착 예정 시간 계산 (alarmTime 사용)
      final alarmData = AlarmData(
        busNo: busNo,
        stationName: stationName,
        remainingMinutes: remainingMinutes,
        routeId: routeId,
        scheduledTime: notificationTime,
        targetArrivalTime: alarmTime, // 원래 전달받은 alarmTime 사용
        currentStation: currentStation,
      );

      // 버스 정보가 제공된 경우 캐시에 저장
      if (busInfo != null) {
        _busInfoCache["${busNo}_$routeId"] = busInfo;
      }

      // SharedPreferences에 저장
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('alarm_$id', jsonEncode(alarmData.toJson()));

      // 이미 지난 시간이면 즉시 알림 표시
      if (notificationTime.isBefore(DateTime.now())) {
        await NotificationHelper.showNotification(
          id: id,
          busNo: busNo,
          stationName: stationName,
          remainingMinutes: remainingMinutes,
          currentStation: currentStation,
        );
        await prefs.remove('alarm_$id');
        return true;
      }

      // WorkManager로 알람 예약
      final uniqueTaskName = 'busAlarm_$id';
      final initialDelay = notificationTime.difference(DateTime.now());

      // 작업에 전달할 데이터
      final inputData = {
        'alarmId': id,
        'busNo': busNo,
        'stationName': stationName,
        'remainingMinutes': remainingMinutes,
        'currentStation': currentStation,
        'routeId': routeId,
      };

      // WorkManager 작업 등록
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

      debugPrint(
          '버스 알람 예약 성공: $busNo, $stationName, ${initialDelay.inMinutes}분 후 실행');

      await loadAlarms(); // 알람 목록 새로고침
      return true;
    } catch (e) {
      debugPrint('알람 설정 오류: $e');
      return false;
    }
  }

  // WorkManager를 사용한 알람 취소
// alarm_service.dart

  Future<bool> cancelAlarm(int id) async {
    try {
      debugPrint('알람 취소 시작: $id');

      // 알람 정보 찾기
      AlarmData? alarmToCancel;
      for (var alarm in _activeAlarms) {
        if (alarm.getAlarmId() == id) {
          alarmToCancel = alarm;
          break;
        }
      }

      // 1. SharedPreferences에서 삭제
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('alarm_$id');
      debugPrint('SharedPreferences에서 알람 제거: alarm_$id');

      // 2. WorkManager 작업 취소
      final uniqueTaskName = 'busAlarm_$id';
      try {
        debugPrint('WorkManager 작업 취소 시작: $uniqueTaskName');
        await Workmanager().cancelByUniqueName(uniqueTaskName);
        debugPrint('WorkManager 작업 취소 완료: $uniqueTaskName');
      } catch (e) {
        debugPrint('WorkManager 작업 취소 오류 (계속 진행): $e');
        // 오류가 발생해도 계속 진행
      }

      // 3. 알람 목록에서 제거
      final alarmRemoved = _activeAlarms.remove(alarmToCancel);
      debugPrint('알람 목록에서 제거: ${alarmRemoved ? "성공" : "실패 또는 이미 제거됨"}');

      _activeAlarms =
          _activeAlarms.where((alarm) => alarm.getAlarmId() != id).toList();
      debugPrint('알람 목록에서 제거 완료, 남은 알람 수: ${_activeAlarms.length}');

      // 4. TTS 음성 안내
      if (alarmToCancel != null) {
        try {
          await TTSHelper.speakAlarmCancel(alarmToCancel.busNo);
        } catch (e) {
          debugPrint('알람 취소 TTS 오류: $e');
        }
      }

      // 5. UI 갱신
      notifyListeners();
      debugPrint('알람 취소 UI 갱신 요청');

      // 6. 알림 취소 (NotificationHelper 사용)
      try {
        await NotificationHelper.cancelNotification(id);
        debugPrint('알림 취소 완료: $id');
      } catch (e) {
        debugPrint('알림 취소 오류: $e');
      }

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
      int alarmId = getAlarmId(busNo, stationName, routeId: routeId);
      debugPrint(
          '버스/정류장으로 알람 취소: $busNo, $stationName, $routeId (ID: $alarmId)');
      return await cancelAlarm(alarmId);
    } catch (e) {
      debugPrint('알람 취소 오류 (경로별): $e');
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
}
