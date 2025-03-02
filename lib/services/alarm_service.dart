import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import '../models/bus_arrival.dart';
import '../utils/notification_helper.dart';
import '../utils/tts_helper.dart';

/// 알람 데이터 모델
class AlarmData {
  final String busNo;
  final String stationName;
  final int remainingMinutes; // 설정 당시 남은 분
  final String routeId;
  final DateTime scheduledTime; // 알람이 울릴 예정 시간
  DateTime targetArrivalTime; // 버스 도착 예정 시간
  final String? currentStation; // 현재 버스 위치 (n번째 전 출발)
  int _currentRemainingMinutes; // 현재 실시간으로 계산된 남은 분 (외부에서 업데이트 가능)

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

  // 현재 알람이 울릴 때까지 남은 시간 계산 (실제 시간 기반)
  int getCurrentAlarmMinutes() {
    final now = DateTime.now();
    final difference = scheduledTime.difference(now);

    // 분 단위로 반환 (최소 0)
    return difference.inSeconds > 0 ? (difference.inSeconds / 60).ceil() : 0;
  }

  // 현재 버스 도착까지 남은 시간 구하기 - BusCard와 시간 동기화를 위해 외부에서 업데이트된 값 사용
  int getCurrentArrivalMinutes() {
    return _currentRemainingMinutes;
  }

  // 외부에서 남은 시간을 업데이트 (BusCard의 최신 시간 정보로 동기화)
  void updateRemainingMinutes(int minutes) {
    _currentRemainingMinutes = minutes;
  }

  // 알람 ID 생성
  int getAlarmId() {
    return "${busNo}_${stationName}_$routeId".hashCode;
  }
}

/// AlarmService: 앱 전체 알람을 관리하는 서비스
class AlarmService extends ChangeNotifier {
  List<AlarmData> _activeAlarms = [];
  Timer? _refreshTimer;
  bool _initialized = false;

  // 버스 정보 캐시 - API 부하 감소를 위해 사용
  final Map<String, BusInfo> _busInfoCache = {};

  // Singleton 패턴
  static final AlarmService _instance = AlarmService._internal();

  factory AlarmService() {
    return _instance;
  }

  AlarmService._internal() {
    _initialize();
  }

