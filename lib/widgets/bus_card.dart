import 'dart:async';
import 'package:flutter/material.dart';
import '../models/bus_arrival.dart';
import '../utils/alarm_helper.dart';
import '../utils/notification_helper.dart';

class BusCard extends StatefulWidget {
  final BusArrival busArrival;
  final VoidCallback onTap;
  final String? stationName;

  const BusCard({
    super.key,
    required this.busArrival,
    required this.onTap,
    this.stationName,
  });

  @override
  State<BusCard> createState() => _BusCardState();
}

class _BusCardState extends State<BusCard> {
  bool alarmEnabled = false;
  int selectedAlarmTime = 3; // 기본 알람 시간 (분)
  Timer? _timer;
  late BusInfo firstBus;
  int remainingTime = 0;

  @override
  void initState() {
    super.initState();

    // 첫 번째 버스 정보 저장
    if (widget.busArrival.buses.isNotEmpty) {
      firstBus = widget.busArrival.buses.first;
      remainingTime = firstBus.getRemainingMinutes();

      // 1분마다 남은 시간 업데이트
      _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
        if (mounted) {
          setState(() {
            if (remainingTime > 0) {
              remainingTime--;
            }

            // 알람 설정되어 있고, 남은 시간이 선택한 알람 시간 이하면 알람 실행
            if (alarmEnabled &&
                remainingTime <= selectedAlarmTime &&
                remainingTime > 0) {
              _playAlarm();
              alarmEnabled = false; // 알람 울린 후 비활성화
            }
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _playAlarm() {
    NotificationHelper.showNotification(
      id: 1,
      title: '버스 도착 알림',
      body: '${widget.busArrival.routeNo}번 버스가 $selectedAlarmTime분 이내에 도착합니다!',
    );
  }

  void _showAlarmModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '알람 설정',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [3, 5, 10]
                        .map((time) => ElevatedButton(
                              onPressed: () {
                                setModalState(() {
                                  selectedAlarmTime = time;
                                });
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: selectedAlarmTime == time
                                    ? Colors.blue
                                    : Colors.grey[200],
                                foregroundColor: selectedAlarmTime == time
                                    ? Colors.white
                                    : Colors.black,
                              ),
                              child: Text('$time분 전'),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              alarmEnabled = true;

                              // AlarmManager를 이용한 알람 설정
                              if (remainingTime > selectedAlarmTime) {
                                int alarmId =
                                    widget.busArrival.routeId.hashCode;
                                DateTime arrivalTime = DateTime.now().add(
                                  Duration(minutes: remainingTime),
                                );

                                AlarmHelper.setOneTimeAlarm(
                                  id: alarmId,
                                  alarmTime: arrivalTime,
                                  preNotificationTime:
                                      Duration(minutes: selectedAlarmTime),
                                );
                              }
                            });
                            Navigator.pop(context);
                          },
                          child: const Text('확인'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.busArrival.buses.isEmpty) {
      return const Card(
        margin: EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text('도착 정보가 없습니다.'),
          ),
        ),
      );
    }

    // 첫 번째 버스와 두 번째 버스 정보 추출
    firstBus = widget.busArrival.buses.first;
    BusInfo? nextBus =
        widget.busArrival.buses.length > 1 ? widget.busArrival.buses[1] : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
          padding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: 180,
              maxHeight: 250,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_on, color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.busArrival.routeNo}번 버스 - ${widget.stationName ?? "정류장 정보 없음"}',
                        style: const TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 버스 번호와 저상 버스 표시
                Row(
                  children: [
                    Text(
                      widget.busArrival.routeNo,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[500],
                      ),
                    ),
                    if (firstBus.isLowFloor)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.green[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '저상',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    Expanded(
                      child: Text(
                        firstBus.currentStation,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 진행 상황 바
                LinearProgressIndicator(
                  value: 0.6, // 진행 상황 표시 (실제로는 계산 필요)
                  backgroundColor: Colors.grey[200],
                  color: Colors.blue[500],
                  borderRadius: BorderRadius.circular(4),
                ),

                const SizedBox(height: 12),

                // 도착 정보 및 알람 버튼
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '도착예정',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                          ),
                        ),
                        Text(
                          '$remainingTime분',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: remainingTime <= 3
                                ? Colors.red
                                : Colors.blue[600],
                          ),
                        ),
                      ],
                    ),

                    // 다음 버스 도착 정보
                    if (nextBus != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '다음 버스',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            nextBus.arrivalTime,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),

                    // 알람 버튼
                    ElevatedButton.icon(
                      onPressed: _showAlarmModal,
                      icon: Icon(
                        Icons.notifications,
                        color: alarmEnabled ? Colors.yellow : Colors.white,
                        size: 18,
                      ),
                      label: Text(
                        alarmEnabled ? '알람 켜짐' : '알람 설정',
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:
                            alarmEnabled ? Colors.blue[700] : Colors.blue,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 0),
                        minimumSize: const Size(80, 36),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
