import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/bus_arrival.dart';
import '../models/bus_info.dart';
import '../services/alarm_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../services/alarm_manager.dart';
import '../utils/tts_switcher.dart';

/// 통합된 버스 상세정보 위젯
/// 홈스크린과 즐겨찾기에서 공통으로 사용
class UnifiedBusDetailWidget extends StatefulWidget {
  final BusArrival busArrival;
  final String stationId;
  final String stationName;
  final VoidCallback? onTap;
  final bool isCompact; // true: 컴팩트 뷰, false: 풀 뷰

  const UnifiedBusDetailWidget({
    super.key,
    required this.busArrival,
    required this.stationId,
    required this.stationName,
    this.onTap,
    this.isCompact = true,
  });

  @override
  State<UnifiedBusDetailWidget> createState() => _UnifiedBusDetailWidgetState();
}

class _UnifiedBusDetailWidgetState extends State<UnifiedBusDetailWidget> {
  Timer? _updateTimer;
  bool _isUpdating = false;
  late BusInfo _currentBus;
  late int _remainingTime;

  @override
  void initState() {
    super.initState();
    _initializeBusInfo();
    _startPeriodicUpdate();
  }

  @override
  void didUpdateWidget(UnifiedBusDetailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busArrival != oldWidget.busArrival) {
      _initializeBusInfo();
    }
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  void _initializeBusInfo() {
    if (widget.busArrival.busInfoList.isNotEmpty) {
      _currentBus = widget.busArrival.busInfoList.first;
      _remainingTime = _currentBus.getRemainingMinutes();
    }
  }

