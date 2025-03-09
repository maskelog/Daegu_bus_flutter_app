import 'package:daegu_bus_app/services/notification_service.dart';
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
        final isTracking = alarmService.isInTrackingMode;

        // 트래킹 중이고 알람이 없는 경우 트래킹 정보만 표시
        if (isTracking && activeAlarms.isEmpty) {
          return Container(
            width: double.infinity,
            color: Colors.blue[50], // 트래킹 모드 색상
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: Row(
              children: [
                Icon(Icons.location_on, color: Colors.blue[700]),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '버스 위치 실시간 추적 중',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.blue,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.stop_circle, color: Colors.red),
                  iconSize: 20,
                  onPressed: () async {
                    // 트래킹 모드 중지 및 알림 취소
                    await alarmService.stopBusMonitoringService();
                    // 관련 알림 취소
                    await NotificationService().cancelOngoingTracking();
                    // 사용자에게 피드백 제공
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('버스 추적이 중지되었습니다'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  tooltip: '추적 중지',
                ),
              ],
            ),
          );
        }

        // 알람이 없는 경우 기본 표시
        if (activeAlarms.isEmpty) {
          return Container(
            width: double.infinity,
            color: Colors.yellow[50],
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
              // 알람 목록
              ...activeAlarms.map(
                (alarm) {
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
                          color:
                              arrivalMinutes <= 3 ? Colors.red : Colors.orange,
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
                          onTap: () async {
                            // 취소 확인 다이얼로그 표시
                            bool? confirmDelete = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('알람 취소'),
                                content:
                                    Text('${alarm.busNo}번 버스 알람을 취소하시겠습니까?'),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(false),
                                    child: const Text('취소'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(true),
                                    child: const Text('확인'),
                                  ),
                                ],
                              ),
                            );

                            // 사용자가 확인을 선택한 경우
                            if (confirmDelete == true && context.mounted) {
                              // 알람 취소 (cancelAlarmByRoute 사용)
                              final success =
                                  await alarmService.cancelAlarmByRoute(
                                alarm.busNo,
                                alarm.stationName,
                                alarm.routeId,
                              );

                              // 남은 알람이 없으면 버스 추적 서비스도 중지
                              if (success) {
                                // 모든 관련 알림 취소 확인
                                await NotificationService()
                                    .cancelNotification(alarm.getAlarmId());
                                await NotificationService()
                                    .cancelOngoingTracking();

                                // 알람 목록 즉시 새로고침
                                await alarmService.loadAlarms();

                                // 남은 알람이 없으면 추적 서비스도 중지
                                if (alarmService.activeAlarms.isEmpty) {
                                  await alarmService.stopBusMonitoringService();
                                }

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                          '${alarm.busNo}번 버스 알람이 취소되었습니다'),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              }
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(8.0),
                            child: Icon(
                              Icons.close,
                              color: Colors.red[700],
                              size: 20,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 17),
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
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
