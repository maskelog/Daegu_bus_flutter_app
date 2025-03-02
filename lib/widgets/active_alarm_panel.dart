import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/alarm_service.dart';

class ActiveAlarmPanel extends StatefulWidget {
  const ActiveAlarmPanel({super.key});

  @override
  State<ActiveAlarmPanel> createState() => _ActiveAlarmPanelState();
}

class _ActiveAlarmPanelState extends State<ActiveAlarmPanel> {
  @override
  void initState() {
    super.initState();
    // 컴포넌트 마운트 시 알람 데이터 최신화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final alarmService = Provider.of<AlarmService>(context, listen: false);
      alarmService.loadAlarms();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AlarmService>(
      builder: (context, alarmService, child) {
        final activeAlarms = alarmService.activeAlarms;

        // 알람이 없는 경우 최소 높이 유지
        if (activeAlarms.isEmpty) {
          return Container(
            width: double.infinity,
            color: Colors.yellow[50], // 더 밝은 색상으로 변경
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: const Center(
              child: Text(
                '예약된 알람이 없습니다.',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          );
        }

        // 알람이 있는 경우
        return Container(
          width: double.infinity,
          color: Colors.yellow[100],
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더 추가
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '승차 알람',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  // 새로고침 버튼 추가
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      debugPrint("알람 목록 새로고침 요청");
                      alarmService.loadAlarms();
                    },
                    tooltip: '알람 목록 새로고침',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // 알람 목록
              ...activeAlarms.map((alarm) {
                // 캐시된 정보를 가져와서 최신화
                final cachedBusInfo = alarmService.getCachedBusInfo(
                  alarm.busNo,
                  alarm.routeId,
                );

                // 남은 시간 계산 - 캐시된 정보가 있으면 해당 값 사용, 없으면 알람 모델의 값 사용
                int arrivalMinutes;
                if (cachedBusInfo != null) {
                  arrivalMinutes = cachedBusInfo.getRemainingMinutes();
                } else {
                  arrivalMinutes = alarm.getCurrentArrivalMinutes();
                }

                final arrivalText =
                    arrivalMinutes <= 1 ? '곧 도착' : '$arrivalMinutes분 후 도착';

                // 버스 현재 위치 정보 (캐시에서 최신 정보 가져오기)
                String? currentStation =
                    cachedBusInfo?.currentStation ?? alarm.currentStation;
                String locationText = '';
                if (currentStation != null && currentStation.isNotEmpty) {
                  locationText = ' ($currentStation)';
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.alarm,
                        color: arrivalMinutes <= 3 ? Colors.red : Colors.orange,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${alarm.busNo}번 버스 - ${alarm.stationName}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$arrivalText$locationText',
                              style: TextStyle(
                                fontSize: 14,
                                color: arrivalMinutes <= 3
                                    ? Colors.red
                                    : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // 알람 취소 버튼
                      GestureDetector(
                        onTap: () => _cancelAlarm(context, alarm, alarmService),
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Icon(
                            Icons.close,
                            color: Colors.red[700],
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  // 알람 취소 함수 - 알람 서비스를 매개변수로 받도록 수정
  Future<void> _cancelAlarm(
      BuildContext context, AlarmData alarm, AlarmService alarmService) async {
    // 취소 확인 다이얼로그 표시
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('알람 취소'),
        content: Text('${alarm.busNo}번 버스 알람을 취소하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('확인'),
          ),
        ],
      ),
    );

    // 확인 버튼을 눌렀을 때
    if (confirmDelete == true && context.mounted) {
      try {
        debugPrint('알람 취소 시도: ${alarm.busNo}, ID: ${alarm.getAlarmId()}');

        // 알람 취소 실행
        final success = await alarmService.cancelAlarm(alarm.getAlarmId());

        if (success && context.mounted) {
          // 완료 메시지 표시
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${alarm.busNo}번 버스 알람이 취소되었습니다'),
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (context.mounted) {
          // 실패 메시지 표시
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('알람 취소 중 오류가 발생했습니다'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      } catch (e) {
        // 예외 발생 시 로그 출력 및 메시지 표시
        debugPrint('알람 취소 오류: $e');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('알람 취소 중 오류가 발생했습니다: $e'),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    }
  }
}
