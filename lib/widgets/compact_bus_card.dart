import 'dart:async';
import 'package:daegu_bus_app/main.dart' show logMessage, LogLevel;
import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bus_arrival.dart';
import '../models/bus_info.dart';
import '../services/alarm_service.dart';
import '../services/api_service.dart';
import 'package:daegu_bus_app/utils/tts_switcher.dart' show TtsSwitcher;
import 'package:daegu_bus_app/services/settings_service.dart';

class CompactBusCard extends StatefulWidget {
  final BusArrival busArrival;
  final VoidCallback onTap;
  final String? stationName; // 정류장 이름
  final String stationId; // 정류장 ID 추가

  const CompactBusCard({
    super.key,
    required this.busArrival,
    required this.onTap,
    required this.stationId, // 필수 파라미터로 변경
    this.stationName,
  });

  @override
  State<CompactBusCard> createState() => _CompactBusCardState();
}

class _CompactBusCardState extends State<CompactBusCard> {
  bool _cacheUpdated = false;
  final int defaultPreNotificationMinutes = 3; // 기본 알람 시간 (분)
  Timer? _updateTimer;
  bool _isUpdating = false;

  @override
  void initState() {
    super.initState();
    if (widget.busArrival.busInfoList.isNotEmpty) {
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
  void dispose() {
    _updateTimer?.cancel();
    logMessage('컴팩트 버스 카드 타이머 취소', level: LogLevel.debug);
    super.dispose();
  }

  Future<void> _updateBusArrivalInfo() async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);

    try {
      final updatedBusArrivals = await ApiService.getBusArrivalByRouteId(
        widget.busArrival.routeId.split('_').last, // stationId 추출
        widget.busArrival.routeId,
      );

      if (mounted &&
          updatedBusArrivals.isNotEmpty &&
          updatedBusArrivals[0].busInfoList.isNotEmpty) {
        setState(() {
          // 업데이트된 버스 정보로 위젯 새로 그리기
          widget.busArrival.busInfoList.clear();
          widget.busArrival.busInfoList
              .addAll(updatedBusArrivals[0].busInfoList);
          logMessage(
              'CompactBusCard - 업데이트된 남은 시간: ${widget.busArrival.busInfoList.first.getRemainingMinutes()}',
              level: LogLevel.debug);

          // 알람 서비스 캐시 업데이트
          if (widget.busArrival.busInfoList.isNotEmpty) {
            final alarmService =
                Provider.of<AlarmService>(context, listen: false);
            final firstBus = widget.busArrival.busInfoList.first;
            final remainingMinutes = firstBus.getRemainingMinutes();
            alarmService.updateBusInfoCache(
              widget.busArrival.routeNo,
              widget.busArrival.routeId,
              firstBus,
              remainingMinutes,
            );
            // [추가] 알람이 있으면 Notification도 함께 갱신
            if (widget.stationName != null &&
                alarmService.hasAlarm(
                  widget.busArrival.routeNo,
                  widget.stationName!,
                  widget.busArrival.routeId,
                )) {
              logMessage(
                '[CompactBusCard] updateBusTrackingNotification 호출: busNo=${widget.busArrival.routeNo}, stationName=${widget.stationName}, remainingMinutes=[1m$remainingMinutes\u001b[0m, currentStation=${firstBus.currentStation}, routeId=${widget.busArrival.routeId}',
                level: LogLevel.info,
              );
              NotificationService().updateBusTrackingNotification(
                busNo: widget.busArrival.routeNo,
                stationName: widget.stationName!,
                remainingMinutes: remainingMinutes,
                currentStation: firstBus.currentStation,
                routeId: widget.busArrival.routeId,
                stationId: widget.stationId,
              );
              // [핵심 추가] 네이티브 알림이 항상 표시되도록 showOngoingBusTracking 호출
              NotificationService().showOngoingBusTracking(
                busNo: widget.busArrival.routeNo,
                stationName: widget.stationName!,
                remainingMinutes: remainingMinutes,
                currentStation: firstBus.currentStation,
                routeId: widget.busArrival.routeId,
                stationId: widget.stationId,
              );
            }
          }
        });
      }
    } catch (e) {
      logMessage('컴팩트 버스 카드 정보 업데이트 오류: $e', level: LogLevel.error);
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 첫 번째 버스 정보 추출
    final firstBus = widget.busArrival.busInfoList.isNotEmpty
        ? widget.busArrival.busInfoList.first
        : null;

    if (firstBus == null) {
      return const SizedBox.shrink();
    }

    // 남은 시간 계산 (getRemainingMinutes()는 정수값을 반환)
    // 운행 종료인 경우 0분으로 처리
    final int remainingMinutes =
        firstBus.isOutOfService ? 0 : firstBus.getRemainingMinutes();

    // 버스 상태에 따른 도착 정보 텍스트 설정
    String arrivalTimeText;
    Color arrivalTextColor;

    if (firstBus.isOutOfService) {
      arrivalTimeText = '운행종료';
      arrivalTextColor = Colors.grey;
    } else if (remainingMinutes <= 0) {
      arrivalTimeText = '곧 도착';
      arrivalTextColor = Colors.red;
    } else {
      arrivalTimeText = '$remainingMinutes분';
      arrivalTextColor = remainingMinutes <= 3 ? Colors.red : Colors.blue[600]!;
    }

    // 버스 위치(정류장) 이름 표시: firstBus.currentStation 값이 없으면 widget.stationName 사용
    final currentStationText = firstBus.currentStation.trim().isNotEmpty
        ? firstBus.currentStation
        : (widget.stationName ?? "정보 없음");

    // 알람 서비스 가져오기
    final alarmService = Provider.of<AlarmService>(context);
    final bool hasAlarm = widget.stationName != null &&
        alarmService.hasAlarm(
          widget.busArrival.routeNo,
          widget.stationName!,
          widget.busArrival.routeId,
        );

    // 캐시 업데이트 (한 번만 실행)
    if (!_cacheUpdated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        alarmService.updateBusInfoCache(
          widget.busArrival.routeNo,
          widget.busArrival.routeId,
          firstBus,
          remainingMinutes,
        );
        _cacheUpdated = true;
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
              // 현재 정류소 및 남은 정류소 표시
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentStationText,
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
              // 도착 예정 시간 표시
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    firstBus.isOutOfService ? '' : '도착예정',
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
              // 알람 버튼 (정류장 이름이 있는 경우에만 표시, 운행종료 시 비활성화)
              if (widget.stationName != null && !firstBus.isOutOfService)
                Container(
                  decoration: BoxDecoration(
                    color: hasAlarm ? Colors.amber[600] : Colors.grey[200],
                    borderRadius: BorderRadius.circular(20),
                    // 테두리 추가
                    border: hasAlarm
                        ? Border.all(color: Colors.orange.shade800, width: 1.5)
                        : Border.all(color: Colors.grey.shade400, width: 0.5),
                    // 그림자 효과
                    boxShadow: hasAlarm
                        ? [
                            BoxShadow(
                              color: Colors.amber.withAlpha(77),
                              spreadRadius: 1,
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: IconButton(
                    icon: Icon(
                      hasAlarm
                          ? Icons.notifications_active
                          : Icons.notifications_none,
                      color: hasAlarm ? Colors.white : Colors.grey[600],
                      size: 20, // 약간 키움
                    ),
                    onPressed: () => _setAlarm(firstBus, remainingMinutes),
                    padding: const EdgeInsets.all(8), // 패딩 추가
                    tooltip: hasAlarm ? '알람 해제' : '승차 알람 설정',
                    constraints: const BoxConstraints(
                      minWidth: 40,
                      minHeight: 40,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // 알람 설정 메서드
  void _setAlarm(BusInfo busInfo, int remainingMinutes) async {
    if (widget.stationName == null) return;

    try {
      final alarmService = Provider.of<AlarmService>(context, listen: false);
      final notificationService = NotificationService();
      await notificationService.initialize();

      final String routeId = widget.busArrival.routeId.isNotEmpty
          ? widget.busArrival.routeId
          : '${widget.busArrival.routeNo}_${widget.stationName}';

      final String stationId = widget.stationId;

      logMessage('사용할 routeId: $routeId, stationId: $stationId',
          level: LogLevel.debug);

      bool hasAlarm = alarmService.hasAlarm(
        widget.busArrival.routeNo,
        widget.stationName!,
        routeId,
      );

      logMessage('기존 알람 존재 여부: $hasAlarm', level: LogLevel.debug);

      if (hasAlarm) {
        // 알람 취소 시 필요한 정보 미리 저장
        final busNo = widget.busArrival.routeNo;
        final stationName = widget.stationName!;

        try {
          // 모든 취소 작업을 순차적으로 실행
          await alarmService.cancelAlarmByRoute(
            busNo,
            stationName,
            routeId,
          );

          // 명시적으로 포그라운드 알림 취소
          await notificationService.cancelOngoingTracking();

          // TTS 추적 중단
          await TtsSwitcher.stopTtsTracking(busNo);

          // 버스 모니터링 서비스 중지
          await alarmService.stopBusMonitoringService();

          // 알람 상태 갱신
          await alarmService.refreshAlarms();

          // UI 업데이트를 위한 setState 추가
          setState(() {});

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('승차 알람이 취소되었습니다')),
            );
          }
        } catch (e) {
          logMessage('알람 취소 중 오류 발생: $e', level: LogLevel.error);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('알람 취소 중 오류가 발생했습니다: $e')),
            );
          }
        }
      } else {
        if (remainingMinutes > 0) {
          int alarmId = alarmService.getAlarmId(
            widget.busArrival.routeNo,
            widget.stationName!,
            routeId: routeId,
          );

          DateTime arrivalTime =
              DateTime.now().add(Duration(minutes: remainingMinutes));
          Duration preNotificationTime =
              Duration(minutes: defaultPreNotificationMinutes);

          // 알람 설정 디버그 로그
          logMessage("--- 알람 설정 시도 ---", level: LogLevel.debug);
          logMessage("Alarm ID: $alarmId", level: LogLevel.debug);
          logMessage("Route No: ${widget.busArrival.routeNo}",
              level: LogLevel.debug);
          logMessage("Station Name: ${widget.stationName}",
              level: LogLevel.debug);
          logMessage("Route ID: $routeId", level: LogLevel.debug);
          logMessage("Station ID: $stationId", level: LogLevel.debug);
          logMessage("Remaining Time: $remainingMinutes mins",
              level: LogLevel.debug);
          logMessage("Arrival Time: $arrivalTime", level: LogLevel.debug);
          logMessage("Pre-notification: ${preNotificationTime.inMinutes} mins",
              level: LogLevel.debug);
          logMessage("Current Station: ${busInfo.currentStation}",
              level: LogLevel.debug);

          // 동일한 정류장의 다른 버스 알람이 있는지 확인하고 해제
          final activeAlarms = alarmService.activeAlarms;
          for (var alarm in activeAlarms) {
            if (alarm.stationName == widget.stationName &&
                alarm.busNo != widget.busArrival.routeNo) {
              logMessage('🚌 동일 정류장의 다른 버스(${alarm.busNo}) 알람 해제 시도',
                  level: LogLevel.info);

              try {
                // 이전 알람 취소
                final success = await alarmService.cancelAlarmByRoute(
                  alarm.busNo,
                  alarm.stationName,
                  alarm.routeId,
                );

                if (success) {
                  // 포그라운드 알림 취소
                  await notificationService.cancelOngoingTracking();

                  // TTS 추적 중단
                  await TtsSwitcher.stopTtsTracking(alarm.busNo);

                  // 버스 모니터링 서비스 중지
                  await alarmService.stopBusMonitoringService();

                  // 알람 상태 갱신
                  await alarmService.loadAlarms();
                  await alarmService.refreshAlarms();

                  logMessage('🚌 이전 버스 알람 해제 성공: ${alarm.busNo}',
                      level: LogLevel.info);
                }
              } catch (e) {
                logMessage('이전 버스 알람 해제 중 오류: $e', level: LogLevel.error);
              }
            }
          }

          bool success = await alarmService.setOneTimeAlarm(
            widget.busArrival.routeNo,
            widget.stationName ?? '정류장 정보 없음',
            remainingMinutes,
            routeId: routeId,
            useTTS: true,
            isImmediateAlarm: true,
            currentStation: busInfo.currentStation, // 현재 위치 정보 전달
          );

          logMessage('알람 설정 결과: $success', level: LogLevel.debug);

          if (success && mounted) {
            // 즉시 알림 대신 즉시 모니터링 시작
            await alarmService.refreshAlarms(); // 알람 상태 갱신
            setState(() {}); // UI 업데이트

            // 승차 알람은 즉시 모니터링 시작
            await alarmService.startBusMonitoringService(
              stationId: stationId,
              stationName: widget.stationName!,
              routeId: routeId,
              busNo: widget.busArrival.routeNo,
            );

            // 네이티브 알림 표시 및 실시간 업데이트 시작
            await notificationService.showOngoingBusTracking(
              busNo: widget.busArrival.routeNo,
              stationName: widget.stationName!,
              remainingMinutes: remainingMinutes,
              currentStation: busInfo.currentStation,
              routeId: routeId,
              stationId: stationId,
            );

            // 실시간 버스 정보 업데이트를 위한 타이머 시작
            notificationService.startRealTimeBusUpdates(
              busNo: widget.busArrival.routeNo,
              stationName: widget.stationName!,
              routeId: routeId,
              stationId: stationId,
            );

            // TTS 알림 즉시 시작 (설정 및 이어폰 연결 여부 확인)
            if (!mounted) return;

            final settings =
                Provider.of<SettingsService>(context, listen: false);
            final ttsSwitcher = TtsSwitcher();
            await ttsSwitcher.initialize();
            final headphoneConnected =
                await ttsSwitcher.isHeadphoneConnected().catchError((e) {
              logMessage('이어폰 연결 상태 확인 중 오류: $e', level: LogLevel.error);
              return false;
            });

            if (settings.speakerMode == SettingsService.speakerModeHeadset) {
              // 이어폰 전용 모드: 이어폰 연결 시에만 TTS 실행
              if (headphoneConnected) {
                await TtsSwitcher.startTtsTracking(
                  routeId: routeId,
                  stationId: stationId,
                  busNo: widget.busArrival.routeNo,
                  stationName: widget.stationName!,
                  remainingMinutes: remainingMinutes,
                );
              } else {
                logMessage('🎧 이어폰 미연결 - 이어폰 전용 모드에서 TTS 실행 안함',
                    level: LogLevel.info);
              }
            } else {
              // 스피커/자동 모드: 기존대로 동작
              await TtsSwitcher.startTtsTracking(
                routeId: routeId,
                stationId: stationId,
                busNo: widget.busArrival.routeNo,
                stationName: widget.stationName!,
                remainingMinutes: remainingMinutes,
              );
            }

            // 중복 알림 제거 - 알람 서비스에서 이미 알림을 표시함

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
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('버스가 이미 도착했거나 곧 도착합니다')),
            );
          }
        }
      }
    } catch (e) {
      logMessage('_setAlarm 오류 발생: $e', level: LogLevel.error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류 발생: ${e.toString()}')),
        );
      }
    }
  }

  @override
  void didUpdateWidget(CompactBusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.busArrival.routeNo != widget.busArrival.routeNo ||
        oldWidget.busArrival.routeId != widget.busArrival.routeId) {
      _cacheUpdated = false;
    }
  }
}
