import 'dart:async';
import 'dart:convert';

import 'package:daegu_bus_app/models/alarm_data.dart';
import 'package:daegu_bus_app/models/auto_alarm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/alarm_manager.dart';
import '../services/alarm_service.dart';
import '../services/notification_service.dart';
import '../utils/tts_switcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ActiveAlarmPanel extends StatefulWidget {
  const ActiveAlarmPanel({super.key});

  @override
  State<ActiveAlarmPanel> createState() => _ActiveAlarmPanelState();
}

class _ActiveAlarmPanelState extends State<ActiveAlarmPanel>
    with SingleTickerProviderStateMixin {
  List<AlarmData> _activeAlarms = [];
  bool _isLoading = false;
  late AnimationController _progressController;
  late AlarmService _alarmService;
  late NotificationService _notificationService;
  Map<String, AutoAlarm> _fullAutoAlarms = {};

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30), // Approximate bus arrival window
    )..addListener(() {
        if (mounted) {
          setState(() {});
        }
      });

    _alarmService = Provider.of<AlarmService>(context, listen: false);
    _notificationService =
        Provider.of<NotificationService>(context, listen: false);
    _reloadData();
    _alarmService.addListener(_reloadData);
  }

  @override
  void dispose() {
    _progressController.dispose();
    _alarmService.removeListener(_reloadData);
    super.dispose();
  }

  void _reloadData() {
    _loadActiveAlarms();
    _loadFullAutoAlarms();
  }

  Future<void> _loadFullAutoAlarms() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final alarmsJson = prefs.getStringList('auto_alarms') ?? [];
      final Map<String, AutoAlarm> tempMap = {};
      for (var jsonStr in alarmsJson) {
        try {
          final alarm = AutoAlarm.fromJson(jsonDecode(jsonStr));
          final key = '${alarm.routeNo}_${alarm.stationName}_${alarm.routeId}';
          tempMap[key] = alarm;
        } catch (e) {
          debugPrint('자동 알람 패널 파싱 오류: $e');
        }
      }
      if (mounted) {
        setState(() {
          _fullAutoAlarms = tempMap;
        });
      }
    } catch (e) {
      debugPrint('자동 알람(전체) 로드 실패: $e');
    }
  }

  Future<void> _loadActiveAlarms() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // AlarmService에서 수동 및 자동 알람을 모두 포함하는 리스트를 가져옵니다.
      final allAlarms = _alarmService.activeAlarms;

      if (mounted) {
        setState(() {
          _activeAlarms = allAlarms;
        });
      }
    } catch (e) {
      debugPrint("활성 알람 로드 실패: $e");
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _cancelSpecificAlarm(
      BuildContext context, AlarmData alarm) async {
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    try {
      await alarmService.cancelAlarmByRoute(
          alarm.busNo, alarm.stationName, alarm.routeId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('알람 취소 중 오류가 발생했습니다.')),
        );
      }
    }
  }

  Future<void> _cancelAllAlarms(BuildContext context) async {
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    if (alarmService.activeAlarms.isEmpty) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('모든 알람 취소'),
        content: Text(
            '현재 설정된 ${alarmService.activeAlarms.length}개의 알람을 모두 취소하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('아니요'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await alarmService.stopAllTracking();
            },
            child: const Text('예'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AlarmService>(
      builder: (context, alarmService, child) {
        final allAlarms = alarmService.activeAlarms;
        final autoAlarms = allAlarms.where((a) => a.isAutoAlarm).toList();
        final manualAlarms = allAlarms.where((a) => !a.isAutoAlarm).toList();

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: () => alarmService.refreshAlarms(),
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
              ),
              if (allAlarms.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Text("활성화된 알람이 없습니다.",
                        style: TextStyle(color: Colors.grey)),
                  ),
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (autoAlarms.isNotEmpty)
                      _buildAutoAlarmSection(autoAlarms),
                    if (manualAlarms.isNotEmpty)
                      _buildManualAlarmList(context, manualAlarms),
                  ],
                ),
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
            itemBuilder: (context, index) {
              return _buildAutoAlarmItem(alarms[index]);
            },
          ),
        ),
        const Divider(height: 32),
      ],
    );
  }

  Widget _buildAutoAlarmItem(AlarmData alarm) {
    final key = '${alarm.busNo}_${alarm.stationName}_${alarm.routeId}';
    final fullAlarm = _fullAutoAlarms[key];
    if (fullAlarm == null) {
      return const SizedBox.shrink(); // Or a placeholder
    }

    final time = fullAlarm.getFormattedTime();
    final days = _getRepeatDaysText(fullAlarm.repeatDays);

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              fullAlarm.routeNo,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            Text(
              fullAlarm.stationName,
              style: const TextStyle(fontSize: 12),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
            const Spacer(),
            Row(
              children: [
                const Icon(Icons.alarm, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(time, style: const TextStyle(fontSize: 14)),
              ],
            ),
            Text(
              days,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
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
      itemBuilder: (context, index) {
        return _buildManualAlarmItem(context, alarms[index]);
      },
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
            color: Colors.grey.withOpacity(0.1),
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
            child: Icon(
              Icons.directions_bus,
              color: Colors.blue.shade600,
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  alarm.stationName,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
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
                  color: _getRemainingTimeColor(alarm),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '남은 시간',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade500,
                ),
              ),
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

  String _getRemainingTimeText(AlarmData alarm) {
    final now = DateTime.now();
    final remaining = alarm.scheduledTime.difference(now);

    if (remaining.isNegative || remaining.inMinutes == 0) {
      return '곧 도착';
    }
    return '${remaining.inMinutes}분';
  }

  Color _getRemainingTimeColor(AlarmData alarm) {
    final now = DateTime.now();
    final remaining = alarm.scheduledTime.difference(now);

    if (remaining.inMinutes < 1) {
      return Colors.red.shade600;
    } else if (remaining.inMinutes < 5) {
      return Colors.orange.shade700;
    } else {
      return Colors.blue;
    }
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
