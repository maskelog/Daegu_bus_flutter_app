import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AlarmManager {
  static const String _activeAlarmsKey = 'active_alarms';
  static List<Function()> _listeners = [];
  static List<AlarmInfo> _cachedAlarms = [];

  // 리스너 관리
  static void addListener(Function() listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  static void removeListener(Function() listener) {
    _listeners.remove(listener);
  }

  static void _notifyListeners() {
    for (final listener in _listeners) {
      try {
        listener();
      } catch (e) {
        print('❌ [ERROR] AlarmManager 리스너 알림 중 오류: $e');
      }
    }
  }

  // 알람 추가
  static Future<void> addAlarm({
    required String busNo,
    required String stationName,
    required String routeId,
    required String wincId,
  }) async {
    try {
      print('🐛 [DEBUG] [AlarmManager] 알람 추가 요청: $busNo, $stationName, $routeId');
      
      final alarmKey = '${busNo}_${stationName}_$routeId';
      
      // 중복 체크
      final existingAlarms = await getActiveAlarms();
      final isDuplicate = existingAlarms.any((alarm) => 
        alarm.busNo == busNo && 
        alarm.stationName == stationName && 
        alarm.routeId == routeId
      );
      
      if (isDuplicate) {
        print('🐛 [DEBUG] [$alarmKey] 이미 존재하는 알람 - 스킵');
        return;
      }
      
      // 새 알람 생성
      final newAlarm = AlarmInfo(
        busNo: busNo,
        stationName: stationName,
        routeId: routeId,
        wincId: wincId,
        createdAt: DateTime.now(),
      );
      
      // 캐시에 추가
      _cachedAlarms.add(newAlarm);
      
      // 저장
      await _saveAlarms(_cachedAlarms);
      
      print('🐛 [DEBUG] [$alarmKey] 알람 추가 완료');
      
      // 리스너들에게 알림
      _notifyListeners();
      
    } catch (e) {
      print('❌ [ERROR] 알람 추가 실패: $e');
      throw e;
    }
  }

  // 특정 알람 취소
  static Future<void> cancelAlarm({
    required String busNo,
    required String stationName,
    required String routeId,
  }) async {
    try {
      print('🐛 [DEBUG] [AlarmManager] 알람 취소 요청: $busNo, $stationName, $routeId');
      
      final alarmKey = '${busNo}_${stationName}_$routeId';
      
      // 캐시에서 제거
      _cachedAlarms.removeWhere((alarm) =>
        alarm.busNo == busNo &&
        alarm.stationName == stationName &&
        alarm.routeId == routeId
      );
      
      print('🐛 [DEBUG] [$alarmKey] 캐시에서 제거됨');
      
      // 저장
      await _saveAlarms(_cachedAlarms);
      
      print('🐛 [DEBUG] [$alarmKey] 알람 취소 완료');
      
      // 리스너들에게 알림
      _notifyListeners();
      
    } catch (e) {
      print('❌ [ERROR] 알람 취소 실패: $e');
      throw e;
    }
  }

  // 모든 알람 취소
  static Future<void> cancelAllAlarms() async {
    try {
      print('🐛 [DEBUG] [AlarmManager] 모든 알람 취소 요청: ${_cachedAlarms.length}개');
      
      // 캐시 클리어
      _cachedAlarms.clear();
      
      // 저장
      await _saveAlarms(_cachedAlarms);
      
      print('🐛 [DEBUG] ✅ 모든 알람 취소 완료');
      
      // 리스너들에게 알림
      _notifyListeners();
      
    } catch (e) {
      print('❌ [ERROR] 모든 알람 취소 실패: $e');
      throw e;
    }
  }

  // 알람 활성 상태 확인
  static Future<bool> isAlarmActive({
    required String busNo,
    required String stationName,
    required String routeId,
  }) async {
    try {
      // 캐시가 비어있으면 로드
      if (_cachedAlarms.isEmpty) {
        await loadAlarms();
      }
      
      final isActive = _cachedAlarms.any((alarm) =>
        alarm.busNo == busNo &&
        alarm.stationName == stationName &&
        alarm.routeId == routeId
      );
      
      return isActive;
      
    } catch (e) {
      print('❌ [ERROR] 알람 활성 상태 확인 실패: $e');
      return false;
    }
  }

  // 활성 알람 목록 가져오기
  static Future<List<AlarmInfo>> getActiveAlarms() async {
    try {
      // 캐시가 비어있으면 로드
      if (_cachedAlarms.isEmpty) {
        await loadAlarms();
      }
      
      return List.from(_cachedAlarms);
      
    } catch (e) {
      print('❌ [ERROR] 활성 알람 목록 가져오기 실패: $e');
      return [];
    }
  }

  // 알람 데이터 로드
  static Future<void> loadAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarmsJson = prefs.getString(_activeAlarmsKey);
      
      if (alarmsJson != null && alarmsJson.isNotEmpty) {
        final List<dynamic> alarmsList = json.decode(alarmsJson);
        _cachedAlarms = alarmsList.map((json) => AlarmInfo.fromJson(json)).toList();
      } else {
        _cachedAlarms = [];
      }
      
      print('🐛 [DEBUG] [AlarmManager] 알람 로드 완료: ${_cachedAlarms.length}개');
      
    } catch (e) {
      print('❌ [ERROR] 알람 로드 실패: $e');
      _cachedAlarms = [];
    }
  }

  // 알람 데이터 저장
  static Future<void> _saveAlarms(List<AlarmInfo> alarms) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarmsJson = json.encode(alarms.map((alarm) => alarm.toJson()).toList());
      await prefs.setString(_activeAlarmsKey, alarmsJson);
      
      print('🐛 [DEBUG] ✅ 알람 저장 완료: ${alarms.length}개');
      
    } catch (e) {
      print('❌ [ERROR] 알람 저장 실패: $e');
      throw e;
    }
  }

  // 캐시 강제 새로고침
  static Future<void> refreshCache() async {
    try {
      _cachedAlarms.clear();
      await loadAlarms();
      _notifyListeners();
      
      print('🐛 [DEBUG] [AlarmManager] 캐시 새로고침 완료');
      
    } catch (e) {
      print('❌ [ERROR] 캐시 새로고침 실패: $e');
    }
  }

  // 디버그 정보 출력
  static void printDebugInfo() {
    print('🐛 [DEBUG] === AlarmManager 상태 ===');
    print('🐛 [DEBUG] 캐시된 알람 수: ${_cachedAlarms.length}');
    print('🐛 [DEBUG] 등록된 리스너 수: ${_listeners.length}');
    
    for (int i = 0; i < _cachedAlarms.length; i++) {
      final alarm = _cachedAlarms[i];
      print('🐛 [DEBUG] [$i] ${alarm.busNo}번 - ${alarm.stationName} (${alarm.routeId})');
    }
    
    print('🐛 [DEBUG] ========================');
  }
}

// 알람 정보 클래스
class AlarmInfo {
  final String busNo;
  final String stationName;
  final String routeId;
  final String wincId;
  final DateTime createdAt;

  AlarmInfo({
    required this.busNo,
    required this.stationName,
    required this.routeId,
    required this.wincId,
    required this.createdAt,
  });

  // JSON 변환
  Map<String, dynamic> toJson() {
    return {
      'busNo': busNo,
      'stationName': stationName,
      'routeId': routeId,
      'wincId': wincId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AlarmInfo.fromJson(Map<String, dynamic> json) {
    return AlarmInfo(
      busNo: json['busNo'] ?? '',
      stationName: json['stationName'] ?? '',
      routeId: json['routeId'] ?? '',
      wincId: json['wincId'] ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'AlarmInfo(busNo: $busNo, stationName: $stationName, routeId: $routeId, wincId: $wincId, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlarmInfo &&
        other.busNo == busNo &&
        other.stationName == stationName &&
        other.routeId == routeId;
  }

  @override
  int get hashCode {
    return busNo.hashCode ^ stationName.hashCode ^ routeId.hashCode;
  }
}
