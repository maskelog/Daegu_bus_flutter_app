import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:daegu_bus_app/models/bus_arrival.dart';
import 'package:daegu_bus_app/models/bus_info.dart';
import 'package:daegu_bus_app/services/alarm_service.dart';
import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:daegu_bus_app/services/api_service.dart';
import 'package:daegu_bus_app/utils/tts_switcher.dart' show TtsSwitcher;
import 'package:daegu_bus_app/main.dart' show logMessage, LogLevel;

class BusCard extends StatefulWidget {
  final BusArrival busArrival;
  final VoidCallback onTap;
  final String? stationName;
  final String stationId;

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

void safeStartNativeTtsTracking({
  required String routeId,
  required String stationId,
  required String busNo,
  required String stationName,
  int remainingMinutes = 5,
  Future<int> Function()? getRemainingTimeCallback,
}) {
  if ([routeId, stationId, busNo, stationName].any((e) => e.isEmpty)) {
    logMessage("❌ TTS 추적 호출 생략 - 인자 누락", level: LogLevel.warning);
    return;
  }
  // TtsSwitcher 사용 - 가장 안전한 방법으로 TTS 발화
  TtsSwitcher.startTtsTracking(
    routeId: routeId,
    stationId: stationId,
    busNo: busNo,
    stationName: stationName,
    remainingMinutes: remainingMinutes, // 남은 시간 전달
    getRemainingTimeCallback: getRemainingTimeCallback,
  );
}

class _BusCardState extends State<BusCard> {
  bool hasBoarded = false;
  bool _isUpdating = false;
  late BusInfo firstBus;
  late int remainingTime;
  final NotificationService _notificationService = NotificationService();
  Timer? _timer;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    if (widget.busArrival.busInfoList.isNotEmpty) {
      firstBus = widget.busArrival.busInfoList.first;
      remainingTime = _calculateRemainingTime();
      _updateAlarmServiceCache();

      // 30초마다 주기적으로 버스 정보 업데이트
      _updateTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (mounted) {
          _updateBusArrivalInfo();
        } else {
          timer.cancel();
        }
      });
    }
  }

  @override
  void didUpdateWidget(BusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busArrival.busInfoList.isNotEmpty) {
      firstBus = widget.busArrival.busInfoList.first;
      remainingTime =
          firstBus.isOutOfService ? 0 : firstBus.getRemainingMinutes();
    }
  }

  Future<void> _updateBusArrivalInfo() async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);

    try {
      final updatedBusArrivals = await ApiService.getBusArrivalByRouteId(
        widget.stationId,
        widget.busArrival.routeId,
      );

      if (mounted &&
          updatedBusArrivals.isNotEmpty &&
          updatedBusArrivals[0].busInfoList.isNotEmpty) {
        final updatedBusArrival = updatedBusArrivals[0];
        setState(() {
          firstBus = updatedBusArrival.busInfoList.first;
          remainingTime =
              firstBus.isOutOfService ? 0 : firstBus.getRemainingMinutes();
          logMessage('BusCard - 업데이트된 남은 시간: $remainingTime',
              level: LogLevel.debug);
          _updateAlarmServiceCache();

          final alarmService =
              Provider.of<AlarmService>(context, listen: false);
          final bool hasAlarm = alarmService.hasAlarm(
            widget.busArrival.routeNo,
            widget.stationName ?? '정류장 정보 없음',
            widget.busArrival.routeId,
          );

          if (hasAlarm &&
              !hasBoarded &&
              remainingTime <= 3 &&
              remainingTime > 0) {
            _playAlarm();
          }

          if (!hasBoarded &&
              remainingTime <= 0 &&
              updatedBusArrival.busInfoList.length > 1) {
            BusInfo nextBus = updatedBusArrival.busInfoList[1];
            int nextRemainingTime = nextBus.getRemainingMinutes();
            _setNextBusAlarm(nextRemainingTime, nextBus.currentStation);
          }
          _isUpdating = false;
        });
      } else {
        setState(() => _isUpdating = false);
      }
    } catch (e) {
      logMessage('버스 도착 정보 업데이트 오류: $e');
      setState(() {
        _isUpdating = false;
        // 오류 발생 시 기존 정보 유지, 화면에 오류 메시지 표시하지 않음
      });
    }
  }

  void _updateAlarmServiceCache() {
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    if (!firstBus.isOutOfService && remainingTime > 0) {
      logMessage(
          '🚌 버스 정보 캐시 업데이트: ${widget.busArrival.routeNo}번, $remainingTime분 후');
      alarmService.updateBusInfoCache(
        widget.busArrival.routeNo,
        widget.busArrival.routeId,
        firstBus,
        remainingTime,
      );
    }
  }

  int _calculateRemainingTime() {
    if (firstBus.isOutOfService) return 0;

    final alarmService = Provider.of<AlarmService>(context, listen: false);
    final hasAutoAlarm = alarmService.hasAutoAlarm(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      widget.busArrival.routeId,
    );

    if (hasAutoAlarm) {
      // 자동 알람의 경우 예약된 시간까지 남은 시간 계산
      final autoAlarm = alarmService.getAutoAlarm(
        widget.busArrival.routeNo,
        widget.stationName ?? '정류장 정보 없음',
        widget.busArrival.routeId,
      );
      if (autoAlarm != null) {
        final remaining =
            autoAlarm.scheduledTime.difference(DateTime.now()).inMinutes;
        logMessage('🚌 자동 알람 남은 시간: $remaining분');
        return remaining;
      }
    }

    // 일반 알람이나 자동 알람이 없는 경우 실시간 도착 정보 사용
    final remaining = firstBus.getRemainingMinutes();
    logMessage('🚌 실시간 도착 남은 시간: $remaining분');
    return remaining;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _updateTimer?.cancel();
    super.dispose();
    logMessage('타이머 취소 및 리소스 해제', level: LogLevel.debug);
  }

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
      remainingMinutes: 3,
      currentStation: firstBus.currentStation,
    );
  }

  Future<void> _setNextBusAlarm(
      int nextRemainingTime, String currentStation) async {
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    DateTime arrivalTime =
        DateTime.now().add(Duration(minutes: nextRemainingTime));

    // routeId가 비어있는 경우 기본값 설정
    final String routeId = widget.busArrival.routeId.isNotEmpty
        ? widget.busArrival.routeId
        : '${widget.busArrival.routeNo}_${widget.stationId}';

    logMessage('🚌 다음 버스 알람 설정 - 사용할 routeId: $routeId');

    int alarmId = alarmService.getAlarmId(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      routeId: routeId,
    );

    // 정류장 정보 확인
    if (widget.stationName == null || widget.stationName!.isEmpty) {
      logMessage('🚌 정류장 정보가 없습니다. 알람을 설정할 수 없습니다.');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('정류장 정보가 없습니다. 알람을 설정할 수 없습니다.')),
        );
      }
      return;
    }

    logMessage(
        '🚌 다음 버스 알람 설정: ${widget.busArrival.routeNo}번 버스, $nextRemainingTime분 후 도착 예정, 알람ID: $alarmId');
    logMessage('🚌 예상 도착 시간: $arrivalTime');

    bool success = await alarmService.setOneTimeAlarm(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      nextRemainingTime,
      routeId: routeId,
      useTTS: true,
      isImmediateAlarm: false,
      currentStation: currentStation,
    );

    if (success && mounted) {
      await alarmService.refreshAlarms(); // 알람 상태 갱신
      await alarmService.loadAlarms(); // 즉시 알람 목록 갱신
      setState(() {}); // UI 업데이트

      // 알람 상태 즉시 갱신
      await alarmService.refreshAlarms();

      // 승차 알람은 즉시 모니터링 시작
      await alarmService.startBusMonitoringService(
        stationId: widget.stationId,
        stationName: widget.stationName ?? '정류장 정보 없음',
        routeId: routeId,
        busNo: widget.busArrival.routeNo,
      );

      // 알림 생성 - 진행 중 알림으로 설정하여 중복 방지
      await _notificationService.showNotification(
        id: alarmService.getAlarmId(
            widget.busArrival.routeNo, widget.stationName ?? '정류장 정보 없음',
            routeId: routeId),
        busNo: widget.busArrival.routeNo,
        stationName: widget.stationName ?? '정류장 정보 없음',
        remainingMinutes: remainingTime,
        currentStation: firstBus.currentStation,
        isOngoing: true, // 진행 중 알림으로 설정
      );

      // TTS 알림 즉시 시작
      await TtsSwitcher.startTtsTracking(
          routeId: routeId,
          stationId: widget.stationId,
          busNo: widget.busArrival.routeNo,
          stationName: widget.stationName ?? "정류장 정보 없음",
          remainingMinutes: remainingTime,
          getRemainingTimeCallback: () async {
            try {
              final updatedBusArrivals =
                  await ApiService.getBusArrivalByRouteId(
                widget.stationId,
                routeId,
              );

              if (updatedBusArrivals.isNotEmpty &&
                  updatedBusArrivals[0].busInfoList.isNotEmpty) {
                final latestBus = updatedBusArrivals[0].busInfoList.first;
                return latestBus.getRemainingMinutes();
              }
            } catch (e) {
              logMessage('실시간 도착 시간 업데이트 오류: $e');
            }
            return remainingTime - 1;
          });

      // 승차 알람이 설정되었음을 알림
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('승차 알람이 시작되었습니다')),
        );
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('승차 알람 설정에 실패했습니다')),
      );
    }
  }

  Future<void> _toggleBoardingAlarm() async {
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    final bool currentAlarmState = alarmService.hasAlarm(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      widget.busArrival.routeId,
    );

    if (currentAlarmState) {
      // 알람 즉시 취소
      try {
        // 먼저 알람 서비스를 통해 알람 취소
        final success = await alarmService.cancelAlarmByRoute(
          widget.busArrival.routeNo,
          widget.stationName ?? '정류장 정보 없음',
          widget.busArrival.routeId,
        );

        if (success && mounted) {
          // 알림 취소
          await _notificationService.cancelOngoingTracking();
          await TtsSwitcher.stopTtsTracking(widget.busArrival.routeNo);

          // 알람 상태 갱신
          await alarmService.refreshAlarms();
          await alarmService.loadAlarms(); // 명시적으로 알람 목록 다시 로드

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('승차 알람이 취소되었습니다')),
            );
          }
        }
      } catch (e) {
        logMessage('🚨 알람 취소 중 오류 발생: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('알람 취소 중 오류가 발생했습니다: $e')),
          );
        }
      }
    } else {
      // 알람 설정 로직
      try {
        logMessage('🚌 V2 승차 알람 토글 시작');
        logMessage(
            '🚌 버스 정보: 노선번호=${widget.busArrival.routeNo}, 정류장=${widget.stationName}, 남은시간=$remainingTime');

        // routeId가 비어있는 경우 기본값 설정
        final String routeId = widget.busArrival.routeId.isNotEmpty
            ? widget.busArrival.routeId
            : '${widget.busArrival.routeNo}_${widget.stationId}';

        logMessage('🚌 사용할 routeId: $routeId');

        if (firstBus.isOutOfService) {
          logMessage('🚌 운행 종료된 버스: 알람 설정 불가');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('운행 종료된 버스입니다')),
            );
          }
          return;
        }

        if (remainingTime > 0) {
          // 먼저 버스 정보 캐시 업데이트
          alarmService.updateBusInfoCache(
            widget.busArrival.routeNo,
            routeId,
            firstBus,
            remainingTime,
          );

          logMessage('🚌 버스 정보 캐시 업데이트 완료');

          // 알람 설정 전에 기존 알람 상태 갱신
          await alarmService.refreshAlarms();

          // 알람 설정
          bool success = await alarmService.setOneTimeAlarm(
            widget.busArrival.routeNo,
            widget.stationName ?? '정류장 정보 없음',
            remainingTime,
            routeId: routeId,
            useTTS: true,
            isImmediateAlarm: false,
            currentStation: firstBus.currentStation,
          );

          logMessage('🚌 알람 설정 시도 결과: $success');

          if (success && mounted) {
            // 알람 상태 즉시 갱신
            await alarmService.refreshAlarms();
            await alarmService.loadAlarms(); // 명시적으로 알람 목록 다시 로드

            // 승차 알람은 즉시 모니터링 시작
            try {
              await alarmService.startBusMonitoringService(
                stationId: widget.stationId,
                stationName: widget.stationName ?? '정류장 정보 없음',
                routeId: routeId,
                busNo: widget.busArrival.routeNo,
              );
              logMessage('🚌 버스 모니터링 서비스 시작 성공');
            } catch (e) {
              logMessage('🚌 버스 모니터링 서비스 시작 실패: $e');
              // 서비스 시작 실패해도 계속 진행
            }

            // 알림 생성 - 진행 중 알림으로 설정하여 중복 방지
            await _notificationService.showNotification(
              id: alarmService.getAlarmId(
                  widget.busArrival.routeNo, widget.stationName ?? '정류장 정보 없음',
                  routeId: routeId),
              busNo: widget.busArrival.routeNo,
              stationName: widget.stationName ?? '정류장 정보 없음',
              remainingMinutes: remainingTime,
              currentStation: firstBus.currentStation,
              isOngoing: true,
            );

            // TTS 추적 시작
            await TtsSwitcher.startTtsTracking(
              routeId: routeId,
              stationId: widget.stationId,
              busNo: widget.busArrival.routeNo,
              stationName: widget.stationName ?? "정류장 정보 없음",
              remainingMinutes: remainingTime,
              getRemainingTimeCallback: () async {
                try {
                  final updatedBusArrivals =
                      await ApiService.getBusArrivalByRouteId(
                    widget.stationId,
                    routeId,
                  );

                  if (updatedBusArrivals.isNotEmpty &&
                      updatedBusArrivals[0].busInfoList.isNotEmpty) {
                    final latestBus = updatedBusArrivals[0].busInfoList.first;
                    return latestBus.getRemainingMinutes();
                  }
                } catch (e) {
                  logMessage('실시간 도착 시간 업데이트 오류: $e');
                }
                return remainingTime;
              },
            );

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('승차 알람이 설정되었습니다')),
              );
            }
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('승차 알람 설정에 실패했습니다')),
            );
          }
        } else if (mounted) {
          logMessage('🚌 버스 도착 임박 또는 이미 도착');

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('버스가 이미 도착했거나 곧 도착합니다')),
          );
        }
      } catch (e) {
        logMessage('🚨 _toggleBoardingAlarm 오류: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('오류 발생: ${e.toString()}')),
          );
        }
      }
    }
    setState(() {}); // UI 상태 갱신
  }

  Widget _showBoardingButton() {
    return ElevatedButton.icon(
      onPressed: () async {
        setState(() => hasBoarded = true);
        final alarmService = Provider.of<AlarmService>(context, listen: false);
        bool success = await alarmService.cancelAlarmByRoute(
          widget.busArrival.routeNo,
          widget.stationName ?? '정류장 정보 없음',
          widget.busArrival.routeId,
        );
        if (success && mounted) {
          // TTSHelper.speakAlarmCancel 제거
          await _notificationService.cancelOngoingTracking();
          await TtsSwitcher.stopTtsTracking(
              widget.busArrival.routeNo); // TTS 추적 중단
          alarmService.refreshAlarms();
        }
      },
      icon: const Icon(Icons.check_circle_outline, color: Colors.white),
      label: const Text(
        '승차 완료',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green[600],
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.green.shade800, width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.busArrival.busInfoList.isEmpty) {
      return Card(
        margin: const EdgeInsets.only(bottom: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
              const SizedBox(width: 8),
              Text(
                '도착 정보가 없습니다',
                style: TextStyle(color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    firstBus = widget.busArrival.busInfoList.first;
    remainingTime =
        firstBus.isOutOfService ? 0 : firstBus.getRemainingMinutes();
    final String currentStationText = firstBus.currentStation.trim().isNotEmpty
        ? firstBus.currentStation
        : "정보 업데이트 중"; // 변경: 위치 정보 없음 -> 정보 업데이트 중

    String arrivalTimeText;
    if (firstBus.isOutOfService) {
      arrivalTimeText = '운행종료';
    } else if (remainingTime <= 0) {
      arrivalTimeText = '곧 도착';
    } else {
      arrivalTimeText = '$remainingTime분';
    }

    final alarmService = Provider.of<AlarmService>(context, listen: true);
    final bool alarmEnabled = alarmService.hasAlarm(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      widget.busArrival.routeId,
    );
    logMessage('🚌 hasAlarm 결과: $alarmEnabled');
    logMessage(
        '🚌 버스카드 알람 상태: routeNo=${widget.busArrival.routeNo}, enabled=$alarmEnabled');

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
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 버스 정보 헤더
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
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 12),

                // 첫 번째(현재) 버스 정보
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

                // 진행 상태 바
                LinearProgressIndicator(
                  value: 0.6,
                  backgroundColor: Colors.grey[200],
                  color:
                      firstBus.isOutOfService ? Colors.grey : Colors.blue[500],
                  borderRadius: BorderRadius.circular(4),
                ),
                const SizedBox(height: 12),

                // 현재 버스 도착 정보 및 승차 알람 버튼
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
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
                                fontSize: 12, color: Colors.grey[600]),
                          ),
                      ],
                    ),
                    // 다음 버스 정보 표시 (있을 경우)
                    if (widget.busArrival.busInfoList.length > 1)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '다음 버스',
                            style: TextStyle(fontSize: 14, color: Colors.grey),
                          ),
                          Text(
                            widget.busArrival.busInfoList[1].isOutOfService
                                ? '운행종료'
                                : '${widget.busArrival.busInfoList[1].getRemainingMinutes()}분',
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
                    ElevatedButton.icon(
                      onPressed: firstBus.isOutOfService
                          ? null
                          : () async {
                              await _toggleBoardingAlarm();
                              setState(() {}); // 상태 갱신 추가
                            },
                      icon: Icon(
                        alarmEnabled
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                        color: alarmEnabled
                            ? Colors.white // 색상 수정
                            : Colors.white,
                        size: 20,
                      ),
                      label: Text(
                        alarmEnabled ? '알람 해제' : '승차 알람',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white, // 색상 수정
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: firstBus.isOutOfService
                            ? Colors.grey
                            : (alarmEnabled
                                ? Colors.yellow[700] // 노란색으로 변경
                                : Colors.blue[600]),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 0),
                        minimumSize: const Size(100, 40),
                        elevation: alarmEnabled ? 4 : 2,
                      ),
                    ),
                  ],
                ),

                // 승차 완료 버튼 (알람이 활성화되고 버스가 곧 도착할 때)
                if (alarmEnabled &&
                    !hasBoarded &&
                    !firstBus.isOutOfService &&
                    remainingTime <= 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _showBoardingButton(),
                  ),

                // 추가: 다음 버스 리스트 (2번째 버스부터)
                if (widget.busArrival.busInfoList.length > 1) ...[
                  const SizedBox(height: 24),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 다음 버스 목록
                  ...widget.busArrival.busInfoList.skip(1).map((bus) {
                    final int nextRemainingMin = bus.getRemainingMinutes();
                    final bool isOutOfService = bus.isOutOfService;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey[300]!),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    widget.busArrival.routeNo,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: isOutOfService
                                          ? Colors.grey
                                          : Colors.blue[600],
                                    ),
                                  ),
                                  if (bus.isLowFloor)
                                    Container(
                                      margin: const EdgeInsets.only(left: 8),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 4, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.green[100],
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '저상',
                                        style: TextStyle(
                                          color: Colors.green[700],
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              Text(
                                isOutOfService ? '운행종료' : '$nextRemainingMin분',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isOutOfService
                                      ? Colors.grey
                                      : (nextRemainingMin <= 3
                                          ? Colors.red
                                          : Colors.blue[600]),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            bus.currentStation,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          Text(
                            bus.remainingStops,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[500],
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
