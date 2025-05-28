import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/alarm_manager.dart';
import '../services/alarm_service.dart';
import '../services/notification_service.dart';
import '../utils/tts_switcher.dart';

class ActiveAlarmPanel extends StatefulWidget {
  const ActiveAlarmPanel({super.key});

  @override
  State<ActiveAlarmPanel> createState() => _ActiveAlarmPanelState();
}

class _ActiveAlarmPanelState extends State<ActiveAlarmPanel>
    with SingleTickerProviderStateMixin {
  List<AlarmInfo> _activeAlarms = [];
  bool _isLoading = false;
  late AnimationController _progressController;
  late AlarmService _alarmService;
  late NotificationService _notificationService;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30), // Approximate bus arrival window
    )..addListener(() {
        if (mounted) setState(() {});
      });
    _alarmService = Provider.of<AlarmService>(context, listen: false);
    _notificationService = NotificationService();
    _loadActiveAlarms();
    AlarmManager.addListener(_onAlarmStateChanged);
    _alarmService.addListener(_onAlarmStateChanged);
  }

  @override
  void dispose() {
    AlarmManager.removeListener(_onAlarmStateChanged);
    _alarmService.removeListener(_onAlarmStateChanged);
    _progressController.dispose();
    super.dispose();
  }

  void _onAlarmStateChanged() {
    if (mounted) {
      _loadActiveAlarms();
    }
  }

  Future<void> _loadActiveAlarms() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // AlarmManager와 AlarmService 모두에서 알람 가져오기
      final managerAlarms = await AlarmManager.getActiveAlarms();
      final serviceAlarms = _alarmService.activeAlarms;

      // AlarmService의 알람을 AlarmInfo 형태로 변환
      final convertedServiceAlarms = serviceAlarms
          .map((alarm) => AlarmInfo(
                busNo: alarm.busNo,
                stationName: alarm.stationName,
                routeId: alarm.routeId,
                wincId: '', // AlarmService에는 wincId가 없으므로 빈 문자열
                createdAt: alarm.scheduledTime,
              ))
          .toList();

      // 중복 제거하면서 합치기 (busNo, stationName, routeId가 같으면 중복으로 간주)
      final allAlarms = <AlarmInfo>[];
      final seenKeys = <String>{};

      for (final alarm in [...managerAlarms, ...convertedServiceAlarms]) {
        final key = '${alarm.busNo}_${alarm.stationName}_${alarm.routeId}';
        if (!seenKeys.contains(key)) {
          seenKeys.add(key);
          allAlarms.add(alarm);
        }
      }

      if (mounted) {
        setState(() {
          _activeAlarms = allAlarms;
          _isLoading = false;
          if (allAlarms.isNotEmpty) {
            _progressController.repeat();
          } else {
            _progressController.stop();
          }
        });
      }
      print(
          '🐛 [DEBUG] 활성 알람 목록 로드 완료: ${allAlarms.length}개 (Manager: ${managerAlarms.length}, Service: ${serviceAlarms.length})');
    } catch (e) {
      print('❌ [ERROR] 활성 알람 목록 로드 실패: $e');
      if (mounted) {
        setState(() {
          _activeAlarms = [];
          _isLoading = false;
          _progressController.stop();
        });
      }
    }
  }

  Future<void> _cancelSpecificAlarm(AlarmInfo alarm) async {
    try {
      print('🐛 [DEBUG] 특정 알람 취소 요청: ${alarm.busNo}번 버스, ${alarm.stationName}');

      setState(() {
        _activeAlarms.removeWhere((a) =>
            a.busNo == alarm.busNo &&
            a.stationName == alarm.stationName &&
            a.routeId == alarm.routeId);
      });

      // AlarmManager에서 알람 취소
      await AlarmManager.cancelAlarm(
        busNo: alarm.busNo,
        stationName: alarm.stationName,
        routeId: alarm.routeId,
      );

      // AlarmService에서도 알람 취소
      final success = await _alarmService.cancelAlarmByRoute(
        alarm.busNo,
        alarm.stationName,
        alarm.routeId,
      );

      if (success) {
        // 포그라운드 알림 취소
        await _notificationService.cancelOngoingTracking();

        // TTS 추적 중단
        await TtsSwitcher.stopTtsTracking(alarm.busNo);

        // 버스 모니터링 서비스 중지
        await _alarmService.stopBusMonitoringService();

        // 알람 상태 갱신
        await _alarmService.loadAlarms();
        await _alarmService.refreshAlarms();
      }

      await _stopSpecificNativeTracking(alarm);

      print('🐛 [DEBUG] ✅ 특정 알람 취소 완료: ${alarm.busNo}번 버스');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${alarm.busNo}번 버스 알람이 취소되었습니다.'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ [ERROR] 특정 알람 취소 실패: $e');
      await _loadActiveAlarms();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('알람 취소 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _cancelAllAlarms() async {
    if (_activeAlarms.isEmpty) {
      print('🐛 [DEBUG] 취소할 활성 알람이 없음');
      return;
    }

    final confirmed = await _showCancelAllDialog();
    if (!confirmed) return;

    try {
      print('🐛 [DEBUG] 모든 알람 취소 요청: ${_activeAlarms.length}개');

      setState(() {
        _activeAlarms.clear();
        _progressController.stop();
      });

      await AlarmManager.cancelAllAlarms();
      await _stopAllNativeTracking();

      print('🐛 [DEBUG] ✅ 모든 알람 취소 완료');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('모든 알람이 취소되었습니다.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print('❌ [ERROR] 모든 알람 취소 실패: $e');
      await _loadActiveAlarms();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('모든 알람 취소 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _stopSpecificNativeTracking(AlarmInfo alarm) async {
    try {
      const platform = MethodChannel('com.example.daegu_bus_app/notification');
      await platform.invokeMethod('stopSpecificTracking', {
        'busNo': alarm.busNo,
        'routeId': alarm.routeId,
        'stationName': alarm.stationName,
      });
      print('🐛 [DEBUG] ✅ 네이티브 특정 추적 중지 요청 완료: ${alarm.busNo}');
    } catch (e) {
      print('❌ [ERROR] 네이티브 특정 추적 중지 실패: $e');
    }
  }

  Future<void> _stopAllNativeTracking() async {
    try {
      const platform = MethodChannel('com.example.daegu_bus_app/notification');
      await platform.invokeMethod('stopBusTrackingService');
      print('🐛 [DEBUG] ✅ 네이티브 모든 추적 중지 요청 완료');
    } catch (e) {
      print('❌ [ERROR] 네이티브 모든 추적 중지 실패: $e');
    }
  }

  Future<bool> _showCancelAllDialog() async {
    return await showDialog<bool>(
          context: context,
          builder: (BuildContext context) {
            return AlertDialog(
              title: const Text('모든 알람 취소'),
              content:
                  Text('현재 설정된 ${_activeAlarms.length}개의 알람을 모두 취소하시겠습니까?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('취소'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('모두 취소'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    // 활성 알람이 없으면 아무것도 표시하지 않음
    if (_activeAlarms.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _loadActiveAlarms,
                      icon: Icon(Icons.refresh, color: Colors.blue.shade700),
                      tooltip: '새로고침',
                    ),
                    IconButton(
                      onPressed: _cancelAllAlarms,
                      icon: Icon(Icons.clear_all, color: Colors.red.shade700),
                      tooltip: '모든 알람 취소',
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: _activeAlarms.length,
              itemBuilder: (context, index) {
                final alarm = _activeAlarms[index];
                return _buildAlarmItem(alarm);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAlarmItem(AlarmInfo alarm) {
    // Assume remaining time is fetched or approximated; here we use a placeholder
    // In a real app, integrate with BusCard's remainingTime via AlarmManager or API
    final double progress =
        _progressController.value; // Placeholder for animation
    final isArrivingSoon = progress > 0.8; // Simulate nearing arrival

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.directions_bus,
                    color: isArrivingSoon ? Colors.red : Colors.blue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${alarm.busNo}번 버스',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        alarm.stationName,
                        style:
                            const TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                onPressed: () => _cancelSpecificAlarm(alarm),
                icon: const Icon(Icons.alarm_off),
                color: Colors.red,
                tooltip: '알람 취소',
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (alarm.routeId.isNotEmpty)
            Text(
              '노선 ID: ${alarm.routeId}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          const SizedBox(height: 8),
          Stack(
            children: [
              Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: MediaQuery.of(context).size.width * progress * 0.85,
                height: 6,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isArrivingSoon
                        ? [Colors.red, Colors.orange]
                        : [Colors.blue, Colors.lightBlue],
                  ),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Positioned(
                left: MediaQuery.of(context).size.width * progress * 0.85 - 8,
                top: -4,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: isArrivingSoon ? Colors.red : Colors.blue,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.white.withAlpha(77),
                        blurRadius: 2,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.directions_bus,
                    color: Colors.white,
                    size: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isArrivingSoon ? '곧 도착' : '도착 예정',
            style: TextStyle(
              fontSize: 12,
              color: isArrivingSoon ? Colors.red : Colors.grey,
            ),
          ),
        ],
      ),
    );
  }
}
