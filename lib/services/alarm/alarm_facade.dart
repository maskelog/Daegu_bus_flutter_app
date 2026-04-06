import 'package:flutter/services.dart';

import '../../models/alarm_data.dart' as alarm_model;
import '../../models/auto_alarm.dart';
import 'cached_bus_info.dart';
import 'alarm_cache.dart';
import 'alarm_native_bridge.dart';
import 'alarm_scheduler.dart';
import 'alarm_state.dart';
import 'auto_alarm_engine.dart';
import 'holiday_service.dart';

class AlarmFacade {
  AlarmFacade({
    required bool Function(Map<String, dynamic>) validateRequiredFields,
    required String Function(String stationName, String routeId) resolveStationId,
  })  : state = AlarmState(),
        holidayService = HolidayService(),
        nativeBridge = AlarmNativeBridge(),
        scheduler = AlarmScheduler(
          validateRequiredFields: validateRequiredFields,
        ) {
    cache = AlarmCache(state: state);
    autoEngine = AutoAlarmEngine(
      state: state,
      resolveStationId: resolveStationId,
    );
  }

  final AlarmState state;
  final HolidayService holidayService;
  final AlarmNativeBridge nativeBridge;
  final AlarmScheduler scheduler;
  late final AlarmCache cache;
  late final AutoAlarmEngine autoEngine;

  Map<String, alarm_model.AlarmData> get activeAlarmsMap =>
      state.activeAlarms;
  List<alarm_model.AlarmData> get autoAlarmsList => state.autoAlarms;
  bool get isTrackingMode => state.isInTrackingMode;
  set isTrackingMode(bool value) => state.isInTrackingMode = value;
  String? get trackedRouteId => state.trackedRouteId;
  set trackedRouteId(String? value) => state.trackedRouteId = value;
  bool get isInTrackingMode => isTrackingMode;

  List<alarm_model.AlarmData> get activeAlarms =>
      state.activeAlarms.values.toList();
  List<alarm_model.AlarmData> get autoAlarms => state.autoAlarms;

  void setMethodChannel(MethodChannel? methodChannel) {
    nativeBridge.setMethodChannel(methodChannel);
    scheduler.setMethodChannel(methodChannel);
  }

  Future<List<DateTime>> getHolidays(int year, int month) {
    return holidayService.fetchHolidays(year, month);
  }

  Future<void> saveAutoAlarms() {
    return autoEngine.saveAutoAlarms();
  }

  Future<void> scheduleAutoAlarm(AutoAlarm alarm, DateTime scheduledTime) {
    return scheduler.scheduleAutoAlarm(alarm, scheduledTime);
  }

  CachedBusInfo? getCachedBusInfo(String busNo, String routeId) {
    return cache.getCachedBusInfo(busNo, routeId);
  }

  Map<String, dynamic>? getTrackingBusInfo() {
    return cache.getTrackingBusInfo();
  }

  void updateBusInfoCache(
    String busNo,
    String routeId,
    dynamic busInfo,
    int remainingMinutes,
  ) {
    cache.updateBusInfoCache(busNo, routeId, busInfo, remainingMinutes);
  }

  void removeFromCacheBeforeCancel(
    String busNo,
    String stationName,
    String routeId,
  ) {
    cache.removeFromCacheBeforeCancel(busNo, stationName, routeId);
  }

  void removeCachedBusInfoByKey(String key) {
    cache.removeCachedBusInfoByKey(key);
  }

  void clearCachedBusInfo() {
    cache.clearCachedBusInfo();
  }

  void updateCachedBusInfo(CachedBusInfo cachedInfo) {
    cache.updateCachedBusInfo(cachedInfo);
  }
}