  // 초기화
  Future<void> _initialize() async {
    if (_initialized) return;

    await loadAlarms();

    // 15초마다 알람 정보 갱신 (더 빠른 업데이트를 위해 30초 → 15초로 변경)
    _refreshTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      loadAlarms();
    });

    _initialized = true;
  }

  // 알람 목록 가져오기
  List<AlarmData> get activeAlarms => _activeAlarms;

  // 캐시된 버스 정보 가져오기
  BusInfo? getCachedBusInfo(String busNo, String routeId) {
    final key = "${busNo}_$routeId";
    return _busInfoCache[key];
  }

  // 버스 정보 캐시 업데이트
  void updateBusInfoCache(
      String busNo, String routeId, BusInfo busInfo, int remainingTime) {
    final key = "${busNo}_$routeId";

    // 기존 캐시된 정보 확인
    BusInfo? existingInfo = _busInfoCache[key];

    // 1. 캐시에 정보가 없거나
    // 2. 남은 시간이 변경되었거나
    // 3. 현재 정류장이 변경된 경우에만 캐시 업데이트
    bool shouldUpdate = existingInfo == null ||
        existingInfo.getRemainingMinutes() != remainingTime ||
        existingInfo.currentStation != busInfo.currentStation;

    if (shouldUpdate) {
      // 새 정보 저장
      _busInfoCache[key] = busInfo;

      // 관련된 알람이 있으면 업데이트
      bool alarmUpdated = false;
      for (var alarm in _activeAlarms) {
        if ("${alarm.busNo}_${alarm.routeId}" == key) {
          // 알람의 남은 시간 정보 업데이트
          alarm.updateRemainingMinutes(remainingTime);

          // 알람의 타겟 도착 시간을 현재 시간 기준으로 다시 계산
          alarm.updateTargetArrivalTime(
              DateTime.now().add(Duration(minutes: remainingTime)));

          alarmUpdated = true;
        }
      }

      // 알람 정보가 변경된 경우만 UI 업데이트 알림
      if (alarmUpdated) {
        debugPrint('BusInfo Cache 업데이트: $busNo, 남은 시간: $remainingTime분');
        notifyListeners();
      }
    }
  }

  // 알람 데이터 로드
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

      // 지난 알람 자동 삭제 (5분 이상 지난 알람)
      final now = DateTime.now();
      alarms = alarms.where((alarm) {
        return alarm.targetArrivalTime
            .isAfter(now.subtract(const Duration(minutes: 5)));
      }).toList();

      // 알람 도착 시간 기준 정렬
      alarms.sort((a, b) => a.targetArrivalTime.compareTo(b.targetArrivalTime));

      // 캐시에서 버스 정보 동기화
      bool shouldNotify = false;
      for (var alarm in alarms) {
        final cacheKey = "${alarm.busNo}_${alarm.routeId}";
        if (_busInfoCache.containsKey(cacheKey)) {
          // BusCard에서 가져온 최신 남은 시간으로 업데이트
          final busInfo = _busInfoCache[cacheKey]!;
          final remainingMinutes = busInfo.getRemainingMinutes();

          // 현재 값과 다른 경우에만 업데이트 (불필요한 알림 방지)
          if (alarm.getCurrentArrivalMinutes() != remainingMinutes) {
            alarm.updateRemainingMinutes(remainingMinutes);
            shouldNotify = true;
          }
        }
      }

      // 알람 목록 변경 감지
      bool alarmsChanged = _activeAlarms.length != alarms.length;
      if (!alarmsChanged) {
        // 개수는 같지만 내용이 다를 수 있으므로 자세히 확인
        for (int i = 0; i < alarms.length; i++) {
          if (i >= _activeAlarms.length ||
              _activeAlarms[i].busNo != alarms[i].busNo ||
              _activeAlarms[i].routeId != alarms[i].routeId) {
            alarmsChanged = true;
            break;
          }
        }
      }

      // 알람 목록 업데이트
      _activeAlarms = alarms;

      // 변경사항이 있는 경우에만 UI 갱신 알림
      if (shouldNotify || alarmsChanged) {
        notifyListeners();
      }

      // 지난 알람 삭제 (SharedPreferences에서)
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

  // 일회성 알람 설정
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

      // AndroidAlarmManager로 알람 예약
      bool success = await AndroidAlarmManager.oneShotAt(
        notificationTime,
        id,
        alarmCallback,
        exact: true,
        wakeup: true,
        rescheduleOnReboot: true,
      );

      if (success) {
        await loadAlarms(); // 알람 목록 새로고침
      }

      return success;
    } catch (e) {
      debugPrint('알람 설정 오류: $e');
      return false;
    }
  }

  // 알람 취소
  Future<bool> cancelAlarm(int id) async {
    try {
      debugPrint('알람 취소 시작: $id');

      // 1. 먼저 알람 정보 찾기 (TTS 실행을 위해)
      AlarmData? alarmToCancel;
      for (var alarm in _activeAlarms) {
        if (alarm.getAlarmId() == id) {
          alarmToCancel = alarm;
          break;
        }
      }

      // 2. SharedPreferences에서 삭제
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('alarm_$id');

      // 3. 관련 캐시 데이터 참조 (제거하지 않고 참조만 함)
      if (alarmToCancel != null) {
        // cacheKey 변수 생성 및 사용 (로그 출력)
        final cacheKey = "${alarmToCancel.busNo}_${alarmToCancel.routeId}";
        debugPrint('관련 캐시 키: $cacheKey (제거하지 않음)');
        // 캐시는 유지 (다른 알람에서 사용할 수 있으므로)
      }

      // 4. AndroidAlarmManager에서 취소
      bool success = true;
      try {
        success = await AndroidAlarmManager.cancel(id);
      } catch (e) {
        debugPrint('알람 매니저 취소 오류 (무시 가능): $e');
        // 알람 매니저 오류는 무시하고 진행 (이미 SharedPreferences에서 삭제됨)
        success = true;
      }

      // 5. 작업 성공 시, 목록 갱신 및 UI 업데이트
      if (success) {
        // 알람 목록에서 해당 알람 제거
        _activeAlarms.removeWhere((alarm) => alarm.getAlarmId() == id);

        // TTS 음성 안내 실행 (alarmToCancel이 있는 경우)
        if (alarmToCancel != null) {
          try {
            await TTSHelper.speakAlarmCancel(alarmToCancel.busNo);
          } catch (e) {
            debugPrint('알람 취소 TTS 오류 (무시): $e');
          }
        }

        // UI 즉시 업데이트
        notifyListeners();

        debugPrint('알람 취소 성공: $id');
      }

      return success;
    } catch (e) {
      debugPrint('알람 취소 오류: $e');
      return false;
    }
  }

  // 알람 ID 생성 함수
  int getAlarmId(String busNo, String stationName, {String routeId = ''}) {
    return (busNo + stationName + routeId).hashCode;
  }

  // routeId로 알람 취소 (BusCard에서 사용)
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

  // 특정 버스/정류장 알람이 이미 있는지 확인
  bool hasAlarm(String busNo, String stationName, String routeId) {
    return _activeAlarms.any((alarm) =>
        alarm.busNo == busNo &&
        alarm.stationName == stationName &&
        alarm.routeId == routeId);
  }

  // 특정 버스/정류장 알람 찾기
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

  // 알람 목록 강제 갱신 후 UI 업데이트 (위젯에서 직접 호출)
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

/// 최상위 함수: 별도의 isolate에서 실행되어야 합니다.
void alarmCallback(int alarmId) async {
  final prefs = await SharedPreferences.getInstance();
  final String? alarmJson = prefs.getString('alarm_$alarmId');

  if (alarmJson != null) {
    final alarmData = AlarmData.fromJson(jsonDecode(alarmJson));

    // OS 알림 표시
    await NotificationHelper.showNotification(
      id: alarmId,
      busNo: alarmData.busNo,
      stationName: alarmData.stationName,
      remainingMinutes: alarmData.remainingMinutes,
      currentStation: alarmData.currentStation,
    );

    // TTS 음성 안내 실행
    await TTSHelper.speakBusAlert(
      busNo: alarmData.busNo,
      stationName: alarmData.stationName,
      remainingMinutes: alarmData.remainingMinutes,
      currentStation: alarmData.currentStation,
    );

    debugPrint('알람 실행: $alarmId');
  } else {
    debugPrint('알람 데이터가 없습니다. 알람 ID: $alarmId');
  }
}
