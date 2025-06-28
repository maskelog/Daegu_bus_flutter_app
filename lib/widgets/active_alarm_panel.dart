import 'dart:async';
import 'dart:convert';

import 'package:daegu_bus_app/models/alarm_data.dart';
import 'package:daegu_bus_app/models/auto_alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/alarm_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ActiveAlarmPanel extends StatefulWidget {
  const ActiveAlarmPanel({super.key});

  @override
  State<ActiveAlarmPanel> createState() => _ActiveAlarmPanelState();
}

class _ActiveAlarmPanelState extends State<ActiveAlarmPanel>
    with SingleTickerProviderStateMixin {
  late AnimationController _progressController;
  Map<String, AutoAlarm> _fullAutoAlarms = {};

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..addListener(() {
        if (mounted) setState(() {});
      });
    _loadFullAutoAlarms();
    // 알람 변경 시 자동 알람 정보도 새로고침
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final alarmService = context.read<AlarmService>();
      alarmService.addListener(_loadFullAutoAlarms);
    });
  }

  @override
  void dispose() {
    _progressController.dispose();
    if (mounted) {
      try {
        context.read<AlarmService>().removeListener(_loadFullAutoAlarms);
      } catch (e) {
        // 이미 dispose된 경우 무시
      }
    }
    super.dispose();
  }

  Future<void> _loadFullAutoAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarmsJson = prefs.getStringList('auto_alarms') ?? [];
      final tempMap = <String, AutoAlarm>{};
      for (var jsonStr in alarmsJson) {
        try {
          final alarm = AutoAlarm.fromJson(jsonDecode(jsonStr));
          final key = '${alarm.routeNo}_${alarm.stationName}_${alarm.routeId}';
          tempMap[key] = alarm;
        } catch (_) {}
      }
      if (mounted) setState(() => _fullAutoAlarms = tempMap);
    } catch (_) {}
  }

  Future<void> _cancelAllAlarms(BuildContext context) async {
    final alarmService = context.read<AlarmService>();
    if (alarmService.activeAlarms.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('모든 알람 취소'),
        content: Text(
            '현재 설정된 ${alarmService.activeAlarms.length}개의 알람을 모두 취소하시겠습니까?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('아니요')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('예')),
        ],
      ),
    );
    if (confirmed == true) {
      // Android에 모든 알람 취소 알림 (NotificationHelper.kt 동기화)
      await _notifyAndroidAllAlarmsCancelled();
      await alarmService.stopAllTracking();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AlarmService>(
      builder: (context, alarmService, child) {
        final allAlarms = alarmService.activeAlarms;
        if (allAlarms.isEmpty) return const SizedBox.shrink();

        final autoAlarms = allAlarms.where((a) => a.isAutoAlarm).toList();
        final manualAlarms = allAlarms.where((a) => !a.isAutoAlarm).toList();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (autoAlarms.isNotEmpty) _buildAutoAlarmSection(autoAlarms),
              if (manualAlarms.isNotEmpty)
                _buildManualAlarmList(context, manualAlarms),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAutoAlarmSection(List<AlarmData> alarms) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 8, top: 8),
          child: Text(
            "자동 알람",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          height: 110,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: alarms.length,
            itemBuilder: (context, index) => _buildAutoAlarmItem(alarms[index]),
          ),
        ),
        const Divider(height: 32),
      ],
    );
  }

  Widget _buildAutoAlarmItem(AlarmData alarm) {
    final key = '${alarm.busNo}_${alarm.stationName}_${alarm.routeId}';
    final fullAlarm = _fullAutoAlarms[key];
    if (fullAlarm == null) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(fullAlarm.routeNo,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
            Text(fullAlarm.stationName,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
                maxLines: 1),
            const Spacer(),
            Row(
              children: [
                Icon(
                  Icons.alarm,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(fullAlarm.getFormattedTime(),
                    style: const TextStyle(fontSize: 14)),
              ],
            ),
            Text(
              _getRepeatDaysText(fullAlarm.repeatDays),
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualAlarmList(BuildContext context, List<AlarmData> alarms) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: alarms.length,
      itemBuilder: (context, index) =>
          _buildManualAlarmItem(context, alarms[index]),
    );
  }

  Widget _buildManualAlarmItem(BuildContext context, AlarmData alarm) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.directions_bus,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${alarm.busNo}번 버스',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    alarm.stationName,
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _getRemainingTimeText(alarm),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _getRemainingTimeColor(context, alarm),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '남은 시간',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _cancelSpecificAlarm(context, alarm),
              icon: const Icon(Icons.close),
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              tooltip: '알람 취소',
              iconSize: 20,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _notifyAndroidAllAlarmsCancelled() async {
    try {
      const platform = MethodChannel('com.example.daegu_bus_app/notification');
      await platform.invokeMethod('forceStopTracking');
      debugPrint('✅ Android에 모든 알람 취소 알림 전송');
    } catch (e) {
      debugPrint('❌ Android 모든 알람 취소 알림 실패: $e');
    }
  }

  Future<void> _notifyAndroidSpecificAlarmCancelled(AlarmData alarm) async {
    try {
      const platform = MethodChannel('com.example.daegu_bus_app/notification');
      await platform.invokeMethod('cancelAlarmNotification', {
        'busNo': alarm.busNo,
        'routeId': alarm.routeId,
        'stationName': alarm.stationName,
      });
      debugPrint('✅ Android에 특정 알람 취소 알림 전송: ${alarm.busNo}');
    } catch (e) {
      debugPrint('❌ Android 특정 알람 취소 알림 실패: $e');
    }
  }

  Future<void> _cancelSpecificAlarm(
      BuildContext context, AlarmData alarm) async {
    try {
      // Android에 특정 알람 취소 알림 (NotificationHelper.kt 동기화)
      await _notifyAndroidSpecificAlarmCancelled(alarm);

      await context
          .read<AlarmService>()
          .cancelAlarmByRoute(alarm.busNo, alarm.stationName, alarm.routeId);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('알람 취소 중 오류가 발생했습니다.')),
        );
      }
    }
  }

  String _getRemainingTimeText(AlarmData alarm) {
    final now = DateTime.now();
    final remaining = alarm.scheduledTime.difference(now);
    if (remaining.isNegative || remaining.inMinutes == 0) return '곧 도착';
    return '${remaining.inMinutes}분';
  }

  Color _getRemainingTimeColor(BuildContext context, AlarmData alarm) {
    final now = DateTime.now();
    final remaining = alarm.scheduledTime.difference(now);
    if (remaining.inMinutes < 1) return Theme.of(context).colorScheme.error;
    if (remaining.inMinutes < 5) return Theme.of(context).colorScheme.tertiary;
    return Theme.of(context).colorScheme.primary;
  }

  String _getRepeatDaysText(List<int> days) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    if (days.isEmpty) return '반복 없음';
    if (days.length == 7) return '매일';
    if (days.length == 5 && days.toSet().containsAll([1, 2, 3, 4, 5]))
      return '평일';
    if (days.length == 2 && days.toSet().containsAll([6, 7])) return '주말';
    return days.map((day) => weekdays[day - 1]).join(',');
  }
}