  void _startPeriodicUpdate() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && !_isUpdating) {
        _updateBusInfo();
      }
    });
  }

  Future<void> _updateBusInfo() async {
    if (_isUpdating || !mounted) return;
    final currentContext = context; // Store context before async operations
    setState(() => _isUpdating = true);
    try {
      final updatedArrivals = await ApiService.getBusArrivalByRouteId(
        widget.stationId,
        widget.busArrival.routeId,
      );
      if (mounted &&
          updatedArrivals.isNotEmpty &&
          updatedArrivals[0].busInfoList.isNotEmpty) {
        setState(() {
          final newBus = updatedArrivals[0].busInfoList.first;
          if (!newBus.isOutOfService) {
            _currentBus = newBus;
            _remainingTime = newBus.getRemainingMinutes();
          }
        });
      }
      // Always check alarm state asynchronously before updating notification
      final alarmService =
          Provider.of<AlarmService>(currentContext, listen: false);
      final hasAlarm = alarmService.hasAlarm(
        widget.busArrival.routeNo,
        widget.stationName,
        widget.busArrival.routeId,
      );
      if (hasAlarm) {
        NotificationService().updateBusTrackingNotification(
          busNo: widget.busArrival.routeNo,
          stationName: widget.stationName,
          remainingMinutes: _remainingTime,
          currentStation: _currentBus.currentStation,
          routeId: widget.busArrival.routeId,
          stationId: widget.stationId,
        );
      }
      // else: do nothing (do not call cancelOngoingTracking)
    } catch (e) {
      debugPrint('Error updating bus info: $e');
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _toggleAlarm() async {
    try {
      final alarmService = Provider.of<AlarmService>(context, listen: false);
      final hasAlarm = alarmService.hasAlarm(
        widget.busArrival.routeNo,
        widget.stationName,
        widget.busArrival.routeId,
      );
      if (hasAlarm) {
        await _cancelAlarm();
      } else {
        await _setAlarm();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('알람 처리 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _cancelAlarm() async {
    final currentContext = context; // Store context before async operations
    final alarmService =
        Provider.of<AlarmService>(currentContext, listen: false);
    final notificationService = NotificationService();

    debugPrint(
        '🔔 알람 취소 시작: ${widget.busArrival.routeNo}번 버스, ${widget.stationName}');

    try {
      // 1. 네이티브 추적 중지 (가장 먼저)
      await _stopNativeTracking();
      debugPrint('✅ 네이티브 추적 중지 완료');

      // 2. AlarmManager에서 알람 제거
      await AlarmManager.cancelAlarm(
        busNo: widget.busArrival.routeNo,
        stationName: widget.stationName,
        routeId: widget.busArrival.routeId,
      );
      debugPrint('✅ AlarmManager 알람 취소 완료');

      // 3. AlarmService에서 알람 제거
      final success = await alarmService.cancelAlarmByRoute(
        widget.busArrival.routeNo,
        widget.stationName,
        widget.busArrival.routeId,
      );
      debugPrint('✅ AlarmService 알람 취소 ${success ? '성공' : '실패'}');

      // 4. 모든 알림 취소
      await notificationService.cancelOngoingTracking();
      debugPrint('✅ 모든 알림 취소 완료');

      // 5. TTS 추적 중지
      await TtsSwitcher.stopTtsTracking(widget.busArrival.routeNo);
      debugPrint('✅ TTS 추적 중지 완료');

      // 6. 버스 모니터링 서비스 중지
      await alarmService.stopBusMonitoringService();
      debugPrint('✅ 버스 모니터링 서비스 중지 완료');

      // 7. 알람 목록 새로고침
      await alarmService.refreshAlarms();
      debugPrint('✅ 알람 목록 새로고침 완료');

      // 8. 추가 안전장치: 1초 후 다시 한번 정리
      Future.delayed(const Duration(seconds: 1), () async {
        try {
          await notificationService.cancelOngoingTracking();
          await _stopNativeTracking();
          debugPrint('✅ 지연 정리 작업 완료');
        } catch (e) {
          debugPrint('⚠️ 지연 정리 작업 오류: $e');
        }
      });

      // 9. UI 업데이트
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          const SnackBar(content: Text('승차 알람이 취소되었습니다')),
        );
      }

      debugPrint('✅ 모든 알람 취소 작업 완료');
    } catch (e) {
      debugPrint('❌ 알람 취소 중 오류: $e');
      // 오류가 발생해도 UI는 업데이트
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(content: Text('알람 취소 중 일부 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  Future<void> _setAlarm() async {
    if (_remainingTime <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('버스가 이미 도착했거나 곧 도착합니다')),
        );
      }
      return;
    }
    final currentContext = context; // Store context
    final alarmService =
        Provider.of<AlarmService>(currentContext, listen: false);

    // 동일한 정류장의 다른 버스 알람 취소
    for (var alarm in alarmService.activeAlarms) {
      if (alarm.stationName == widget.stationName &&
          alarm.busNo != widget.busArrival.routeNo) {
        await alarmService.cancelAlarmByRoute(
            alarm.busNo, alarm.stationName, alarm.routeId);
        await TtsSwitcher.stopTtsTracking(alarm.busNo);
      }
    }

    // AlarmManager에 알람 추가
    await AlarmManager.addAlarm(
      busNo: widget.busArrival.routeNo,
      stationName: widget.stationName,
      routeId: widget.busArrival.routeId,
      wincId: widget.stationId,
    );

    // 네이티브 추적 시작
    await _startNativeTracking();

    // AlarmService에 일회성 알람 설정
    final success = await alarmService.setOneTimeAlarm(
      widget.busArrival.routeNo,
      widget.stationName,
      _remainingTime,
      routeId: widget.busArrival.routeId,
      useTTS: true,
      isImmediateAlarm: true,
      currentStation: _currentBus.currentStation,
    );

    if (success) {
      // 버스 모니터링 서비스 시작
      await alarmService.startBusMonitoringService(
        stationId: widget.stationId,
        stationName: widget.stationName,
        routeId: widget.busArrival.routeId,
        busNo: widget.busArrival.routeNo,
      );

      // TTS 설정
      final settings =
          Provider.of<SettingsService>(currentContext, listen: false);
      if (settings.useTts) {
        final ttsSwitcher = TtsSwitcher();
        await ttsSwitcher.initialize();
        final headphoneConnected = await ttsSwitcher.isHeadphoneConnected();
        if (settings.speakerMode == SettingsService.speakerModeHeadset) {
          if (headphoneConnected) {
            await TtsSwitcher.startTtsTracking(
              routeId: widget.busArrival.routeId,
              stationId: widget.stationId,
              busNo: widget.busArrival.routeNo,
              stationName: widget.stationName,
              remainingMinutes: _remainingTime,
            );
          }
        } else {
          await TtsSwitcher.startTtsTracking(
            routeId: widget.busArrival.routeId,
            stationId: widget.stationId,
            busNo: widget.busArrival.routeNo,
            stationName: widget.stationName,
            remainingMinutes: _remainingTime,
          );
        }
      }

      // 실시간 버스 업데이트 시작
      NotificationService().startRealTimeBusUpdates(
        busNo: widget.busArrival.routeNo,
        stationName: widget.stationName,
        routeId: widget.busArrival.routeId,
        stationId: widget.stationId,
      );

      await alarmService.refreshAlarms();
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(currentContext).showSnackBar(
          const SnackBar(content: Text('승차 알람이 설정되었습니다')),
        );
      }
    }
  }

  Future<void> _startNativeTracking() async {
    try {
      const platform = MethodChannel('com.example.daegu_bus_app/notification');
      await platform.invokeMethod('startBusTrackingService', {
        'busNo': widget.busArrival.routeNo,
        'stationName': widget.stationName,
        'routeId': widget.busArrival.routeId,
      });
      debugPrint('✅ 네이티브 추적 시작: ${widget.busArrival.routeNo}번');
    } catch (e) {
      debugPrint('❌ 네이티브 추적 시작 실패: $e');
    }
  }

  Future<void> _stopNativeTracking() async {
    try {
      const platform = MethodChannel('com.example.daegu_bus_app/notification');

      // 1. 특정 추적 중지
      await platform.invokeMethod('stopSpecificTracking', {
        'busNo': widget.busArrival.routeNo,
        'routeId': widget.busArrival.routeId,
        'stationName': widget.stationName,
      });
      debugPrint('✅ 특정 네이티브 추적 중지: ${widget.busArrival.routeNo}번');

      // 2. 모든 추적 중지 (백업)
      await platform.invokeMethod('stopBusTrackingService');
      debugPrint('✅ 모든 네이티브 추적 중지');

      // 3. 진행 중인 추적 취소
      await platform.invokeMethod('cancelOngoingTracking');
      debugPrint('✅ 진행 중인 추적 취소');

      // 4. 특정 알림 취소
      await platform.invokeMethod('cancelNotification', {
        'id': 1001, // ONGOING_NOTIFICATION_ID
      });
      debugPrint('✅ 특정 알림 취소');

      // 5. Android에 특정 알람 취소 알림 (NotificationHelper.kt 동기화)
      await platform.invokeMethod('cancelAlarmNotification', {
        'busNo': widget.busArrival.routeNo,
        'routeId': widget.busArrival.routeId,
        'stationName': widget.stationName,
      });
      debugPrint('✅ Android에 알람 취소 알림 전송');

      // 6. 강제 전체 추적 중지 (최종 안전장치)
      await platform.invokeMethod('forceStopTracking');
      debugPrint('✅ 강제 네이티브 추적 중지');
    } catch (e) {
      debugPrint('❌ 네이티브 추적 중지 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.busArrival.busInfoList.isEmpty) return _buildEmptyCard();
    return widget.isCompact ? _buildCompactCard() : _buildFullCard();
  }

  Widget _buildEmptyCard() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20),
            const SizedBox(width: 8),
            Text('도착 정보를 불러오는 중...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactCard() {
    final arrivalInfo = _getArrivalInfo();
    return Consumer<AlarmService>(
      builder: (context, alarmService, child) {
        final hasAlarm = alarmService.hasAlarm(widget.busArrival.routeNo,
            widget.stationName, widget.busArrival.routeId);
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 8),
          elevation: 1,
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.directions_bus,
                      size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 12),
                  Text(widget.busArrival.routeNo,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold)),
                  if (_currentBus.isLowFloor)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('저상',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                  color: Colors.green[700],
                                  fontWeight: FontWeight.w500)),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            _currentBus.currentStation.isNotEmpty
                                ? _currentBus.currentStation
                                : widget.stationName,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                        Text(_currentBus.remainingStops,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!_currentBus.isOutOfService)
                        Text('도착예정',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                      Text(arrivalInfo.text,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  color: arrivalInfo.color,
                                  fontWeight: FontWeight.bold)),
                    ],
                  ),
                  if (!_currentBus.isOutOfService)
                    Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: IconButton(
                        icon: Icon(
                            hasAlarm
                                ? Icons.notifications_active
                                : Icons.notifications_none,
                            color: hasAlarm
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                        onPressed: _toggleAlarm,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        iconSize: 24,
                        tooltip: hasAlarm ? '알람 해제' : '승차 알람 설정',
                      ),
                    ),
                  if (_isUpdating)
                    const Padding(
                        padding: EdgeInsets.only(left: 12),
                        child: SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFullCard() {
    final arrivalInfo = _getArrivalInfo();
    return Consumer<AlarmService>(
      builder: (context, alarmService, child) {
        final hasAlarm = alarmService.hasAlarm(widget.busArrival.routeNo,
            widget.stationName, widget.busArrival.routeId);
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.directions_bus,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                            '${widget.busArrival.routeNo}번 - ${widget.stationName}',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      if (_isUpdating)
                        const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(widget.busArrival.routeNo,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                          color: _currentBus.isOutOfService
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant
                                              : Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                          fontWeight: FontWeight.bold)),
                              if (_currentBus.isLowFloor)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green[100],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text('저상',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                              color: Colors.green[700],
                                              fontWeight: FontWeight.w500)),
                                ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(_currentBus.currentStation,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                          Text(_currentBus.remainingStops,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                        ],
                      ),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!_currentBus.isOutOfService)
                            Text('도착예정',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant)),
                          Text(arrivalInfo.text,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                      color: arrivalInfo.color,
                                      fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed:
                          _currentBus.isOutOfService ? null : _toggleAlarm,
                      icon: Icon(
                          hasAlarm
                              ? Icons.notifications_off
                              : Icons.notifications_active,
                          color: Colors.white),
                      label: Text(hasAlarm ? '승차 알람 해제' : '승차 알람 설정',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _currentBus.isOutOfService
                            ? Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withOpacity(0.12)
                            : (hasAlarm
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  ({String text, Color color}) _getArrivalInfo() {
    if (_currentBus.isOutOfService) {
      return (
        text: '운행종료',
        color: Theme.of(context).colorScheme.onSurfaceVariant
      );
    }
    if (_remainingTime <= 0) {
      return (text: '곧 도착', color: Theme.of(context).colorScheme.error);
    }
    return (
      text: '$_remainingTime분',
      color: _remainingTime <= 3
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.primary
    );
  }
}

/// 버스 상세정보 모달을 표시하는 헬퍼 함수
void showUnifiedBusDetailModal(
  BuildContext context,
  BusArrival busArrival,
  String stationId,
  String stationName,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    backgroundColor: Theme.of(context).colorScheme.surface,
    barrierColor: Colors.black54,
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 드래그 핸들
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    height: 5,
                    width: 40,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withOpacity(0.3),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
                // 헤더
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${busArrival.routeNo}번 버스',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          Text('$stationName → ${busArrival.direction}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.zero,
                    children: [
                      UnifiedBusDetailWidget(
                        busArrival: BusArrival(
                          routeNo: busArrival.routeNo,
                          routeId: busArrival.routeId,
                          busInfoList: busArrival.busInfoList.isNotEmpty
                              ? [busArrival.busInfoList.first]
                              : [],
                          direction: busArrival.direction,
                        ),
                        stationId: stationId,
                        stationName: stationName,
                        isCompact: false,
                      ),
                      if (busArrival.busInfoList.length > 1) ...[
                        const SizedBox(height: 24),
                        Text('다음 버스 정보',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        ...busArrival.busInfoList.skip(1).map((bus) {
                          final remainingMinutes = bus.getRemainingMinutes();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 1,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                  color: Theme.of(context).dividerColor),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(busArrival.routeNo,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                        color: bus
                                                                .isOutOfService
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant
                                                            : Theme.of(context)
                                                                .colorScheme
                                                                .primary,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                            if (bus.isLowFloor)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                    left: 8),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.green[100],
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text('저상',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                            color: Colors
                                                                .green[700],
                                                            fontWeight:
                                                                FontWeight
                                                                    .w500)),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(bus.currentStation,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant)),
                                        Text(bus.remainingStops,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (!bus.isOutOfService)
                                        Text('도착예정',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant)),
                                      Text(
                                          bus.isOutOfService
                                              ? '운행종료'
                                              : '$remainingMinutes분',
                                          style: Theme.of(
                                                  context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  color:
                                                      bus
                                                              .isOutOfService
                                                          ? Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant
                                                          : (remainingMinutes <=
                                                                  3
                                                              ? Theme.of(
                                                                      context)
                                                                  .colorScheme
                                                                  .error
                                                              : Theme.of(
                                                                      context)
                                                                  .colorScheme
                                                                  .primary),
                                                  fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 100), // 하단 여백
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
