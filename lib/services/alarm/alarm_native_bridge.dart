import 'package:flutter/services.dart';

class AlarmNativeBridge {
  AlarmNativeBridge({MethodChannel? methodChannel})
      : _methodChannel = methodChannel;

  MethodChannel? _methodChannel;

  void setMethodChannel(MethodChannel? methodChannel) {
    _methodChannel = methodChannel;
  }

  Future<void> startBusMonitoringService({
    required String stationId,
    required String stationName,
    required String routeId,
    required String busNo,
  }) async {
    await _methodChannel?.invokeMethod('startBusMonitoringService', {
      'stationId': stationId,
      'stationName': stationName,
      'routeId': routeId,
      'busNo': busNo,
    });
  }

  Future<dynamic> stopBusMonitoringService() async {
    return _methodChannel?.invokeMethod('stopBusMonitoringService');
  }

  Future<void> stopTtsTracking() async {
    await _methodChannel?.invokeMethod('stopTtsTracking');
  }

  Future<void> stopSpecificTracking({
    required String busNo,
    required String routeId,
    required String stationName,
  }) async {
    await _methodChannel?.invokeMethod('stopSpecificTracking', {
      'busNo': busNo,
      'routeId': routeId,
      'stationName': stationName,
    });
  }

  Future<void> forceStopTracking() async {
    await _methodChannel?.invokeMethod('forceStopTracking');
  }

  Future<void> stopAllTts() async {
    await _methodChannel?.invokeMethod('stopAllTts');
  }

  Future<void> cancelAlarmNotification({
    required String routeId,
    required String busNo,
    required String stationName,
  }) async {
    await _methodChannel?.invokeMethod('cancelAlarmNotification', {
      'routeId': routeId,
      'busNo': busNo,
      'stationName': stationName,
    });
  }

  Future<dynamic> getBusArrivalByRouteId({
    required String stationId,
    required String routeId,
  }) async {
    return _methodChannel?.invokeMethod('getBusArrivalByRouteId', {
      'stationId': stationId,
      'routeId': routeId,
    });
  }
}
