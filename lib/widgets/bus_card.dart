import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bus_arrival.dart';
import '../services/alarm_service.dart';
import '../services/bus_api_service.dart';
import '../services/notification_service.dart';
import '../utils/tts_helper.dart';

class BusCard extends StatefulWidget {
  final BusArrival busArrival;
  final VoidCallback onTap;
  final String? stationName;
  final String stationId; // 정류장 ID

  const BusCard({
    super.key,
    required this.busArrival,
    required this.onTap,
    this.stationName,
    required this.stationId,
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
  final BusApiService _busApiService = BusApiService(); // 네이티브 API 서비스 인스턴스
  bool _isUpdating = false; // 업데이트 진행 중 플래그
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();

    if (widget.busArrival.buses.isNotEmpty) {
      firstBus = widget.busArrival.buses.first;
      remainingTime = firstBus.getRemainingMinutes();

      // 초기값 설정 시에도 AlarmService 캐시 업데이트
      _updateAlarmServiceCache();

      // 30초마다 남은 시간 업데이트 (네이티브 API를 통한 업데이트)
      _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (!mounted) return;
        _updateBusArrivalInfo();
      });
    }
  }

  // 네이티브 API를 통해 버스 도착 정보 업데이트
  Future<void> _updateBusArrivalInfo() async {
    if (_isUpdating) return;

    setState(() {
      _isUpdating = true;
    });

    try {
      final BusArrivalInfo? arrivalInfo =
          await _busApiService.getBusArrivalByRouteId(
        widget.stationId,
        widget.busArrival.routeId,
      );

      if (mounted && arrivalInfo != null && arrivalInfo.bus.isNotEmpty) {
        final BusArrival updatedBusArrival =
            _busApiService.convertToBusArrival(arrivalInfo);

        setState(() {
          if (updatedBusArrival.buses.isNotEmpty) {
            firstBus = updatedBusArrival.buses.first;
            remainingTime = firstBus.getRemainingMinutes();

            debugPrint('BusCard - 업데이트된 남은 시간: $remainingTime');

            _updateAlarmServiceCache();

            final alarmService =
                Provider.of<AlarmService>(context, listen: false);
            final bool hasAlarm = alarmService.hasAlarm(
              widget.busArrival.routeNo,
              widget.stationName ?? '정류장 정보 없음',
              widget.busArrival.routeId,
            );

            // 알람 조건에 따라 알람 실행
            if (hasAlarm &&
                !hasBoarded &&
                remainingTime <= defaultPreNotificationMinutes &&
                remainingTime > 0) {
              _playAlarm();
            }

            // 다음 버스 알람 예약 (두 번째 버스가 존재하는 경우)
            if (!hasBoarded &&
                remainingTime <= 0 &&
                updatedBusArrival.buses.length > 1) {
              BusInfo nextBus = updatedBusArrival.buses[1];
              int nextRemainingTime = nextBus.getRemainingMinutes();
              _setNextBusAlarm(nextRemainingTime, nextBus.currentStation);
            }
          }
          _isUpdating = false;
        });
      } else {
        setState(() {
          _isUpdating = false;
        });
      }
    } catch (e) {
      debugPrint('버스 도착 정보 업데이트 오류: $e');
      setState(() {
        _isUpdating = false;
      });
    }
  }

  // AlarmService 캐시 업데이트
  void _updateAlarmServiceCache() {
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    alarmService.updateBusInfoCache(
      widget.busArrival.routeNo,
      widget.busArrival.routeId,
      firstBus,
      remainingTime,
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // 알람 실행: OS 알림을 표시합니다.
  void _playAlarm() {
    int alarmId = Provider.of<AlarmService>(context, listen: false).getAlarmId(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      routeId: widget.busArrival.routeId,
    );

    _notificationService.showNotification(
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
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      routeId: widget.busArrival.routeId,
    );

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
      busInfo: nextBus,
    );

    if (success) {
      TTSHelper.speakAlarmSet(widget.busArrival.routeNo);
    }
  }

  // 승차 알람 예약 또는 해제
  Future<void> _toggleBoardingAlarm() async {
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    bool hasAlarm = alarmService.hasAlarm(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      widget.busArrival.routeId,
    );

    if (hasAlarm) {
      // 알람 해제
      bool success = await alarmService.cancelAlarmByRoute(
        widget.busArrival.routeNo,
        widget.stationName ?? '정류장 정보 없음',
        widget.busArrival.routeId,
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('승차 알람이 취소되었습니다.')),
        );

        TTSHelper.speakAlarmCancel(widget.busArrival.routeNo);

        await _notificationService.cancelOngoingTracking();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            alarmService.refreshAlarms();
          }
        });
      }
    } else {
      // 알람 예약
      if (firstBus.isOutOfService) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('운행 종료된 버스입니다.')),
          );
        }
        return;
      }

      if (remainingTime > 0) {
        int alarmId = alarmService.getAlarmId(
          widget.busArrival.routeNo,
          widget.stationName ?? '정류장 정보 없음',
          routeId: widget.busArrival.routeId,
        );
        DateTime arrivalTime =
            DateTime.now().add(Duration(minutes: remainingTime));
        bool success = await alarmService.setOneTimeAlarm(
          id: alarmId,
          alarmTime: arrivalTime,
          preNotificationTime: Duration(minutes: defaultPreNotificationMinutes),
          busNo: widget.busArrival.routeNo,
          stationName: widget.stationName ?? '정류장 정보 없음',
          remainingMinutes: remainingTime,
          routeId: widget.busArrival.routeId,
          currentStation: firstBus.currentStation,
          busInfo: firstBus,
        );

        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('승차 알람이 설정되었습니다.')),
          );

          await _notificationService.showOngoingBusTracking(
            busNo: widget.busArrival.routeNo,
            stationName: widget.stationName ?? '정류장 정보 없음',
            remainingMinutes: remainingTime,
            currentStation: firstBus.currentStation,
          );

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              alarmService.refreshAlarms();
            }
          });
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('승차 알람 설정에 실패했습니다.')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('버스가 이미 도착했거나 곧 도착합니다.')),
          );
        }
      }
    }
  }

  // 승차 완료 버튼
  Widget _showBoardingButton() {
    return ElevatedButton(
      onPressed: () async {
        setState(() {
          hasBoarded = true;
        });

        final alarmService = Provider.of<AlarmService>(context, listen: false);
        bool success = await alarmService.cancelAlarmByRoute(
          widget.busArrival.routeNo,
          widget.stationName ?? '정류장 정보 없음',
          widget.busArrival.routeId,
        );

        if (success && mounted) {
          TTSHelper.speakAlarmCancel(widget.busArrival.routeNo);
          await _notificationService.cancelOngoingTracking();

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

    // currentStationText: 버스의 현재 정류소 정보가 없으면 widget.stationName 사용
    final String currentStationText = firstBus.currentStation.trim().isNotEmpty
        ? firstBus.currentStation
        : (widget.stationName ?? "정류장 정보 없음");

    // 도착 예정 텍스트 처리
    String arrivalTimeText;
    if (firstBus.isOutOfService) {
      arrivalTimeText = '운행종료';
    } else if (remainingTime <= 0) {
      arrivalTimeText = '곧 도착';
    } else {
      arrivalTimeText = '$remainingTime분';
    }

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
                    if (_isUpdating)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // 버스 번호, 저상 여부, 현재 정류소 정보
                Row(
                  children: [
                    Text(
                      widget.busArrival.routeNo,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: firstBus.isOutOfService
                            ? Colors.grey
                            : Colors.blue[500],
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
                        currentStationText,
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
                  color:
                      firstBus.isOutOfService ? Colors.grey : Colors.blue[500],
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
                        Text(
                          firstBus.isOutOfService ? '버스 상태' : '도착예정',
                          style:
                              const TextStyle(fontSize: 14, color: Colors.grey),
                        ),
                        Text(
                          arrivalTimeText,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: firstBus.isOutOfService
                                ? Colors.grey
                                : (remainingTime <= 3
                                    ? Colors.red
                                    : Colors.blue[600]),
                          ),
                        ),
                        if (currentStationText.isNotEmpty &&
                            !firstBus.isOutOfService)
                          Text(
                            '($currentStationText)',
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
                            nextBus.isOutOfService
                                ? '운행종료'
                                : '${nextBus.getRemainingMinutes()}분',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      )
                    else
                      const SizedBox.shrink(),
                    // 승차 알람 버튼: 알람이 이미 설정되었다면 '알람 해제', 아니면 '승차 알람'
                    ElevatedButton.icon(
                      onPressed: firstBus.isOutOfService
                          ? null
                          : () async {
                              await _toggleBoardingAlarm();
                            },
                      icon: Icon(
                        Icons.directions_bus,
                        color: alarmEnabled ? Colors.yellow : Colors.white,
                        size: 18,
                      ),
                      label: Text(
                        alarmEnabled ? '알람 해제' : '승차 알람',
                        style: const TextStyle(fontSize: 13),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: firstBus.isOutOfService
                            ? Colors.grey
                            : (alarmEnabled ? Colors.blue[700] : Colors.blue),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 0),
                        minimumSize: const Size(80, 36),
                      ),
                    ),
                  ],
                ),
                if (alarmEnabled &&
                    !hasBoarded &&
                    !firstBus.isOutOfService &&
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
