import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:daegu_bus_app/models/bus_arrival.dart';
import 'package:daegu_bus_app/models/bus_info.dart';
import 'package:daegu_bus_app/services/alarm_service.dart';
import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:daegu_bus_app/services/api_service.dart';
import 'package:daegu_bus_app/utils/tts_switcher.dart' show TtsSwitcher;
import 'package:daegu_bus_app/main.dart' show logMessage, LogLevel;
import 'package:daegu_bus_app/services/settings_service.dart';

// 정류장 추적 메서드 채널 상수 추가
const String STATION_TRACKING_CHANNEL =
    'com.example.daegu_bus_app/station_tracking';

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
  late AlarmService _alarmService;

  @override
  void initState() {
    super.initState();
    _alarmService = Provider.of<AlarmService>(context, listen: false);
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

    // AlarmService 리스너 등록 - 포그라운드 노티피케이션에서 취소 시 UI 업데이트
    _alarmService.addListener(_updateAlarmState);

    // 알림 서비스 초기화
    _notificationService.initialize();
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

          final bool hasAlarm = _alarmService.hasAlarm(
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
    if (!firstBus.isOutOfService && remainingTime > 0) {
      logMessage(
          '🚌 버스 정보 캐시 업데이트: ${widget.busArrival.routeNo}번, $remainingTime분 후');
      _alarmService.updateBusInfoCache(
        widget.busArrival.routeNo,
        widget.busArrival.routeId,
        firstBus,
        remainingTime,
      );
    }
  }

  int _calculateRemainingTime() {
    if (firstBus.isOutOfService) return 0;

    final hasAutoAlarm = _alarmService.hasAutoAlarm(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      widget.busArrival.routeId,
    );

    if (hasAutoAlarm) {
      // 자동 알람의 경우 예약된 시간까지 남은 시간 계산
      final autoAlarm = _alarmService.getAutoAlarm(
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

  // 알람 상태 변경 시 UI 업데이트
  void _updateAlarmState() {
    if (mounted) {
      setState(() {
        // UI 강제 갱신
        // 승차 알람 상태 재확인
        if (!_alarmService.isInTrackingMode) {
          hasBoarded = false; // 추적 중이 아니면 승차 완료 상태 초기화
          _updateBusArrivalInfo(); // 정보 새로고침
          logMessage(
              '\ud83d\udce3 UI 강제 업데이트 - 추적중 = ${_alarmService.isInTrackingMode}, hasBoarded 초기화',
              level: LogLevel.debug);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _updateTimer?.cancel();

    // AlarmService 리스너 해제
    _alarmService.removeListener(_updateAlarmState);

    super.dispose();
    logMessage('타이머 취소 및 리소스 해제', level: LogLevel.debug);
  }

  void _playAlarm() {
    int alarmId = _alarmService.getAlarmId(
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
    DateTime arrivalTime =
        DateTime.now().add(Duration(minutes: nextRemainingTime));

    // routeId가 비어있는 경우 기본값 설정
    final String routeId = widget.busArrival.routeId.isNotEmpty
        ? widget.busArrival.routeId
        : '${widget.busArrival.routeNo}_${widget.stationId}';

    logMessage('🚌 다음 버스 알람 설정 - 사용할 routeId: $routeId');

    int alarmId = _alarmService.getAlarmId(
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

    bool success = await _alarmService.setOneTimeAlarm(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      nextRemainingTime,
      routeId: routeId,
      useTTS: true,
      isImmediateAlarm: false,
      currentStation: currentStation,
    );

    if (success && mounted) {
      await _alarmService.refreshAlarms(); // 알람 상태 갱신
      await _alarmService.loadAlarms(); // 즉시 알람 목록 갱신
      setState(() {}); // UI 업데이트

      // 알람 상태 즉시 갱신
      await _alarmService.refreshAlarms();

      // 승차 알람은 즉시 모니터링 시작
      await _alarmService.startBusMonitoringService(
        stationId: widget.stationId,
        stationName: widget.stationName ?? '정류장 정보 없음',
        routeId: routeId,
        busNo: widget.busArrival.routeNo,
      );

      // 알림 서비스 시작
      await _notificationService.showOngoingBusTracking(
        busNo: widget.busArrival.routeNo,
        stationName: widget.stationName ?? '정류장 정보 없음',
        remainingMinutes: remainingTime,
        currentStation: firstBus.currentStation,
        routeId: routeId,
      );

      // TTS 알림 즉시 시작 (일반 승차 알람에 대해 useTts 설정 및 이어폰 연결 여부 확인)
      final settings = Provider.of<SettingsService>(context, listen: false);
      if (!settings.useTts) {
        logMessage('🔇 일반 승차 알람 TTS 설정 비활성화 - TTS 건너뜀', level: LogLevel.info);
      } else {
        final ttsSwitcher = TtsSwitcher();
        await ttsSwitcher.initialize();
        final headphoneConnected = await ttsSwitcher.isHeadphoneConnected();
        if (headphoneConnected) {
          await TtsSwitcher.startTtsTracking(
            routeId: routeId,
            stationId: widget.stationId,
            busNo: widget.busArrival.routeNo,
            stationName: widget.stationName ?? '정류장 정보 없음',
          );
        } else {
          logMessage('🎧 이어폰 미연결 - 승차 알람 TTS 건너뜀', level: LogLevel.info);
        }
      }

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
    final bool currentAlarmState = _alarmService.hasAlarm(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      widget.busArrival.routeId,
    );

    // 정류장 ID 추출
    final String stationId = widget.stationId.isNotEmpty
        ? widget.stationId
        : widget.busArrival.routeId.split('_').lastOrNull ?? '';
    if (stationId.isEmpty) {
      logMessage('❌ 정류장 ID를 추출할 수 없습니다.', level: LogLevel.error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('정류장 정보가 완전하지 않습니다. 알람을 설정할 수 없습니다.')),
        );
      }
      return;
    }

    if (currentAlarmState) {
      // 알람 즉시 취소 로직
      try {
        logMessage(
            '🔔 승차 알람 취소 시도 - 노선 번호: ${widget.busArrival.routeNo}, 정류장: ${widget.stationName}',
            level: LogLevel.debug);

        // 필요한 정보 미리 저장
        final stationName = widget.stationName ?? '정류장 정보 없음';
        final busNo = widget.busArrival.routeNo;
        final routeId = widget.busArrival.routeId;

        // 모든 취소 작업을 순차적으로 실행
        final success = await _alarmService.cancelAlarmByRoute(
          busNo,
          stationName,
          routeId,
        );

        if (success) {
          // 명시적으로 포그라운드 알림 취소
          await _notificationService.cancelOngoingTracking();

          // TTS 추적 중단
          await TtsSwitcher.stopTtsTracking(busNo);

          // 버스 모니터링 서비스 중지
          await _alarmService.stopBusMonitoringService();

          // 알람 상태 갱신
          await _alarmService.loadAlarms();
          await _alarmService.refreshAlarms();

          setState(() {});

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('승차 알람이 취소되었습니다')),
            );
            logMessage('🔔 승차 알람 취소 완료', level: LogLevel.info);
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('승차 알람 취소 실패')),
          );
          logMessage('🔔 승차 알람 취소 실패', level: LogLevel.error);
        }
      } catch (e) {
        logMessage('🚨 알람 취소 중 오류 발생: $e', level: LogLevel.error);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('알람 취소 중 오류가 발생했습니다: $e')),
          );
        }
      }
    } else {
      // 알람 설정 로직
      try {
        logMessage('🚌 V2 승차 알람 토글 시작', level: LogLevel.debug);
        logMessage(
            '🚌 버스 정보: 노선번호=${widget.busArrival.routeNo}, 정류장=${widget.stationName}, 남은시간=$remainingTime',
            level: LogLevel.debug);

        // routeId가 비어있는 경우 기본값 설정
        final String routeId = widget.busArrival.routeId.isNotEmpty
            ? widget.busArrival.routeId
            : '${widget.busArrival.routeNo}_${widget.stationId}';

        logMessage('🚌 사용할 routeId: $routeId, stationId: $stationId',
            level: LogLevel.debug);

        // 동일한 정류장의 다른 버스 알람이 있는지 확인하고 해제
        final activeAlarms = _alarmService.activeAlarms;
        for (var alarm in activeAlarms) {
          if (alarm.stationName == widget.stationName &&
              alarm.busNo != widget.busArrival.routeNo) {
            logMessage('🚌 동일 정류장의 다른 버스(${alarm.busNo}) 알람 해제 시도',
                level: LogLevel.info);

            try {
              // 이전 알람 취소
              final success = await _alarmService.cancelAlarmByRoute(
                alarm.busNo,
                alarm.stationName,
                alarm.routeId,
              );

              if (success) {
                // 포그라운드 알림 취소
                await _notificationService.cancelOngoingTracking();

                // TTS 추적 중단
                await TtsSwitcher.stopTtsTracking(alarm.busNo);

                // 버스 모니터링 서비스 중지
                await _alarmService.stopBusMonitoringService();

                // 알람 상태 갱신
                await _alarmService.loadAlarms();
                await _alarmService.refreshAlarms();

                logMessage('🚌 이전 버스 알람 해제 성공: ${alarm.busNo}',
                    level: LogLevel.info);
              }
            } catch (e) {
              logMessage('이전 버스 알람 해제 중 오류: $e', level: LogLevel.error);
            }
          }
        }

        // 알람 설정 로직 추가
        int alarmId = _alarmService.getAlarmId(
          widget.busArrival.routeNo,
          widget.stationName ?? '정류장 정보 없음',
          routeId: routeId,
        );

        logMessage(
            '🚌 알람 설정 시작: ${widget.busArrival.routeNo}번 버스, ${widget.stationName}, 알람ID: $alarmId, stationId: $stationId',
            level: LogLevel.debug);

        // 버스 도착 예상 시간 계산
        DateTime arrivalTime =
            DateTime.now().add(Duration(minutes: remainingTime));
        logMessage('🚌 예상 도착 시간: $arrivalTime', level: LogLevel.debug);

        // 알람 서비스에 알람 설정
        bool success = await _alarmService.setOneTimeAlarm(
          widget.busArrival.routeNo,
          widget.stationName ?? '정류장 정보 없음',
          remainingTime,
          routeId: routeId,
          useTTS: true,
          isImmediateAlarm: true,
          currentStation: firstBus.currentStation,
        );

        if (success && mounted) {
          // 버스 모니터링 서비스 시작 - stationId를 명시적으로 전달
          await _alarmService.startBusMonitoringService(
            routeId: routeId,
            stationId: stationId, // 명시적으로 stationId 전달
            stationName: widget.stationName ?? '정류장 정보 없음',
            busNo: widget.busArrival.routeNo,
          );

          // 알림 서비스 시작
          await _notificationService.showOngoingBusTracking(
            busNo: widget.busArrival.routeNo,
            stationName: widget.stationName ?? '정류장 정보 없음',
            remainingMinutes: remainingTime,
            currentStation: firstBus.currentStation,
            routeId: routeId,
          );

          // TTS 알림 즉시 시작 (일반 승차 알람용, useTts 설정 및 이어폰 연결 여부 확인)
          if (mounted) {
            final settings =
                Provider.of<SettingsService>(context, listen: false);
            if (!settings.useTts) {
              logMessage('🔇 일반 승차 알람 TTS 설정 비활성화 - TTS 건너뜀',
                  level: LogLevel.info);
            } else {
              final ttsSwitcher = TtsSwitcher();
              await ttsSwitcher.initialize();
              final headphoneConnected =
                  await ttsSwitcher.isHeadphoneConnected().catchError((e) {
                logMessage('❌ 이어폰 연결 상태 확인 오류: $e', level: LogLevel.error);
                return false; // 오류 발생 시 이어폰 미연결로 처리
              });

              if (headphoneConnected) {
                await TtsSwitcher.startTtsTracking(
                  routeId: routeId,
                  stationId: stationId, // 명시적으로 stationId 전달
                  busNo: widget.busArrival.routeNo,
                  stationName: widget.stationName ?? '정류장 정보 없음',
                );
              } else {
                logMessage('🎧 이어폰 미연결 - 승차 알람 TTS 건너뜀', level: LogLevel.info);
              }
            }
          }

          // 알람 상태 갱신
          await _alarmService.refreshAlarms();
          await _alarmService.loadAlarms();

          // hasBoarded 상태 초기화
          setState(() {
            hasBoarded = false;
          });

          // 버스 도착 정보 이후 다시 UI 새로고침 위해 지연
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {});
              _updateBusArrivalInfo(); // 정보 다시 불러오기
            }
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('승차 알람이 설정되었습니다')),
            );
          }

          logMessage('🚌 알람 설정 완료: ${widget.busArrival.routeNo}번 버스',
              level: LogLevel.debug);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('승차 알람 설정에 실패했습니다')),
          );
        }
      } catch (e) {
        logMessage('🚨 알람 설정 중 오류 발생: $e', level: LogLevel.error);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('알람 설정 중 오류가 발생했습니다: $e')),
          );
        }
      }
    }
  }

  Widget _showBoardingButton() {
    return ElevatedButton.icon(
      onPressed: () async {
        try {
          setState(() => hasBoarded = true);

          // 필요한 정보 미리 저장
          final busNo = widget.busArrival.routeNo;
          final stationName = widget.stationName ?? '정류장 정보 없음';
          final routeId = widget.busArrival.routeId;

          // 모든 취소 작업을 순차적으로 실행
          final success = await _alarmService.cancelAlarmByRoute(
            busNo,
            stationName,
            routeId,
          );

          if (success) {
            // 명시적으로 포그라운드 알림 취소
            await _notificationService.cancelOngoingTracking();

            // TTS 추적 중단
            await TtsSwitcher.stopTtsTracking(busNo);

            // 버스 모니터링 서비스 중지
            await _alarmService.stopBusMonitoringService();

            // 알람 상태 갱신
            await _alarmService.loadAlarms();
            await _alarmService.refreshAlarms();

            setState(() {});

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('승차 완료 처리되었습니다')),
              );
            }
          }
        } catch (e) {
          logMessage('승차 완료 처리 중 오류 발생: $e', level: LogLevel.error);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('승차 완료 처리 중 오류가 발생했습니다: $e')),
            );
          }
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

    // 자동 알람 설정 여부 확인
    final bool hasAutoAlarm = alarmService.hasAutoAlarm(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      widget.busArrival.routeId,
    );

    // 일반 승차 알람만 확인 (자동 알람 제외)
    final bool regularAlarmEnabled = alarmService.activeAlarms.any((alarm) =>
        alarm.busNo == widget.busArrival.routeNo &&
        alarm.stationName == (widget.stationName ?? '정류장 정보 없음') &&
        alarm.routeId == widget.busArrival.routeId);

    // 자동 알람이 있으면 승차 알람은 비활성화
    final bool alarmEnabled = !hasAutoAlarm && regularAlarmEnabled;

    logMessage(
        '🚌 버스카드 알람 상태: routeNo=${widget.busArrival.routeNo}, 자동알람=$hasAutoAlarm, 승차알람=$regularAlarmEnabled, 최종=$alarmEnabled');

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
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${widget.busArrival.routeNo}번 버스 - ${widget.stationName ?? "정류장 정보 없음"}',
                              style: const TextStyle(
                                  fontSize: 18, color: Colors.grey),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                          // 자동 알람 배지 추가
                          if (hasAutoAlarm)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.amber[300]!),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.schedule,
                                      size: 12, color: Colors.amber[800]),
                                  const SizedBox(width: 4),
                                  Text(
                                    '자동',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber[800],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
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
                    else if (hasAutoAlarm)
                      // 자동 알람 표시 - 개선된 디자인
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.amber[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber[200]!),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.amber.withAlpha(25),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.alarm_on,
                                    size: 16, color: Colors.amber[800]),
                                const SizedBox(width: 6),
                                Text(
                                  '자동 알람 설정됨',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.amber[800],
                                      fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            // 자동 알람 시간 정보 추가
                            FutureBuilder<String>(
                              future: _getAutoAlarmTimeInfo(alarmService),
                              builder: (context, snapshot) {
                                return Text(
                                  snapshot.data ?? '승차 알람을 사용할 수 없습니다',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.amber[700],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      )
                    else
                      const SizedBox.shrink(),
                    ElevatedButton.icon(
                      onPressed: firstBus.isOutOfService ||
                              alarmService.hasAutoAlarm(
                                  widget.busArrival.routeNo,
                                  widget.stationName ?? '정류장 정보 없음',
                                  widget.busArrival.routeId)
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
                        backgroundColor: firstBus.isOutOfService ||
                                alarmService.hasAutoAlarm(
                                    widget.busArrival.routeNo,
                                    widget.stationName ?? '정류장 정보 없음',
                                    widget.busArrival.routeId)
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

  // 자동 알람 시간 정보를 가져오는 메서드
  Future<String> _getAutoAlarmTimeInfo(AlarmService alarmService) async {
    try {
      // 자동 알람 정보 가져오기
      final autoAlarm = alarmService.getAutoAlarm(
        widget.busArrival.routeNo,
        widget.stationName ?? '정류장 정보 없음',
        widget.busArrival.routeId,
      );

      if (autoAlarm == null) {
        return '승차 알람을 사용할 수 없습니다';
      }

      // 알람 시간 포맷팅
      final scheduledTime = autoAlarm.scheduledTime;
      final hour = scheduledTime.hour.toString().padLeft(2, '0');
      final minute = scheduledTime.minute.toString().padLeft(2, '0');
      final timeStr = '$hour:$minute';

      // 자동 알람이 설정된 시간 표시
      return '$timeStr 자동 알람 설정됨';
    } catch (e) {
      logMessage('자동 알람 시간 정보 가져오기 오류: $e', level: LogLevel.error);
      return '승차 알람을 사용할 수 없습니다';
    }
  }
}
