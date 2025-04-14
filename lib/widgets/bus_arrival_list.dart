import 'package:flutter/material.dart';
import '../models/bus_arrival.dart';
import '../models/bus_stop.dart';
import 'compact_bus_card.dart';

class BusArrivalList extends StatelessWidget {
  final List<BusArrival> arrivals;
  final BusStop? station;
  final Function(BusArrival) onTap;
  final Function(BusArrival) onAlarmSet;
  final bool isLoading;
  final String? errorMessage;

  const BusArrivalList({
    super.key,
    required this.arrivals,
    this.station,
    required this.onTap,
    required this.onAlarmSet,
    this.isLoading = false,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red[700]),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                // 다시 시도 콜백이 있다면 여기서 호출
              },
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (arrivals.isEmpty) {
      return const Center(
        child: Text('도착 예정 버스가 없습니다'),
      );
    }

    // 스크롤 가능한 리스트로 변경
    return Scrollbar(
      thickness: 6.0,
      radius: const Radius.circular(10),
      child: ListView.builder(
        padding: EdgeInsets.zero,
        itemCount: arrivals.length,
        itemBuilder: (context, index) {
          return CompactBusCard(
            busArrival: arrivals[index],
            onTap: () => onTap(arrivals[index]),
          );
        },
      ),
    );
  }
}

class BusArrivalItem extends StatelessWidget {
  final BusArrival arrival;
  final VoidCallback onTap;

  const BusArrivalItem({
    super.key,
    required this.arrival,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // 첫 번째 버스 정보 추출
    final firstBus = arrival.busInfoList.isNotEmpty ? arrival.busInfoList.first : null;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
          ),
        ),
        child: Row(
          children: [
            // 버스 번호
            Container(
              width: 60,
              alignment: Alignment.center,
              child: Text(
                arrival.routeNo,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: firstBus?.isOutOfService == true
                      ? Colors.grey
                      : Colors.blue.shade600,
                ),
              ),
            ),

            // 저상 버스 표시
            if (firstBus != null && firstBus.isLowFloor)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.green.shade100,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '저상',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.green.shade700,
                  ),
                ),
              ),

            const SizedBox(width: 16),

            // 현재 정류소 및 남은 정류소
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (firstBus != null)
                    Text(
                      firstBus.currentStation,
                      style: const TextStyle(
                        fontSize: 14,
                      ),
                    ),
                  if (firstBus != null)
                    Text(
                      firstBus.isOutOfService
                          ? '운행종료'
                          : firstBus.remainingStops,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                ],
              ),
            ),

            // 도착 예정 시간
            Container(
              width: 60,
              alignment: Alignment.center,
              child: Column(
                children: [
                  Text(
                    firstBus?.isOutOfService == true ? '버스 상태' : '도착예정',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (firstBus != null)
                    Text(
                      firstBus.isOutOfService ? '운행종료' : '${firstBus.getRemainingMinutes()}분',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: firstBus.isOutOfService
                            ? Colors.grey
                            : (firstBus.getRemainingMinutes() <= 3
                                ? Colors.red
                                : Colors.blue.shade600),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
