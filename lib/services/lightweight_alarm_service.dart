import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alarm_data.dart' as alarm_model;
import '../main.dart' show logMessage, LogLevel;

/// 경량화된 알람 서비스
/// 메모리 사용량과 백그라운드 처리를 최적화
class LightweightAlarmService extends ChangeNotifier {
  static final LightweightAlarmService _instance =
      LightweightAlarmService._internal();
  factory LightweightAlarmService() => _instance;

  // 메모리 효율을 위해 Map 대신 Set 사용 (필요한 경우만)
  final Set<String> _activeAlarmKeys = <String>{};
  final Map<String, alarm_model.AlarmData> _alarmCache = {};

  bool _initialized = false;
  MethodChannel? _methodChannel;
  Timer? _refreshTimer;

  // 메모리 절약을 위한 상수
  static const int _maxCacheSize = 20;
  static const Duration _refreshInterval = Duration(seconds: 30); // 30초로 증가

  LightweightAlarmService._internal();

  /// 경량화된 초기화
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _setupMethodChannel();
      await _loadActiveAlarms();
      _startPeriodicRefresh();

      _initialized = true;
      logMessage('✅ 경량화된 알람 서비스 초기화 완료');
    } catch (e) {
      logMessage('❌ 알람 서비스 초기화 오류: $e', level: LogLevel.error);
    }
  }

  /// 메서드 채널 설정 (최소화)
  void _setupMethodChannel() {
    _methodChannel = const MethodChannel('com.example.daegu_bus_app/bus_api');
    _methodChannel?.setMethodCallHandler(_handleMethodCall);
  }

  /// 메서드 호출 처리 (간소화)
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onAlarmCanceledFromNotification':
          return await _handleAlarmCanceled(call.arguments);
        case 'onAllAlarmsCanceled':
          return await _handleAllAlarmsCanceled();
        default:
          return null;
      }
    } catch (e) {
      logMessage('메서드 채널 오류: $e', level: LogLevel.error);
      return null;
    }
  }

  /// 특정 알람 취소 처리
  Future<bool> _handleAlarmCanceled(dynamic args) async {
    try {
      final Map<String, dynamic> data = Map<String, dynamic>.from(args);
      final String busNo = data['busNo'] ?? '';
      final String routeId = data['routeId'] ?? '';
      final String stationName = data['stationName'] ?? '';

      final String alarmKey = "${busNo}_${stationName}_$routeId";

      if (_activeAlarmKeys.remove(alarmKey)) {
        _alarmCache.remove(alarmKey);
        await _saveActiveAlarms();
        notifyListeners();
        logMessage('✅ 알람 취소 처리: $alarmKey');
      }

      return true;
    } catch (e) {
      logMessage('알람 취소 처리 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  /// 모든 알람 취소 처리
  Future<bool> _handleAllAlarmsCanceled() async {
    try {
      if (_activeAlarmKeys.isNotEmpty || _alarmCache.isNotEmpty) {
        _activeAlarmKeys.clear();
        _alarmCache.clear();
        await _saveActiveAlarms();
        notifyListeners();
        logMessage('✅ 모든 알람 취소 처리 완료');
      }
      return true;
    } catch (e) {
      logMessage('모든 알람 취소 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  /// 알람 추가 (경량화)
  Future<bool> addAlarm(alarm_model.AlarmData alarm) async {
    try {
      final String key = _generateAlarmKey(alarm);

      // 캐시 크기 제한
      if (_alarmCache.length >= _maxCacheSize) {
        _clearOldestCache();
      }

      _activeAlarmKeys.add(key);
      _alarmCache[key] = alarm;

      await _saveActiveAlarms();
      notifyListeners();

      logMessage('✅ 알람 추가: ${alarm.busNo}');
      return true;
    } catch (e) {
      logMessage('알람 추가 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  /// 알람 제거
  Future<bool> removeAlarm(
      String busNo, String stationName, String routeId) async {
    try {
      final String key = "${busNo}_${stationName}_$routeId";

      if (_activeAlarmKeys.remove(key)) {
        _alarmCache.remove(key);
        await _saveActiveAlarms();
        notifyListeners();
        logMessage('✅ 알람 제거: $key');
        return true;
      }

      return false;
    } catch (e) {
      logMessage('알람 제거 오류: $e', level: LogLevel.error);
      return false;
    }
  }

  /// 활성 알람 목록 조회 (경량화)
  List<alarm_model.AlarmData> get activeAlarms {
    return _alarmCache.values.toList();
  }

  /// 활성 알람 수
  int get activeAlarmCount => _activeAlarmKeys.length;

  /// 추적 모드 여부
  bool get isInTrackingMode => _activeAlarmKeys.isNotEmpty;

  /// 주기적 새로고침 시작 (간격 증가로 리소스 절약)
  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) => _refreshAlarms());
  }

  /// 알람 새로고침 (경량화)
  void _refreshAlarms() {
    try {
      if (_activeAlarmKeys.isEmpty) return;

      // 필요한 경우만 새로고침 수행
      logMessage('🔄 알람 새로고침 (${_activeAlarmKeys.length}개)');
      notifyListeners();
    } catch (e) {
      logMessage('알람 새로고침 오류: $e', level: LogLevel.error);
    }
  }

  /// 활성 알람 저장 (경량화)
  Future<void> _saveActiveAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> keysList = _activeAlarmKeys.toList();
      await prefs.setStringList('active_alarm_keys', keysList);
    } catch (e) {
      logMessage('알람 저장 오류: $e', level: LogLevel.error);
    }
  }

  /// 활성 알람 로드
  Future<void> _loadActiveAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String>? keysList = prefs.getStringList('active_alarm_keys');

      if (keysList != null) {
        _activeAlarmKeys.addAll(keysList);
        logMessage('📱 활성 알람 ${keysList.length}개 로드됨');
      }
    } catch (e) {
      logMessage('알람 로드 오류: $e', level: LogLevel.error);
    }
  }

  /// 오래된 캐시 정리 (메모리 절약)
  void _clearOldestCache() {
    try {
      if (_alarmCache.length >= _maxCacheSize) {
        final firstKey = _alarmCache.keys.first;
        _alarmCache.remove(firstKey);
        _activeAlarmKeys.remove(firstKey);
        logMessage('🧹 오래된 캐시 정리: $firstKey');
      }
    } catch (e) {
      logMessage('캐시 정리 오류: $e', level: LogLevel.error);
    }
  }

  /// 알람 키 생성
  String _generateAlarmKey(alarm_model.AlarmData alarm) {
    return "${alarm.busNo}_${alarm.stationName}_${alarm.routeId}";
  }

  /// 리소스 정리
  @override
  void dispose() {
    _refreshTimer?.cancel();
    _alarmCache.clear();
    _activeAlarmKeys.clear();
    super.dispose();
  }
}
