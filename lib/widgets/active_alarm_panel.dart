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
      duration: const Duration(seconds: 2), // Faster pulsing
    )..repeat(reverse: true); // Infinite pulsing animation
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

  @override
  Widget build(BuildContext context) {
    return Consumer<AlarmService>(
      builder: (context, alarmService, child) {
        final allAlarms = alarmService.activeAlarms;
        if (allAlarms.isEmpty) return const SizedBox.shrink();

        final autoAlarms = allAlarms.where((a) => a.isAutoAlarm).toList();
        final manualAlarms = allAlarms.where((a) => !a.isAutoAlarm).toList();

        return Container(
          margin: const EdgeInsets.only(left: 16, right: 16, top: 8, bottom: 0),
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
          padding: const EdgeInsets.only(left: 8, bottom: 4, top: 8),
          child: Text(
            "자동 알람",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        SizedBox(
          height: 80, // Increased height for the button
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                vertical: 8, horizontal: 4), // Padding for shadow
            itemCount: alarms.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) =>
                _buildAutoAlarmCompactItem(context, alarms[index]),
          ),
        ),
        // Divider 제거
      ],
    );
  }

  Widget _buildAutoAlarmCompactItem(BuildContext context, AlarmData alarm) {
    final key = '${alarm.busNo}_${alarm.stationName}_${alarm.routeId}';
    final fullAlarm = _fullAutoAlarms[key];
    if (fullAlarm == null) return const SizedBox.shrink();

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Card(
          elevation: 1,
          margin: EdgeInsets.zero,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Container(
            width: 140, // Increased width for better layout
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  fullAlarm.routeNo,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  fullAlarm.stationName,
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.alarm,
                        size: 13,
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(width: 2),
                    Text(
                      fullAlarm.getFormattedTime(),
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Positioned(
          top: -8,
          right: -8,
          child: InkWell(
            onTap: () => _cancelAutoAlarm(context, alarm),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withAlpha(26),
                    blurRadius: 4,
                    offset: const Offset(1, 1),
                  )
                ],
              ),
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.cancel,
                size: 20,
                color: Theme.of(context)
                    .colorScheme
                    .onSurfaceVariant
                    .withAlpha(204),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _cancelAutoAlarm(BuildContext context, AlarmData alarm) async {
    if (!mounted) return;

    try {
      final alarmService = context.read<AlarmService>();
      await alarmService.stopAutoAlarm(
          alarm.busNo, alarm.stationName, alarm.routeId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${alarm.busNo}번 버스 자동 알람이 중지되었습니다.'),
              duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('자동 알람 중지 중 오류가 발생했습니다.'),
              duration: Duration(seconds: 2)),
        );
      }
    }
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
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 16), // More spacing
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28), // Very rounded
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(28),
        child: InkWell(
          onTap: () {}, // Add tap handler if needed
          borderRadius: BorderRadius.circular(28),
          child: Padding(
            padding: const EdgeInsets.all(20), // Generous padding
            child: Row(
              children: [
                // ✨ Stunning alarm icon with gradient and animation
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.primary,
                        colorScheme.primary.withAlpha(179),
                        colorScheme.tertiary,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20), // Squircle-like
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.primary.withAlpha(102),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulsing background animation
                      AnimatedBuilder(
                        animation: _progressController,
                        builder: (context, child) {
                          return Container(
                            width: 56 + (_progressController.value * 8),
                            height: 56 + (_progressController.value * 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: colorScheme.primary.withAlpha(
                                  (77 * (1 - _progressController.value)).round(),
                                ),
                                width: 2,
                              ),
                            ),
                          );
                        },
                      ),
                      // Main alarm bell icon
                      Icon(
                        Icons
                            .notifications_active_rounded, // Better icon than headphones
                        color: colorScheme.onPrimary,
                        size: 28,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${alarm.busNo}번',
                            style: TextStyle(
                              fontSize: 20, // Larger
                              fontWeight: FontWeight.w900, // Bolder
                              color: colorScheme.onSurface,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '버스 알람',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.location_on_rounded,
                              size: 14, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              alarm.stationName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onSurfaceVariant,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Time badge with gradient
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _getRemainingTimeColor(context, alarm),
                        _getRemainingTimeColor(context, alarm).withAlpha(204),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: _getRemainingTimeColor(context, alarm)
                            .withAlpha(77),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Text(
                        _getRemainingTimeText(alarm),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '남은시간',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withAlpha(230),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: IconButton.filledTonal(
                    onPressed: () => _cancelSpecificAlarm(context, alarm),
                    icon:
                        Icon(Icons.close_rounded, color: colorScheme.onSurface),
                    tooltip: '알람 취소',
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.surfaceContainerHighest,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _cancelSpecificAlarm(
      BuildContext context, AlarmData alarm) async {
    if (!mounted) return; // Check mounted state at the beginning

    try {
      await context
          .read<AlarmService>()
          .cancelAlarmByRoute(alarm.busNo, alarm.stationName, alarm.routeId);

      // UI 즉시 업데이트 보장
      if (mounted) {
        setState(() {
          // 강제 UI 업데이트
        });
        // BuildContext 사용 전에 mounted 상태 재확인
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${alarm.busNo}번 버스 알람이 취소되었습니다.')),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // 오류 발생 시에도 UI 업데이트
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('알람 취소 중 오류가 발생했습니다.')),
      );
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
}
