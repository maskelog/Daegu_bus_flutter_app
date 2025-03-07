import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bus_arrival.dart';
import '../services/alarm_service.dart';

class CompactBusCard extends StatefulWidget {
  final BusArrival busArrival;
  final VoidCallback onTap;
  final String? stationName; // 정류장 이름 추가

  const CompactBusCard({
    super.key,
    required this.busArrival,
    required this.onTap,
    this.stationName, // 정류장 이름 매개변수 추가
  });

  @override
  State<CompactBusCard> createState() => _CompactBusCardState();
}

class _CompactBusCardState extends State<CompactBusCard> {
  bool _cacheUpdated = false;
  final int defaultPreNotificationMinutes = 3; // 기본 알람 시간 (분)

  @override
  Widget build(BuildContext context) {
    // 첫 번째 버스 정보 추출
    final firstBus = widget.busArrival.buses.isNotEmpty
        ? widget.busArrival.buses.first
        : null;

    // 아무 버스도 없을 때
    if (firstBus == null) {
      return const SizedBox.shrink();
    }

    // 남은 시간 계산
    final remainingMinutes = firstBus.getRemainingMinutes();

    // 버스 상태에 따른 도착 정보 텍스트 설정
    String arrivalTimeText;
    Color arrivalTextColor;

    if (firstBus.isOutOfService == true) {
      // 운행 종료된 경우
      arrivalTimeText = '운행종료';
      arrivalTextColor = Colors.grey;
    } else if (remainingMinutes <= 0) {
      // 도착 임박한 경우
      arrivalTimeText = '곧 도착';
      arrivalTextColor = Colors.red;
    } else {
      // 일반적인 경우
      arrivalTimeText = '$remainingMinutes분';
      arrivalTextColor = remainingMinutes <= 3 ? Colors.red : Colors.blue[600]!;
    }

    // 알람 서비스 가져오기
    final alarmService = Provider.of<AlarmService>(context);

    // 현재 알람 상태 확인
    final bool hasAlarm = widget.stationName != null &&
        alarmService.hasAlarm(
          widget.busArrival.routeNo,
          widget.stationName!,
          widget.busArrival.routeId,
        );

    // 한 번만 캐시 업데이트 실행
    if (!_cacheUpdated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        alarmService.updateBusInfoCache(widget.busArrival.routeNo,
            widget.busArrival.routeId, firstBus, remainingMinutes);
        _cacheUpdated = true; // 플래그 설정
      });
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      elevation: 0,
      color: Colors.grey[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[200]!, width: 1),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 위치 아이콘
              Icon(Icons.location_on, size: 18, color: Colors.grey[500]),
              const SizedBox(width: 8),

              // 버스 번호
              Text(
                widget.busArrival.routeNo,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[600],
                ),
              ),

              // 저상 버스 뱃지
              if (firstBus.isLowFloor)
                Container(
                  margin: const EdgeInsets.only(left: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '저상',
                    style: TextStyle(
                      color: Colors.green[700],
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

              const SizedBox(width: 8),

              // 현재 정류소 및 남은 정류소
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      firstBus.currentStation,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      firstBus.remainingStops,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              ),

              // 도착 예정 시간
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    firstBus.isOutOfService == true ? '' : '도착예정',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    arrivalTimeText,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: arrivalTextColor,
                    ),
                  ),
                ],
              ),

              // 알람 버튼 (정류장 이름이 있는 경우에만 표시, 운행 종료 시 비활성화)
              if (widget.stationName != null && firstBus.isOutOfService != true)
                IconButton(
                  icon: Icon(
                    hasAlarm
                        ? Icons.notifications_active
                        : Icons.notifications_none,
                    color: hasAlarm ? Colors.amber : Colors.grey,
                  ),
                  onPressed: () => _setAlarm(firstBus, remainingMinutes),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 알람 설정 메서드
// 알람 설정 메서드
  void _setAlarm(BusInfo busInfo, int remainingMinutes) async {
    // 정류장 이름이 없으면 알람을 설정할 수 없음
    if (widget.stationName == null) return;

    final alarmService = Provider.of<AlarmService>(context, listen: false);
    // NotificationService 인스턴스 생성
    final notificationService = NotificationService();
    await notificationService.initialize();

    // 현재 알람 상태 확인
    bool hasAlarm = alarmService.hasAlarm(
      widget.busArrival.routeNo,
      widget.stationName!,
      widget.busArrival.routeId,
    );

    if (hasAlarm) {
      // 이미 알람이 설정되어 있으면 취소
      await alarmService.cancelAlarmByRoute(
        widget.busArrival.routeNo,
        widget.stationName!,
        widget.busArrival.routeId,
      );

      // 실시간 추적 알림도 함께 취소
      await notificationService.cancelOngoingTracking();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('승차 알람이 취소되었습니다')),
        );
      }
    } else {
      // 새 알람 설정
      if (remainingMinutes > 0) {
        // 알람 ID 생성
        int alarmId = alarmService.getAlarmId(
          widget.busArrival.routeNo,
          widget.stationName!,
          routeId: widget.busArrival.routeId,
        );

        // 도착 예정 시간 계산
        DateTime arrivalTime =
            DateTime.now().add(Duration(minutes: remainingMinutes));

        bool success = await alarmService.setOneTimeAlarm(
          id: alarmId,
          alarmTime: arrivalTime,
          preNotificationTime: Duration(minutes: defaultPreNotificationMinutes),
          busNo: widget.busArrival.routeNo,
          stationName: widget.stationName!,
          remainingMinutes: remainingMinutes,
          routeId: widget.busArrival.routeId,
          currentStation: busInfo.currentStation,
          busInfo: busInfo,
        );

        if (success && mounted) {
          // 알람 설정 성공 시 실시간 추적 알림 시작
          await notificationService.showOngoingBusTracking(
            busNo: widget.busArrival.routeNo,
            stationName: widget.stationName!,
            remainingMinutes: remainingMinutes,
            currentStation: busInfo.currentStation,
          );

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('승차 알람이 설정되었습니다')),
          );
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('승차 알람 설정에 실패했습니다')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('버스가 이미 도착했거나 곧 도착합니다')),
          );
        }
      }
    }
  }

  @override
  void didUpdateWidget(CompactBusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 버스 정보가 변경되었을 때만 캐시 업데이트 플래그 재설정
    if (oldWidget.busArrival.routeNo != widget.busArrival.routeNo ||
        oldWidget.busArrival.routeId != widget.busArrival.routeId) {
      _cacheUpdated = false;
    }
  }
}
