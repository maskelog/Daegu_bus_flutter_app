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

      // 자동 알람인지 확인하고 취소
      final hasAutoAlarm = _alarmService.hasAutoAlarm(
        alarm.busNo,
        alarm.stationName,
        alarm.routeId,
      );

      if (hasAutoAlarm) {
        print('🐛 [DEBUG] 자동 알람 취소: ${alarm.busNo}번 버스');
        await _alarmService.stopAutoAlarm(
          alarm.busNo,
          alarm.stationName,
          alarm.routeId,
        );
      }

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

      // 모든 자동 알람 취소
      for (final alarm in _activeAlarms) {
        final hasAutoAlarm = _alarmService.hasAutoAlarm(
          alarm.busNo,
          alarm.stationName,
          alarm.routeId,
        );
        if (hasAutoAlarm) {
          await _alarmService.stopAutoAlarm(
            alarm.busNo,
            alarm.stationName,
            alarm.routeId,
          );
        }
      }

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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더 (새로고침, 모든 알람 취소 버튼)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                onPressed: _loadActiveAlarms,
                icon: const Icon(Icons.refresh, color: Colors.grey),
                tooltip: '새로고침',
                iconSize: 20,
              ),
              IconButton(
                onPressed: _cancelAllAlarms,
                icon: const Icon(Icons.clear_all, color: Colors.red),
                tooltip: '모든 알람 취소',
                iconSize: 20,
              ),
            ],
          ),

          // 로딩 상태 또는 알람 목록
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 버스 아이콘 (자동 알람 구분)
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isAutoAlarm(alarm)
                  ? Colors.orange.shade50
                  : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _isAutoAlarm(alarm) ? Icons.schedule : Icons.directions_bus,
              color: _isAutoAlarm(alarm)
                  ? Colors.orange.shade600
                  : Colors.blue.shade600,
              size: 24,
            ),
          ),

          const SizedBox(width: 12),

          // 버스 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${alarm.busNo}번 버스',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    if (_isAutoAlarm(alarm)) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Text(
                          '자동',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ),
                    ],
                  ],
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

          // 남은 시간 표시
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

          // 취소 버튼
          IconButton(
            onPressed: () => _cancelSpecificAlarm(alarm),
            icon: const Icon(Icons.close),
            color: Colors.grey.shade600,
            tooltip: '알람 취소',
            iconSize: 20,
          ),
        ],
      ),
    );
  }

  // 남은 시간 텍스트 반환
  String _getRemainingTimeText(AlarmInfo alarm) {
    try {
      // 자동 알람인 경우 예약된 시간까지의 남은 시간 표시
      if (_isAutoAlarm(alarm)) {
        final autoAlarm = _alarmService.getAutoAlarm(
          alarm.busNo,
          alarm.stationName,
          alarm.routeId,
        );
        if (autoAlarm != null) {
          final now = DateTime.now();
          final remainingMinutes =
              autoAlarm.scheduledTime.difference(now).inMinutes;

          if (remainingMinutes <= 0) {
            return '실행 중';
          } else if (remainingMinutes == 1) {
            return '1분 후';
          } else if (remainingMinutes < 60) {
            return '$remainingMinutes분 후';
          } else {
            final hours = remainingMinutes ~/ 60;
            final minutes = remainingMinutes % 60;
            return '$hours시간 $minutes분 후';
          }
        }
      }

      // 일반 알람의 경우 실시간 버스 정보 표시
      final busInfo =
          _alarmService.getCachedBusInfo(alarm.busNo, alarm.routeId);
      if (busInfo != null) {
        final minutes = busInfo.remainingMinutes;
        if (minutes <= 0) {
          return '곧 도착';
        } else if (minutes == 1) {
          return '1분';
        } else {
          return '$minutes분';
        }
      }

      // 캐시된 정보가 없으면 알람 생성 시간 기준으로 추정
      final now = DateTime.now();
      final createdTime = alarm.createdAt;
      final elapsedMinutes = now.difference(createdTime).inMinutes;

      final estimatedMinutes = (10 - elapsedMinutes).clamp(0, 15);

      if (estimatedMinutes <= 0) {
        return '곧 도착';
      } else if (estimatedMinutes == 1) {
        return '1분';
      } else {
        return '$estimatedMinutes분';
      }
    } catch (e) {
      return '정보 없음';
    }
  }

  // 남은 시간에 따른 색상 반환
  Color _getRemainingTimeColor(AlarmInfo alarm) {
    final timeText = _getRemainingTimeText(alarm);

    // 자동 알람인 경우 오렌지 계열 색상 사용
    if (_isAutoAlarm(alarm)) {
      if (timeText == '실행 중') {
        return Colors.red;
      } else if (timeText.contains('1분') ||
          timeText.contains('2분') ||
          timeText.contains('3분')) {
        return Colors.orange.shade700;
      } else {
        return Colors.orange.shade600;
      }
    }

    // 일반 알람인 경우 기존 색상 사용
    if (timeText == '곧 도착') {
      return Colors.red;
    } else if (timeText.contains('1분') ||
        timeText.contains('2분') ||
        timeText.contains('3분')) {
      return Colors.orange;
    } else {
      return Colors.blue;
    }
  }

  // 자동 알람인지 확인
  bool _isAutoAlarm(AlarmInfo alarm) {
    return _alarmService.hasAutoAlarm(
      alarm.busNo,
      alarm.stationName,
      alarm.routeId,
    );
  }
}
