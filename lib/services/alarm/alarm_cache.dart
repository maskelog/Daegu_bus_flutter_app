import '../../main.dart' show logMessage;
import 'alarm_state.dart';
import 'cached_bus_info.dart';

class AlarmCache {
  AlarmCache({required AlarmState state}) : _state = state;

  final AlarmState _state;

  CachedBusInfo? getCachedBusInfo(String busNo, String routeId) {
    final key = "${busNo}_$routeId";
    return _state.cachedBusInfo[key];
  }

  Map<String, dynamic>? getTrackingBusInfo() {
    if (!_state.isInTrackingMode) return null;

    if (_state.activeAlarms.isNotEmpty) {
      final alarm = _state.activeAlarms.values.first;
      final key = "${alarm.busNo}_${alarm.routeId}";
      final cachedInfo = _state.cachedBusInfo[key];

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

      return {
        'busNumber': alarm.busNo,
        'stationName': alarm.stationName,
        'remainingMinutes': alarm.getCurrentArrivalMinutes(),
        'currentStation': alarm.currentStation ?? '',
        'routeId': alarm.routeId,
      };
    }

    for (var entry in _state.cachedBusInfo.entries) {
      final key = entry.key;
      final cachedInfo = entry.value;
      final remainingMinutes = cachedInfo.remainingMinutes;

      final isRecent =
          DateTime.now().difference(cachedInfo.lastUpdated).inMinutes < 10;

      if (isRecent) {
        final parts = key.split('_');
        if (parts.isNotEmpty) {
          final busNumber = parts[0];
          final routeId = parts.length > 1 ? parts[1] : '';
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
    _state.cachedBusInfo[key] = cachedInfo;
    logMessage('🚌 버스 정보 캐시 업데이트: $busNo번, $remainingMinutes분 후');
  }

  void updateCachedBusInfo(CachedBusInfo cachedInfo) {
    final key = "${cachedInfo.busNo}_${cachedInfo.routeId}";
    _state.cachedBusInfo[key] = cachedInfo;
  }

  void removeCachedBusInfo(String busNo, String routeId) {
    final key = "${busNo}_$routeId";
    _state.cachedBusInfo.remove(key);
  }

  void removeCachedBusInfoByKey(String key) {
    _state.cachedBusInfo.remove(key);
  }

  void clearCachedBusInfo() {
    _state.cachedBusInfo.clear();
  }

  void removeFromCacheBeforeCancel(
    String busNo,
    String stationName,
    String routeId,
  ) {
    final keysToRemove = <String>[];
    _state.activeAlarms.forEach((key, alarm) {
      if (alarm.busNo == busNo &&
          alarm.stationName == stationName &&
          alarm.routeId == routeId) {
        keysToRemove.add(key);
      }
    });

    for (var key in keysToRemove) {
      _state.activeAlarms.remove(key);
    }

    final cacheKey = "${busNo}_$routeId";
    _state.cachedBusInfo.remove(cacheKey);

    _state.autoAlarms.removeWhere(
      (alarm) =>
          alarm.busNo == busNo &&
          alarm.stationName == stationName &&
          alarm.routeId == routeId,
    );
  }
}
