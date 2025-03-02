import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bus_arrival.dart';
import '../services/alarm_service.dart';
import '../utils/notification_helper.dart';
import '../utils/tts_helper.dart';

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
  bool hasBoarded = false; // 승차 여부
  final int defaultPreNotificationMinutes = 3; // 기본 승차 알람 시간 (분)
  Timer? _timer;
  late BusInfo firstBus;
  int remainingTime = 0;

  @override
  void initState() {
    super.initState();

    if (widget.busArrival.buses.isNotEmpty) {
      firstBus = widget.busArrival.buses.first;
      remainingTime = firstBus.getRemainingMinutes();

      // 초기값 설정 시에도 AlarmService 캐시 업데이트
      _updateAlarmServiceCache();

      // 30초마다 남은 시간을 업데이트 (더 빠른 업데이트)
      _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (!mounted) return;
        setState(() {
          // 남은 시간 업데이트 - API 데이터 기반
          if (remainingTime > 0) {
            remainingTime = firstBus.getRemainingMinutes();

            debugPrint('BusCard - Remaining Time: $remainingTime');
            debugPrint('BusCard - Current Time: ${DateTime.now()}');

            // AlarmService의 캐시에 최신 도착 정보 업데이트
            _updateAlarmServiceCache();

            // 알람 체크 및 작동
            final alarmService =
                Provider.of<AlarmService>(context, listen: false);
            final bool hasAlarm = alarmService.hasAlarm(
              widget.busArrival.routeNo,
              widget.stationName ?? '정류장 정보 없음',
              widget.busArrival.routeId,
            );

            if (hasAlarm &&
                !hasBoarded &&
                remainingTime <= defaultPreNotificationMinutes &&
                remainingTime > 0) {
              _playAlarm();
            }

            // 다음 버스 알람 예약 로직 유지
            if (!hasBoarded &&
                remainingTime <= 0 &&
                widget.busArrival.buses.length > 1) {
              BusInfo nextBus = widget.busArrival.buses[1];
              int nextRemainingTime = nextBus.getRemainingMinutes();
              _setNextBusAlarm(nextRemainingTime, nextBus.currentStation);
            }
          }
        });
      });
    }
  }

  // AlarmService 캐시 업데이트를 위한 별도 메소드
  void _updateAlarmServiceCache() {
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    // 버스 정보 및 현재 남은 시간 업데이트
    alarmService.updateBusInfoCache(widget.busArrival.routeNo,
        widget.busArrival.routeId, firstBus, remainingTime);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // 알람 실행: OS 알림을 표시합니다.
  void _playAlarm() {
    // AlarmService를 사용하지만 직접 알림 표시 기능
    int alarmId = Provider.of<AlarmService>(context, listen: false).getAlarmId(
        widget.busArrival.routeNo, widget.stationName ?? '정류장 정보 없음',
        routeId: widget.busArrival.routeId);

    NotificationHelper.showNotification(
      id: alarmId,
      busNo: widget.busArrival.routeNo,
      stationName: widget.stationName ?? '정류장 정보 없음',
      remainingMinutes: defaultPreNotificationMinutes,
      currentStation: firstBus.currentStation,
    );
  }

  // 다음 버스 알람 설정
  Future<void> _setNextBusAlarm(
      int nextRemainingTime, String currentStation) async {
    final alarmService = Provider.of<AlarmService>(context, listen: false);

    DateTime arrivalTime =
        DateTime.now().add(Duration(minutes: nextRemainingTime));
    int alarmId = alarmService.getAlarmId(
        widget.busArrival.routeNo, widget.stationName ?? '정류장 정보 없음',
        routeId: widget.busArrival.routeId);

    // 다음 버스 정보도 캐시에 저장
    BusInfo nextBus = widget.busArrival.buses[1];

    bool success = await alarmService.setOneTimeAlarm(
      id: alarmId,
      alarmTime: arrivalTime,
      preNotificationTime: Duration(minutes: defaultPreNotificationMinutes),
      busNo: widget.busArrival.routeNo,
      stationName: widget.stationName ?? '정류장 정보 없음',
      remainingMinutes: nextRemainingTime,
      routeId: widget.busArrival.routeId,
      currentStation: currentStation,
      busInfo: nextBus, // 버스 정보 전달 추가
    );

    if (success) {
      // TTS 안내 (알람 설정)
      TTSHelper.speakAlarmSet(widget.busArrival.routeNo);
    }
  }

  // 승차 알람 예약
  Future<void> _setBoardingAlarm() async {
    final alarmService = Provider.of<AlarmService>(context, listen: false);

    // 현재 알람 상태 확인
    bool hasAlarm = alarmService.hasAlarm(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      widget.busArrival.routeId,
    );

    if (hasAlarm) {
      // 이미 알람이 설정되어 있으면 취소
      await alarmService.cancelAlarmByRoute(
        widget.busArrival.routeNo,
        widget.stationName ?? '정류장 정보 없음',
        widget.busArrival.routeId,
      );

      // TTS 알람 해제 안내
      TTSHelper.speakAlarmCancel(widget.busArrival.routeNo);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('승차 알람이 취소되었습니다.')),
        );
      }
      return;
    }

    // 새 알람 설정
    if (remainingTime > 0) {
      DateTime arrivalTime =
          DateTime.now().add(Duration(minutes: remainingTime));
      int alarmId = alarmService.getAlarmId(
          widget.busArrival.routeNo, widget.stationName ?? '정류장 정보 없음',
          routeId: widget.busArrival.routeId);

      bool success = await alarmService.setOneTimeAlarm(
        id: alarmId,
        alarmTime: arrivalTime,
        preNotificationTime: Duration(minutes: defaultPreNotificationMinutes),
        busNo: widget.busArrival.routeNo,
        stationName: widget.stationName ?? '정류장 정보 없음',
        remainingMinutes: remainingTime,
        routeId: widget.busArrival.routeId,
        currentStation: firstBus.currentStation,
        busInfo: firstBus, // 버스 정보 전달 추가
      );

      if (success) {
        // TTS 알람 설정 안내
        TTSHelper.speakAlarmSet(widget.busArrival.routeNo);

        // 알람 설정 후 즉시 ActiveAlarmPanel 업데이트를 위해 알람 목록 갱신 요청
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            alarmService.refreshAlarms();
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('승차 알람이 설정되었습니다.')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('승차 알람 설정에 실패했습니다.')),
        );
      }
    }
  }

  // 승차 완료 버튼: 사용자가 탑승했음을 확인하면 알람을 취소합니다.
  Widget _showBoardingButton() {
    return ElevatedButton(
      onPressed: () async {
        setState(() {
          hasBoarded = true;
        });

        // 알람 취소
        final alarmService = Provider.of<AlarmService>(context, listen: false);
        bool success = await alarmService.cancelAlarmByRoute(
          widget.busArrival.routeNo,
          widget.stationName ?? '정류장 정보 없음',
          widget.busArrival.routeId,
        );

        if (success && mounted) {
          // TTS 알람 해제 안내
          TTSHelper.speakAlarmCancel(widget.busArrival.routeNo);

          // 알람 취소 후 즉시 ActiveAlarmPanel 업데이트를 위해 알람 목록 갱신 요청
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              alarmService.refreshAlarms();
            }
          });
        }
      },
      style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
      child: const Text('승차 완료'),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.busArrival.buses.isEmpty) {
      return const Card(
        margin: EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: Text('도착 정보가 없습니다.')),
        ),
      );
    }

    // 첫 번째 버스와 두 번째 버스 정보 추출
    firstBus = widget.busArrival.buses.first;
    BusInfo? nextBus =
        widget.busArrival.buses.length > 1 ? widget.busArrival.buses[1] : null;

    // 알람 상태 확인
    final alarmService = Provider.of<AlarmService>(context);
    final bool alarmEnabled = alarmService.hasAlarm(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      widget.busArrival.routeId,
    );

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
            constraints: const BoxConstraints(minHeight: 180, maxHeight: 250),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 상단: 정류장 및 버스 정보
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Icon(Icons.location_on, color: Colors.grey, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.busArrival.routeNo}번 버스 - ${widget.stationName ?? "정류장 정보 없음"}',
                        style:
                            const TextStyle(fontSize: 18, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 버스 번호, 저상 여부, 현재 정류장 정보
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
                        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // 진행 상황 바
                LinearProgressIndicator(
                  value: 0.6,
                  backgroundColor: Colors.grey[200],
                  color: Colors.blue[500],
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 12),
                // 도착 정보 및 버튼 영역
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 도착 예정 정보
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '도착예정',
                          style: TextStyle(fontSize: 14, color: Colors.grey),
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
                        // 현재 버스 위치 (n번째 전 출발) 표시 추가
                        if (firstBus.currentStation.isNotEmpty)
                          Text(
                            '(${firstBus.currentStation})',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                    // 다음 버스 정보 (존재 시)
                    if (nextBus != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '다음 버스',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
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
                    // 승차 알람 버튼
                    ElevatedButton.icon(
                      onPressed: _setBoardingAlarm,
                      icon: Icon(
                        Icons.directions_bus,
                        color: alarmEnabled ? Colors.yellow : Colors.white,
                        size: 18,
                      ),
                      label: Text(
                        alarmEnabled ? '알람 설정됨' : '승차 알람',
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
                // 승차 알람이 울린 상태이면 승차 완료 버튼 표시
                if (alarmEnabled &&
                    !hasBoarded &&
                    remainingTime <= defaultPreNotificationMinutes)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _showBoardingButton(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
