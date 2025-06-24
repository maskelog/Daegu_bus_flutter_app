import 'dart:async';
import 'dart:convert';

import 'package:daegu_bus_app/models/alarm_data.dart';
import 'package:daegu_bus_app/models/auto_alarm.dart';
import 'package:flutter/material.dart';
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
    context.read<AlarmService>().removeListener(_loadFullAutoAlarms);
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
    if (confirmed == true) await alarmService.stopAllTracking();
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
              _buildPanelActions(context, alarmService),
              if (autoAlarms.isNotEmpty) _buildAutoAlarmSection(autoAlarms),
              if (manualAlarms.isNotEmpty)
                _buildManualAlarmList(context, manualAlarms),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPanelActions(BuildContext context, AlarmService alarmService) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        IconButton(
          onPressed: alarmService.refreshAlarms,
          icon: const Icon(Icons.refresh, color: Colors.grey),
          tooltip: '새로고침',
          iconSize: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
        ),
        IconButton(
          onPressed: () => _cancelAllAlarms(context),
          icon: const Icon(Icons.clear_all, color: Colors.red),
          tooltip: '모든 알람 취소',
          iconSize: 20,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
        ),
      ],
    );
  }

  Widget _buildAutoAlarmSection(List<AlarmData> alarms) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8, bottom: 8, top: 8),
          child: Text("자동 알람",
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.black54)),
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
                const Icon(Icons.alarm, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(fullAlarm.getFormattedTime(),
                    style: const TextStyle(fontSize: 14)),
              ],
            ),
            Text(_getRepeatDaysText(fullAlarm.repeatDays),
                style: const TextStyle(fontSize: 10, color: Colors.grey),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha(25),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.directions_bus,
                color: Colors.blue.shade600, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${alarm.busNo}번 버스',
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87)),
                const SizedBox(height: 4),
                Text(alarm.stationName,
                    style:
                        TextStyle(fontSize: 14, color: Colors.grey.shade600)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(_getRemainingTimeText(alarm),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: _getRemainingTimeColor(alarm))),
              const SizedBox(height: 2),
              Text('남은 시간',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => _cancelSpecificAlarm(context, alarm),
            icon: const Icon(Icons.close),
            color: Colors.grey.shade600,
            tooltip: '알람 취소',
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  Future<void> _cancelSpecificAlarm(
      BuildContext context, AlarmData alarm) async {
    try {
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

  Color _getRemainingTimeColor(AlarmData alarm) {
    final now = DateTime.now();
    final remaining = alarm.scheduledTime.difference(now);
    if (remaining.inMinutes < 1) return Colors.red.shade600;
    if (remaining.inMinutes < 5) return Colors.orange.shade700;
    return Colors.blue;
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
