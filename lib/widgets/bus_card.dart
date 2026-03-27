import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:daegu_bus_app/models/bus_arrival.dart';
import 'package:daegu_bus_app/models/bus_info.dart';
import 'package:daegu_bus_app/services/alarm_service.dart';
import 'package:daegu_bus_app/services/notification_service.dart';
import 'package:daegu_bus_app/services/api_service.dart';
import 'package:daegu_bus_app/utils/tts_switcher.dart';
import 'package:daegu_bus_app/main.dart' show logMessage, LogLevel;
import 'package:daegu_bus_app/services/settings_service.dart';
import '../services/alarm_manager.dart';

const String stationTrackingChannel =
    'com.devground.daegubus/station_tracking';

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
  TtsSwitcher.startTtsTracking(
    routeId: routeId,
    stationId: stationId,
    busNo: busNo,
    stationName: stationName,
    remainingMinutes: remainingMinutes,
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
  late AlarmService _alarmService;
  bool _isOutOfServiceText(String value) {
    return value == '운행종료' || value == '운행 종료';
  }

  @override
  void initState() {
    super.initState();
    _alarmService = Provider.of<AlarmService>(context, listen: false);
    _checkInitialAlarmState();
    if (widget.busArrival.busInfoList.isNotEmpty) {
      firstBus = widget.busArrival.busInfoList.first;
      remainingTime = _calculateRemainingTime();
      _updateAlarmServiceCache();

    }

    _alarmService.addListener(_updateAlarmState);
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

      if (mounted) {
        if (updatedBusArrivals.isNotEmpty &&
            updatedBusArrivals[0].busInfoList.isNotEmpty) {
          final updatedBusArrival = updatedBusArrivals[0];
          setState(() {
            // 기존 버스 정보를 업데이트된 정보로 교체하지 말고,
            // 유효한 정보만 업데이트
            final newFirstBus = updatedBusArrival.busInfoList.first;
            if (!newFirstBus.isOutOfService ||
                !_isOutOfServiceText(newFirstBus.estimatedTime)) {
              firstBus = newFirstBus;
              remainingTime = firstBus.getRemainingMinutes();
            }

            logMessage(
                '🚌 BusCard 업데이트: ${widget.busArrival.routeNo}번, $remainingTime분, 상태: ${firstBus.estimatedTime}',
                level: LogLevel.debug);

            final hasAlarm = _alarmService.hasAlarm(
              widget.busArrival.routeNo,
              widget.stationName ?? '정류장 정보 없음',
              widget.busArrival.routeId,
            );

            if (hasAlarm) {
              _alarmService.updateBusInfoCache(
                widget.busArrival.routeNo,
                widget.busArrival.routeId,
                firstBus,
                remainingTime,
              );

              if (!hasBoarded && remainingTime <= 3 && remainingTime > 0) {
                _playAlarm();
              }

              final bool hasActiveTracking = _alarmService.hasAlarm(
                widget.busArrival.routeNo,
                widget.stationName ?? '정류장 정보 없음',
                widget.busArrival.routeId,
              );

              if (hasActiveTracking) {
                _notificationService.updateBusTrackingNotification(
                  busNo: widget.busArrival.routeNo,
                  stationName: widget.stationName ?? '정류장 정보 없음',
                  remainingMinutes: remainingTime,
                  currentStation: firstBus.currentStation,
                  routeId: widget.busArrival.routeId,
                  stationId: widget.stationId,
                );
              }
            }

            // 다음 버스 처리도 개선
            if (!hasBoarded &&
                remainingTime <= 0 &&
                updatedBusArrival.busInfoList.length > 1) {
              final nextBus = updatedBusArrival.busInfoList[1];
              if (!nextBus.isOutOfService) {
                int nextRemainingTime = nextBus.getRemainingMinutes();
                _setNextBusAlarm(nextRemainingTime, nextBus.currentStation);
              }
            }
          });
        } else {
          // 업데이트된 정보가 없어도 기존 정보 유지
          logMessage(
              '🚌 업데이트된 버스 정보 없음, 기존 정보 유지: ${widget.busArrival.routeNo}번',
              level: LogLevel.warning);
        }
        setState(() => _isUpdating = false);
      }
    } catch (e) {
      logMessage('❌ 버스 도착 정보 업데이트 오류: $e', level: LogLevel.error);
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  void _updateAlarmServiceCache() {
    try {
      // 유효한 버스 정보만 캐시에 저장
      if (!firstBus.isOutOfService &&
          remainingTime > 0 &&
          !_isOutOfServiceText(firstBus.estimatedTime) &&
          firstBus.estimatedTime.isNotEmpty) {
        logMessage(
            '🚌 버스 정보 캐시 업데이트: ${widget.busArrival.routeNo}번, $remainingTime분 후, 상태: ${firstBus.estimatedTime}',
            level: LogLevel.debug);
        _alarmService.updateBusInfoCache(
          widget.busArrival.routeNo,
          widget.busArrival.routeId,
          firstBus,
          remainingTime,
        );
      } else {
        logMessage(
            '🚌 캐시 업데이트 생략 - 무효한 버스 정보: ${widget.busArrival.routeNo}번, 운행종료: ${firstBus.isOutOfService}, 시간: $remainingTime',
            level: LogLevel.debug);
      }
    } catch (e) {
      logMessage('❌ 캐시 업데이트 오류: $e', level: LogLevel.error);
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
      final autoAlarm = _alarmService.getAutoAlarm(
        widget.busArrival.routeNo,
        widget.stationName ?? '정류장 정보 없음',
        widget.busArrival.routeId,
      );
      if (autoAlarm != null) {
        final remaining =
            autoAlarm.scheduledTime.difference(DateTime.now()).inMinutes;
        logMessage('🚌 자동 알람 남은 시간: $remaining분', level: LogLevel.debug);
        return remaining;
      }
    }

    final remaining = firstBus.getRemainingMinutes();
    logMessage('🚌 실시간 도착 남은 시간: $remaining분', level: LogLevel.debug);
    return remaining;
  }

  Future<void> _checkInitialAlarmState() async {
    try {
      final isActive = await AlarmManager.isAlarmActive(
        busNo: widget.busArrival.routeNo,
        stationName: widget.stationName ?? '정류장 정보 없음',
        routeId: widget.busArrival.routeId,
      );

      if (mounted && isActive) {
        setState(() {});
      }
    } catch (e) {
      logMessage('❌ [ERROR] 초기 알람 상태 확인 실패: $e', level: LogLevel.error);
    }
  }

  void _updateAlarmState() {
    if (mounted) {
      setState(() {
        if (!_alarmService.isInTrackingMode) {
          hasBoarded = false;
          _updateBusArrivalInfo();
          logMessage(
              '📣 UI 강제 업데이트 - 추적중 = ${_alarmService.isInTrackingMode}, hasBoarded 초기화',
              level: LogLevel.debug);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _alarmService.removeListener(_updateAlarmState);
    super.dispose();
    logMessage('타이머 취소 및 리소스 해제', level: LogLevel.debug);
  }

  void _playAlarm() {
    int notificationId =
        ("${widget.busArrival.routeNo}_${widget.stationName ?? '정류장 정보 없음'}_${widget.busArrival.routeId}")
            .hashCode;
    _notificationService.showNotification(
      id: notificationId,
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
    final String routeId = widget.busArrival.routeId.isNotEmpty
        ? widget.busArrival.routeId
        : '${widget.busArrival.routeNo}_${widget.stationId}';

    logMessage('🚌 다음 버스 알람 설정 - 사용할 routeId: $routeId', level: LogLevel.debug);

    int notificationId =
        ("${widget.busArrival.routeNo}_${widget.stationName ?? '정류장 정보 없음'}_$routeId")
            .hashCode;

    if (widget.stationName == null || widget.stationName!.isEmpty) {
      logMessage('🚌 정류장 정보가 없습니다. 알람을 설정할 수 없습니다.', level: LogLevel.error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('정류장 정보가 없습니다. 알람을 설정할 수 없습니다.')),
        );
      }
      return;
    }

    logMessage(
      '🚌 다음 버스 알람 설정: ${widget.busArrival.routeNo}번 버스, $nextRemainingTime분 후 도착 예정, 알람ID: $notificationId',
      level: LogLevel.debug,
    );
    logMessage('🚌 예상 도착 시간: $arrivalTime', level: LogLevel.debug);

    bool success = await _alarmService.setOneTimeAlarm(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      nextRemainingTime,
      routeId: routeId,
      stationId: widget.stationId,
      useTTS: true,
      isImmediateAlarm: false,
      currentStation: currentStation,
    );

    if (success && mounted) {
      await _alarmService.refreshAlarms();
      await _alarmService.loadAlarms();
      setState(() {});

      await _alarmService.startBusMonitoringService(
        stationId: widget.stationId,
        stationName: widget.stationName ?? '정류장 정보 없음',
        routeId: routeId,
        busNo: widget.busArrival.routeNo,
      );

      if (!mounted) return;
      final settings = Provider.of<SettingsService>(context, listen: false);
      final ttsSwitcher = TtsSwitcher();
      await ttsSwitcher.initialize();
      if (!mounted) return;
      final headphoneConnected =
          await ttsSwitcher.isHeadphoneConnected().catchError((e) {
        logMessage('이어폰 연결 상태 확인 중 오류: $e', level: LogLevel.error);
        return false;
      });

      if (settings.speakerMode == SettingsService.speakerModeHeadset) {
        if (headphoneConnected) {
          await TtsSwitcher.startTtsTracking(
            routeId: routeId,
            stationId: widget.stationId,
            busNo: widget.busArrival.routeNo,
            stationName: widget.stationName ?? '정류장 정보 없음',
            remainingMinutes: remainingTime,
          );
        } else {
          logMessage('🎧 이어폰 미연결 - 이어폰 전용 모드에서 TTS 실행 안함',
              level: LogLevel.info);
        }
      } else {
        await TtsSwitcher.startTtsTracking(
          routeId: routeId,
          stationId: widget.stationId,
          busNo: widget.busArrival.routeNo,
          stationName: widget.stationName ?? '정류장 정보 없음',
          remainingMinutes: remainingTime,
        );
      }

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
      try {
        logMessage(
          '🔔 승차 알람 취소 시도 - 노선 번호: ${widget.busArrival.routeNo}, 정류장: ${widget.stationName}',
          level: LogLevel.debug,
        );

        final stationName = widget.stationName ?? '정류장 정보 없음';
        final busNo = widget.busArrival.routeNo;
        final routeId = widget.busArrival.routeId;

        setState(() {});

        // 1. 네이티브 추적 중지 (개별 버스만)
        await _stopSpecificNativeTracking();

        // 2. AlarmManager에서 알람 취소
        await AlarmManager.cancelAlarm(
          busNo: busNo,
          stationName: stationName,
          routeId: routeId,
        );

        // 3. AlarmService에서 알람 취소
        final success =
            await _alarmService.cancelAlarmByRoute(busNo, stationName, routeId);
        if (success) {
          // 4. TTS 추적 중단 (개별 버스만)
          await TtsSwitcher.stopTtsTracking(busNo);

          // 5. 알람 상태 갱신
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
      try {
        logMessage('🚌 V2 승차 알람 토글 시작', level: LogLevel.debug);
        logMessage(
          '🚌 버스 정보: 노선번호=${widget.busArrival.routeNo}, 정류장=${widget.stationName}, 남은시간=$remainingTime',
          level: LogLevel.debug,
        );

        final String routeId = widget.busArrival.routeId.isNotEmpty
            ? widget.busArrival.routeId
            : '${widget.busArrival.routeNo}_${widget.stationId}';

        logMessage('🚌 사용할 routeId: $routeId, stationId: $stationId',
            level: LogLevel.debug);

        final activeAlarms = _alarmService.activeAlarms;
        for (var alarm in activeAlarms) {
          if (alarm.stationName == widget.stationName &&
              alarm.busNo != widget.busArrival.routeNo) {
            logMessage('🚌 동일 정류장의 다른 버스(${alarm.busNo}) 알람 해제 시도',
                level: LogLevel.info);
            try {
              final success = await _alarmService.cancelAlarmByRoute(
                alarm.busNo,
                alarm.stationName,
                alarm.routeId,
              );
              if (success) {
                await TtsSwitcher.stopTtsTracking(alarm.busNo);
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

        int notificationId =
            ("${widget.busArrival.routeNo}_${widget.stationName ?? '정류장 정보 없음'}_$routeId")
                .hashCode;

        logMessage(
          '🚌 알람 설정 시작: ${widget.busArrival.routeNo}번 버스, ${widget.stationName}, 알람ID: $notificationId, stationId: $stationId',
          level: LogLevel.debug,
        );

        DateTime arrivalTime =
            DateTime.now().add(Duration(minutes: remainingTime));
        logMessage('🚌 예상 도착 시간: $arrivalTime', level: LogLevel.debug);

        setState(() {});
        await AlarmManager.addAlarm(
          busNo: widget.busArrival.routeNo,
          stationName: widget.stationName ?? '정류장 정보 없음',
          routeId: routeId,
          wincId: widget.stationId,
        );
        await _startNativeTracking();

        bool success = await _alarmService.setOneTimeAlarm(
          widget.busArrival.routeNo,
          widget.stationName ?? '정류장 정보 없음',
          remainingTime,
          routeId: routeId,
          stationId: widget.stationId,
          useTTS: true,
          isImmediateAlarm: true,
          currentStation: firstBus.currentStation,
        );

        if (success && mounted) {
          await _alarmService.startBusMonitoringService(
            routeId: routeId,
            stationId: stationId,
            stationName: widget.stationName ?? '정류장 정보 없음',
            busNo: widget.busArrival.routeNo,
          );

          if (!mounted) return;
          final settings = Provider.of<SettingsService>(context, listen: false);
          final ttsSwitcher = TtsSwitcher();
          await ttsSwitcher.initialize();
          if (!mounted) return;
          final headphoneConnected =
              await ttsSwitcher.isHeadphoneConnected().catchError((e) {
            logMessage('이어폰 연결 상태 확인 중 오류: $e', level: LogLevel.error);
            return false;
          });

          if (settings.speakerMode == SettingsService.speakerModeHeadset) {
            if (headphoneConnected) {
              await TtsSwitcher.startTtsTracking(
                routeId: routeId,
                stationId: stationId,
                busNo: widget.busArrival.routeNo,
                stationName: widget.stationName ?? '정류장 정보 없음',
                remainingMinutes: remainingTime,
              );
            } else {
              logMessage('🎧 이어폰 미연결 - 이어폰 전용 모드에서 TTS 실행 안함',
                  level: LogLevel.info);
            }
          } else {
            await TtsSwitcher.startTtsTracking(
              routeId: routeId,
              stationId: stationId,
              busNo: widget.busArrival.routeNo,
              stationName: widget.stationName ?? '정류장 정보 없음',
              remainingMinutes: remainingTime,
            );
          }

          await _alarmService.refreshAlarms();
          await _alarmService.loadAlarms();

          setState(() {
            hasBoarded = false;
          });

          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              setState(() {});
              _updateBusArrivalInfo();
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
          final busNo = widget.busArrival.routeNo;
          final stationName = widget.stationName ?? '정류장 정보 없음';
          final routeId = widget.busArrival.routeId;

          // 1. 네이티브 추적 중지 (개별 버스만)
          await _stopSpecificNativeTracking();

          // 2. AlarmManager에서 알람 취소
          await AlarmManager.cancelAlarm(
            busNo: busNo,
            stationName: stationName,
            routeId: routeId,
          );

          // 3. AlarmService에서 알람 취소
          final success = await _alarmService.cancelAlarmByRoute(
              busNo, stationName, routeId);

          if (success) {
            // 4. TTS 추적 중단 (개별 버스만)
            await TtsSwitcher.stopTtsTracking(busNo);

            // 5. 알람 상태 갱신
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
        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green[600],
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28), // Material 3 Expressive
          side: BorderSide(color: Colors.green.shade800, width: 1),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
              Text('도착 정보를 불러오는 중...',
                  style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }

    // 상태 업데이트 시 기존 데이터 보존
    if (widget.busArrival.busInfoList.isNotEmpty) {
      final newFirstBus = widget.busArrival.busInfoList.first;
      // 유효한 정보가 있을 때만 업데이트
      if (!newFirstBus.isOutOfService ||
          (!_isOutOfServiceText(newFirstBus.estimatedTime) &&
              newFirstBus.estimatedTime.isNotEmpty)) {
        firstBus = newFirstBus;
        remainingTime = firstBus.getRemainingMinutes();
      }
    }

    final String currentStationText = firstBus.currentStation.trim().isNotEmpty
        ? firstBus.currentStation
        : "정보 업데이트 중";

    logMessage(
        '🚌 BusCard 빌드: ${widget.busArrival.routeNo}번, $remainingTime분, 상태: ${firstBus.estimatedTime}, 운행종료: ${firstBus.isOutOfService}',
        level: LogLevel.debug);

    String arrivalTimeText;
    if (firstBus.isOutOfService) {
      arrivalTimeText = '운행 종료';
    } else if (remainingTime <= 0) {
      arrivalTimeText = '곧 도착';
    } else {
      arrivalTimeText = '$remainingTime분';
    }

    final alarmService = Provider.of<AlarmService>(context, listen: true);
    final bool hasAutoAlarm = alarmService.hasAutoAlarm(
      widget.busArrival.routeNo,
      widget.stationName ?? '정류장 정보 없음',
      widget.busArrival.routeId,
    );
    final bool regularAlarmEnabled = alarmService.activeAlarms.any((alarm) =>
        alarm.busNo == widget.busArrival.routeNo &&
        alarm.stationName == (widget.stationName ?? '정류장 정보 없음') &&
        alarm.routeId == widget.busArrival.routeId);
    final bool alarmEnabled = !hasAutoAlarm && regularAlarmEnabled;

    logMessage(
      '🚌 버스카드 알람 상태: routeNo=${widget.busArrival.routeNo}, 자동알람=$hasAutoAlarm, 승차알람=$regularAlarmEnabled, 최종=$alarmEnabled',
      level: LogLevel.debug,
    );

    return Semantics(
      label: '${widget.busArrival.routeNo}번 버스 정보',
      hint: firstBus.isOutOfService
          ? '운행이 종료된 버스입니다'
          : '$arrivalTimeText에 도착 예정이며, 현재 위치는 $currentStationText입니다',
      child: Container(
        margin: const EdgeInsets.only(bottom: 20), // More spacing
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32), // Very rounded
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha((255 * 0.08).round()),
              blurRadius: 20,
              offset: const Offset(0, 6),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Card(
          margin: EdgeInsets.zero,
          elevation: 0, // Elevation is in BoxDecoration shadow
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(32),
            side: BorderSide.none, // NO BORDER - Material You
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              borderRadius: BorderRadius.circular(32),
              child: Padding(
                padding: const EdgeInsets.all(24), // Generous padding
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.location_on,
                          color: Colors.grey, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${widget.busArrival.routeNo}번 버스 - ${widget.stationName ?? "정류장 정보 없음"}',
                                style: TextStyle(
                                    fontSize: 18,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurface),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
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
                          style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                          textAlign: TextAlign.right,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  LinearProgressIndicator(
                    value: 0.6,
                    backgroundColor: Colors.grey[200],
                    color: firstBus.isOutOfService
                        ? Colors.grey
                        : Colors.blue[500],
                    borderRadius: BorderRadius.circular(4),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            firstBus.isOutOfService ? '버스 상태' : '도착예정',
                            style: TextStyle(
                                fontSize: 14,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
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
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                        ],
                      ),
                      if (widget.busArrival.busInfoList.length > 1)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('다음 버스',
                                style: TextStyle(
                                    fontSize: 14,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                            Text(
                              widget.busArrival.busInfoList[1].isOutOfService
                                  ? '운행 종료'
                                  : '${widget.busArrival.busInfoList[1].getRemainingMinutes()}분',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      else if (hasAutoAlarm)
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
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              FutureBuilder<String>(
                                future: _getAutoAlarmTimeInfo(alarmService),
                                builder: (context, snapshot) {
                                  return Text(
                                    snapshot.data ?? '승차 알람을 사용할 수 없습니다',
                                    style: TextStyle(
                                        fontSize: 11, color: Colors.amber[700]),
                                  );
                                },
                              ),
                            ],
                          ),
                        )
                      else
                        const SizedBox.shrink(),
                      Semantics(
                        label: alarmEnabled ? '승차 알람 해제' : '승차 알람 설정',
                        hint: alarmEnabled
                            ? '현재 설정된 승차 알람을 해제합니다'
                            : '${widget.busArrival.routeNo}번 버스 승차 알람을 설정합니다',
                        child: ElevatedButton.icon(
                          onPressed: firstBus.isOutOfService ||
                                  alarmService.hasAutoAlarm(
                                      widget.busArrival.routeNo,
                                      widget.stationName ?? '정류장 정보 없음',
                                      widget.busArrival.routeId)
                              ? null
                              : () async {
                                  // 햅틱 피드백 추가
                                  HapticFeedback.lightImpact();

                                  await _toggleBoardingAlarm();
                                  setState(() {});
                                },
                          icon: Icon(
                            alarmEnabled
                                ? Icons.notifications_active
                                : Icons.notifications_none,
                            color: Colors.white,
                            size: 20,
                          ),
                          label: Text(
                            alarmEnabled ? '알람 해제' : '승차 알람',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
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
                                    ? Colors.yellow[700]
                                    : Colors.blue[600]),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 0),
                            minimumSize: const Size(100, 40),
                            elevation: alarmEnabled ? 4 : 2,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (alarmEnabled &&
                      !hasBoarded &&
                      !firstBus.isOutOfService &&
                      remainingTime <= 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: _showBoardingButton(),
                    ),
                  if (widget.busArrival.busInfoList.length > 1) ...[
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 16),
                    ...widget.busArrival.busInfoList.skip(1).map<Widget>((bus) {
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
                                          borderRadius:
                                              BorderRadius.circular(8),
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
                                  isOutOfService
                                      ? '운행 종료'
                                      : '$nextRemainingMin분',
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
                                  fontSize: 13, color: Colors.grey[600]),
                            ),
                            Text(
                              bus.remainingStops,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[500]),
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
      ),
        ),
      ),
    );
  }

  Future<String> _getAutoAlarmTimeInfo(AlarmService alarmService) async {
    try {
      final autoAlarm = alarmService.getAutoAlarm(
        widget.busArrival.routeNo,
        widget.stationName ?? '정류장 정보 없음',
        widget.busArrival.routeId,
      );

      if (autoAlarm == null) {
        return '승차 알람을 사용할 수 없습니다';
      }

      final scheduledTime = autoAlarm.scheduledTime;
      final hour = scheduledTime.hour.toString().padLeft(2, '0');
      final minute = scheduledTime.minute.toString().padLeft(2, '0');
      final timeStr = '$hour:$minute';

      return '$timeStr 자동 알람 설정됨';
    } catch (e) {
      logMessage('자동 알람 시간 정보 가져오기 오류: $e', level: LogLevel.error);
      return '승차 알람을 사용할 수 없습니다';
    }
  }

  Future<void> _stopSpecificNativeTracking() async {
    try {
      const platform = MethodChannel('com.devground.daegubus/bus_api');
      await platform.invokeMethod('stopSpecificTracking', {
        'busNo': widget.busArrival.routeNo,
        'routeId': widget.busArrival.routeId,
        'stationName': widget.stationName ?? '정류장 정보 없음',
      });
      logMessage('🔔 ✅ 네이티브 특정 추적 중지 요청 완료', level: LogLevel.info);
    } catch (e) {
      logMessage('❌ [ERROR] 네이티브 특정 추적 중지 실패: $e', level: LogLevel.error);
    }
  }

  Future<void> _startNativeTracking() async {
    try {
      const platform = MethodChannel('com.devground.daegubus/bus_api');
      await platform.invokeMethod('startBusTrackingService', {
        'busNo': widget.busArrival.routeNo,
        'stationName': widget.stationName ?? '정류장 정보 없음',
        'routeId': widget.busArrival.routeId,
      });
      logMessage('🔔 ✅ 네이티브 추적 시작 요청 완료', level: LogLevel.info);
    } catch (e) {
      logMessage('❌ [ERROR] 네이티브 추적 시작 실패: $e', level: LogLevel.error);
      rethrow;
    }
  }
}
