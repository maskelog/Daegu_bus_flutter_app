import 'package:flutter/material.dart';

import '../models/bus_info.dart';
import '../services/alarm_service.dart';
import '../services/notification_service.dart';

/// 승차 알람 설정/해제의 공용 흐름.
///
/// "있으면 해제, 없으면 도착 시간 확인 후 설정 + 스낵바 안내"가
/// 홈·정류장 상세·즐겨찾기 화면에 각각 복제되어 있던 것을 한 곳에 모은다.
/// await 이후 context를 쓰지 않도록 messenger를 먼저 캡처한다.
class BoardingAlarmActions {
  BoardingAlarmActions._();

  /// 승차 알람 토글.
  ///
  /// 해제는 [bus] 정보 없이도 동작한다 (도착 정보가 사라져도 해제는 가능해야 함).
  /// [cancelOngoingNotification]은 진행 중 추적 알림까지 지울 때 사용.
  static Future<void> toggle(
    BuildContext context, {
    required AlarmService alarmService,
    required String busNo,
    required String stationName,
    required String routeId,
    required String stationId,
    required BusInfo? bus,
    required bool hasAlarm,
    bool cancelOngoingNotification = false,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      if (hasAlarm) {
        await alarmService.cancelAlarmByRoute(busNo, stationName, routeId);
        if (cancelOngoingNotification) {
          await NotificationService().cancelOngoingTracking();
        }
        messenger.showSnackBar(
          SnackBar(content: Text('$busNo번 승차 알람이 해제되었습니다')),
        );
        return;
      }

      if (bus == null) {
        messenger.showSnackBar(
          const SnackBar(content: Text('도착 정보가 없어 알람을 설정할 수 없습니다')),
        );
        return;
      }

      final minutes = bus.getRemainingMinutes();
      if (minutes <= 0) {
        messenger.showSnackBar(
          const SnackBar(content: Text('버스가 이미 도착했거나 곧 도착합니다')),
        );
        return;
      }

      await alarmService.setOneTimeAlarm(
        busNo,
        stationName,
        minutes,
        routeId: routeId,
        stationId: stationId,
        useTTS: true,
        isImmediateAlarm: true,
        currentStation: bus.currentStation,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('$busNo번 버스 $minutes분 후 승차 알람이 설정되었습니다')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('알람 처리에 실패했습니다: $e')),
      );
    }
  }

  /// 이어폰 전용 즉시 알람 설정 (즐겨찾기 화면).
  static Future<void> setEarphoneAlarm(
    BuildContext context, {
    required AlarmService alarmService,
    required String busNo,
    required String stationName,
    required String routeId,
    required String stationId,
    required BusInfo? bus,
  }) async {
    final messenger = ScaffoldMessenger.of(context);

    if (bus == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('도착 정보가 없습니다.')),
      );
      return;
    }
    final minutes = bus.getRemainingMinutes();
    if (minutes < 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('운행 종료 상태입니다.')),
      );
      return;
    }

    try {
      await alarmService.setOneTimeAlarm(
        busNo,
        stationName,
        minutes,
        routeId: routeId,
        stationId: stationId,
        useTTS: true,
        isImmediateAlarm: true,
        earphoneOnlyOverride: true,
        currentStation: bus.currentStation,
      );
      messenger.showSnackBar(
        SnackBar(content: Text('$busNo번 버스 이어폰 알람을 설정했습니다.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('알람 처리에 실패했습니다: $e')),
      );
    }
  }
}
