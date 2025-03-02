import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bus_arrival.dart';
import '../services/alarm_service.dart';

class CompactBusCard extends StatefulWidget {
  final BusArrival busArrival;
  final VoidCallback onTap;

  const CompactBusCard({
    super.key,
    required this.busArrival,
    required this.onTap,
  });

  @override
  State<CompactBusCard> createState() => _CompactBusCardState();
}

class _CompactBusCardState extends State<CompactBusCard> {
  bool _cacheUpdated = false;

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
    final arrivalTimeText =
        remainingMinutes <= 0 ? '곧 도착' : '$remainingMinutes분';

    // 한 번만 캐시 업데이트 실행
    if (!_cacheUpdated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final alarmService = Provider.of<AlarmService>(context, listen: false);
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

              const Spacer(),

              // 현재 정류소 및 남은 정류소
              Expanded(
                flex: 2,
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

              const SizedBox(width: 8),

              // 도착 예정 시간
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '도착예정',
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
                      color:
                          remainingMinutes <= 3 ? Colors.red : Colors.blue[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
