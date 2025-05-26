import 'dart:async';
import 'package:flutter/material.dart';
// import 'package:flutter/services.dart'; // MethodChannel을 위해 추가 - REMOVED (Unnecessary)
import 'package:provider/provider.dart';
import '../services/alarm_service.dart';
import '../models/alarm_data.dart';
import '../main.dart' show logMessage, LogLevel;
import '../services/notification_service.dart';
import '../utils/tts_switcher.dart';
import '../services/api_service.dart';

class ActiveAlarmPanel extends StatefulWidget {
  const ActiveAlarmPanel({super.key});

  @override
  State<ActiveAlarmPanel> createState() => _ActiveAlarmPanelState();
}

class _ActiveAlarmPanelState extends State<ActiveAlarmPanel> {
  // 버스 위치 애니메이션을 위한 프로그레스 컨트롤러
  dynamic _progressTimer;

  @override
  void initState() {
    super.initState();
    // 컴포넌트 마운트 시 알람 데이터 최신화
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAlarms();
    });

    // AlarmService 리스너 등록 - 포그라운드 노티피케이션에서 취소 시 UI 업데이트
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    alarmService.addListener(_updateAlarmState);
  }

  // 알람 상태 변경 시 UI 업데이트
  void _updateAlarmState() {
    if (mounted) {
      setState(() {
        // UI 강제 갱신
      });
    }
  }

  Future<void> _initializeAlarms() async {
    if (!mounted) return;

    try {
      final alarmService = Provider.of<AlarmService>(context, listen: false);

      // 알람 로드 시도 (최대 3번)
      bool success = false;
      int retryCount = 0;
      const maxRetries = 3;

      while (!success && retryCount < maxRetries) {
        try {
          await alarmService.loadAlarms();
          success = true;
          if (mounted) setState(() {}); // 초기 로드 후 UI 갱신
        } catch (e) {
          retryCount++;
          logMessage('알람 로드 재시도 #$retryCount: $e', level: LogLevel.warning);
          if (retryCount < maxRetries) {
            await Future.delayed(Duration(seconds: retryCount * 2));
          }
        }
      }

      if (!success) {
        logMessage('알람 로드 실패 (최대 재시도 횟수 초과)', level: LogLevel.error);
        return;
      }

      // 30초마다 실시간 버스 정보 업데이트
      Timer.periodic(const Duration(seconds: 30), (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }

        try {
          // 활성화된 알람들의 실시간 정보 업데이트
          for (var alarm in alarmService.activeAlarms) {
            if (!mounted) break;

            // API를 통해 실시간 버스 도착 정보 가져오기
            final updatedBusArrivals = await ApiService.getBusArrivalByRouteId(
              alarm.routeId.split('_').last,
              alarm.routeId,
            );

            if (updatedBusArrivals.isNotEmpty &&
                updatedBusArrivals[0].busInfoList.isNotEmpty) {
              final firstBus = updatedBusArrivals[0].busInfoList.first;

              // 캐시 업데이트
              alarmService.updateBusInfoCache(
                alarm.busNo,
                alarm.routeId,
                firstBus,
                firstBus.getRemainingMinutes(),
              );

              logMessage(
                '실시간 버스 정보 업데이트: ${alarm.busNo}번, ${firstBus.getRemainingMinutes()}분 후 도착',
                level: LogLevel.debug,
              );
            }
          }

          // UI 갱신
          if (mounted) {
            setState(() {});
          }
        } catch (e) {
          logMessage('실시간 버스 정보 업데이트 오류: $e', level: LogLevel.error);
        }
      });

      // 버스 이동 애니메이션 타이머 설정
      _startProgressAnimation();
    } catch (e) {
      logMessage('알람 패널 초기화 오류: $e', level: LogLevel.error);
    }
  }

  void _startProgressAnimation() {
    // 기존 타이머가 있으면 취소
    _progressTimer?.cancel();

    // 버스 위치 실시간 시각화를 위한 타이머 설정
    const refreshRate = Duration(milliseconds: 50);

    // 프로그레스 업데이트 타이머 설정
    _progressTimer = Future.delayed(refreshRate, () {
      if (mounted) {
        setState(() {});
        _startProgressAnimation(); // 재귀적으로 다시 호출
      }
    });
  }

  @override
  void dispose() {
    _progressTimer?.cancel();

    // AlarmService 리스너 해제
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    alarmService.removeListener(_updateAlarmState);

    super.dispose();
  }

  // 알람 목록 아이템 위젯 생성 메서드
  Widget _buildAlarmListItem(AlarmData alarm, AlarmService alarmService) {
    // 자동 알람인지 확인 - 객체 비교 대신 필드 비교
    final isAutoAlarm = alarmService.autoAlarms.any((autoAlarm) =>
        autoAlarm.busNo == alarm.busNo &&
        autoAlarm.stationName == alarm.stationName &&
        autoAlarm.routeId == alarm.routeId);

    // 캐시된 정보를 가져와서 최신화
    final cachedBusInfo = alarmService.getCachedBusInfo(
      alarm.busNo,
      alarm.routeId,
    );

    // 남은 시간 계산 - 자동 알람과 일반 알람 구분
    int arrivalMinutes;
    String arrivalText;

    if (isAutoAlarm) {
      // 자동 알람의 경우 예약된 시간 표시
      final now = DateTime.now();
      final alarmTime = DateTime(
        now.year,
        now.month,
        now.day,
        alarm.scheduledTime.hour,
        alarm.scheduledTime.minute,
      );

      // 오늘 알람 시간이 지났는지 확인
      if (now.isAfter(alarmTime)) {
        // 다음 날 알람 시간 계산
        final tomorrow = DateTime(now.year, now.month, now.day + 1,
            alarm.scheduledTime.hour, alarm.scheduledTime.minute);
        arrivalMinutes = tomorrow.difference(now).inMinutes;
        arrivalText = '다음 알람: ${_getFormattedTime(alarm.scheduledTime)}';
      } else {
        arrivalMinutes = alarmTime.difference(now).inMinutes;
        if (arrivalMinutes <= 0) {
          arrivalText =
              '알람 시간: ${_getFormattedTime(alarm.scheduledTime)} (진행 중)';
        } else {
          arrivalText =
              '알람 시간: ${_getFormattedTime(alarm.scheduledTime)} ($arrivalMinutes분 후)';
        }
      }
    } else if (cachedBusInfo != null) {
      // 일반 알람의 경우 실시간 도착 정보 사용
      arrivalMinutes = cachedBusInfo.getRemainingMinutes();
      arrivalText = arrivalMinutes <= 1 ? '곧 도착' : '$arrivalMinutes분 후 도착';
      logMessage(
          '패널 표시 시간 계산: 버스=${alarm.busNo}, 마지막 갱신 시간=${cachedBusInfo.lastUpdated.toString()}, 남은 시간=$arrivalMinutes분',
          level: LogLevel.debug);
    } else {
      arrivalMinutes = alarm.getCurrentArrivalMinutes();
      arrivalText = arrivalMinutes <= 1 ? '곧 도착' : '$arrivalMinutes분 후 도착';
      logMessage(
          '패널 표시 시간 계산: 버스=${alarm.busNo}, 캐시 없음, 알람 시간=$arrivalMinutes분',
          level: LogLevel.debug);
    }

    // 버스 현재 위치 정보 (캐시에서 최신 정보 가져오기)
    String? currentStation =
        cachedBusInfo?.currentStation ?? alarm.currentStation;
    String locationText = '';
    if (!isAutoAlarm && currentStation != null && currentStation.isNotEmpty) {
      locationText = ' ($currentStation)';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // 알람 아이콘 - 자동 알람은 다른 아이콘 사용
          Icon(
            isAutoAlarm ? Icons.schedule : Icons.alarm,
            color: isAutoAlarm
                ? Colors.blue
                : (arrivalMinutes <= 3 ? Colors.red : Colors.orange),
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${alarm.busNo}번 버스 - ${alarm.stationName}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (isAutoAlarm) ...[
                      // 자동 알람 표시
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '자동',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  '$arrivalText$locationText',
                  style: TextStyle(
                    fontSize: 14,
                    color: isAutoAlarm
                        ? Colors.blue[700]
                        : (arrivalMinutes <= 3 ? Colors.red : Colors.black87),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          // 알람 취소 버튼
          GestureDetector(
            onTap: () => _showCancelDialog(alarm, alarmService),
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Icon(
                Icons.close,
                color: Colors.red[700],
                size: 20,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 17),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () {
              logMessage("알람 목록 새로고침 요청", level: LogLevel.debug);
              alarmService.loadAlarms();
              alarmService.loadAutoAlarms(); // 자동 알람도 새로고침
            },
            tooltip: '알람 목록 새로고침',
          ),
        ],
      ),
    );
  }

  // 알람 취소 다이얼로그 표시 메서드
  Future<void> _showCancelDialog(
      AlarmData alarm, AlarmService alarmService) async {
    // 자동 알람인지 확인
    final isAutoAlarm = alarmService.autoAlarms.contains(alarm);
    final alarmType = isAutoAlarm ? '자동 알람' : '승차 알람';
    final actionText = isAutoAlarm ? '해제' : '취소';

    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$alarmType $actionText'),
        content: Text('${alarm.busNo}번 버스 $alarmType을 $actionText하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('확인'),
          ),
        ],
      ),
    );

    if (confirmDelete == true && context.mounted) {
      try {
        logMessage('${alarm.busNo}번 버스 $alarmType $actionText 시작',
            level: LogLevel.info);

        // 필요한 정보 미리 저장
        final busNo = alarm.busNo;
        final stationName = alarm.stationName;
        final routeId = alarm.routeId;

        bool success = false;

        if (isAutoAlarm) {
          // 자동 알람 해제
          logMessage('🗓️ 자동 알람 해제 시작: $busNo번', level: LogLevel.info);
          success =
              await alarmService.stopAutoAlarm(busNo, stationName, routeId);

          if (success) {
            logMessage('✅ 자동 알람 해제 성공: $busNo번', level: LogLevel.info);
          } else {
            logMessage('❌ 자동 알람 해제 실패: $busNo번', level: LogLevel.error);
          }
        } else {
          // 일반 알람 취소
          logMessage('🚌 일반 알람 취소 시작: $busNo번', level: LogLevel.info);
          success = await alarmService.cancelAlarmByRoute(
              busNo, stationName, routeId);

          if (success) {
            // 명시적으로 포그라운드 알림 취소
            final notificationService = NotificationService();
            await notificationService.cancelOngoingTracking();

            // TTS 추적 중단
            await TtsSwitcher.stopTtsTracking(busNo);

            // 버스 모니터링 서비스 중지
            await alarmService.stopBusMonitoringService();

            logMessage('✅ 일반 알람 취소 성공: $busNo번', level: LogLevel.info);
          } else {
            logMessage('❌ 일반 알람 취소 실패: $busNo번', level: LogLevel.error);
          }
        }

        // 알람 상태 갱신
        await alarmService.loadAlarms();
        await alarmService.loadAutoAlarms();
        await alarmService.refreshAlarms();

        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text('${alarm.busNo}번 버스 $alarmType이 $actionText되었습니다')),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      '${alarm.busNo}번 버스 $alarmType $actionText에 실패했습니다')),
            );
          }
        }
      } catch (e) {
        logMessage('알람 취소 중 오류 발생: $e', level: LogLevel.error);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('알람 $actionText 중 오류가 발생했습니다: $e')),
          );
        }
      }
    }
  }

  // 시간을 HH:mm 형식으로 포맷팅하는 헬퍼 함수
  String _getFormattedTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AlarmService>(
      builder: (context, alarmService, child) {
        // 일반 알람과 자동 알람 모두 표시
        final activeAlarms = alarmService.activeAlarms;
        final autoAlarms = alarmService.autoAlarms;

        // 전체 알람 목록 합치기 (정렬: 시간순)
        final allAlarms = <AlarmData>[
          ...activeAlarms,
          ...autoAlarms,
        ]..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

        // 알람 정보 로깅
        logMessage('📊 알람 현황:', level: LogLevel.debug);
        logMessage('  - 일반 알람: ${activeAlarms.length}개', level: LogLevel.debug);
        logMessage('  - 자동 알람: ${autoAlarms.length}개', level: LogLevel.debug);
        logMessage('  - 전체 알람: ${allAlarms.length}개', level: LogLevel.debug);

        // 알람이 없는 경우
        if (allAlarms.isEmpty) {
          return Container(
            width: double.infinity,
            color: Colors.yellow[50],
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: const Center(
              child: Text(
                '예약된 알람이 없습니다.',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          );
        }

        // 알람이 있는 경우 - 첫 번째 알람에 대한 상세 패널 표시
        final firstAlarm = allAlarms.first;

        // routeId가 비어있으면 기본값 설정
        final String routeId = firstAlarm.routeId.isNotEmpty
            ? firstAlarm.routeId
            : '${firstAlarm.busNo}_${firstAlarm.stationName}';

        // 캐시된 정보를 가져와서 최신화
        final cachedBusInfo = alarmService.getCachedBusInfo(
          firstAlarm.busNo,
          routeId,
        );

        // 남은 시간 계산
        int remainingMinutes;
        if (cachedBusInfo != null) {
          // 실시간 도착 정보 사용
          remainingMinutes = cachedBusInfo.getRemainingMinutes();
          logMessage(
              '버스 도착 정보 (캐시): ${firstAlarm.busNo}번, $remainingMinutes분 후',
              level: LogLevel.debug);
        } else {
          remainingMinutes = firstAlarm.getCurrentArrivalMinutes();
          logMessage(
              '버스 도착 정보 (예약): ${firstAlarm.busNo}번, $remainingMinutes분 후',
              level: LogLevel.debug);
        }

        final isArrivingSoon = remainingMinutes <= 2;
        final progress =
            (remainingMinutes > 30) ? 0.0 : (30 - remainingMinutes) / 30.0;

        // 도착 정보 텍스트 설정
        final arrivalText = isArrivingSoon ? '곧 도착' : '$remainingMinutes분 후 도착';

        // 버스 현재 위치 정보 표시
        String currentStation = '정보 업데이트 중...';
        if (cachedBusInfo?.currentStation != null &&
            cachedBusInfo!.currentStation.isNotEmpty) {
          currentStation = cachedBusInfo.currentStation;
        } else if (firstAlarm.currentStation != null &&
            firstAlarm.currentStation!.isNotEmpty) {
          currentStation = firstAlarm.currentStation!;
        }

        // 메인 패널 생성
        final mainPanel = Container(
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isArrivingSoon
                  ? [Colors.red.shade100, Colors.red.shade50]
                  : [Colors.blue.shade100, Colors.blue.shade50],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(26),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          child: Column(
            children: [
              // 버스 정보 헤더
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.directions_bus_rounded,
                        color:
                            isArrivingSoon ? Colors.red[700] : Colors.blue[700],
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${firstAlarm.busNo}번 버스',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isArrivingSoon
                              ? Colors.red[700]
                              : Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // 새로고침 버튼
                      IconButton(
                        icon: Icon(
                          Icons.refresh,
                          color: Colors.blue[700],
                          size: 18,
                        ),
                        onPressed: () {
                          alarmService.loadAlarms();
                        },
                        tooltip: '정보 새로고침',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 12),
                      // 중지 버튼
                      IconButton(
                        icon: Icon(
                          Icons.stop_circle,
                          color: Colors.red[700],
                          size: 20,
                        ),
                        onPressed: () =>
                            _showCancelDialog(firstAlarm, alarmService),
                        tooltip: '추적 중지',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 정류장 및 도착 정보
              Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withAlpha(179),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 정류장 정보
                    Text(
                      '${firstAlarm.stationName} 정류장까지',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 도착 시간 정보
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_filled,
                          color: isArrivingSoon ? Colors.red : Colors.blue[700],
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          arrivalText,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color:
                                isArrivingSoon ? Colors.red : Colors.blue[700],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // 버스 위치 정보
                    if (currentStation.isNotEmpty)
                      Row(
                        children: [
                          Icon(
                            Icons.location_on,
                            color: Colors.blue[700],
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '현재 위치: $currentStation',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[800],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),

                    const SizedBox(height: 10),

                    // 진행률 표시 프로그레스 바
                    Stack(
                      children: [
                        // 배경 프로그레스 바
                        Container(
                          width: double.infinity,
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        // 진행 프로그레스 바
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: MediaQuery.of(context).size.width *
                              progress *
                              0.85,
                          height: 6,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: isArrivingSoon
                                  ? [Colors.red, Colors.orange]
                                  : [Colors.blue, Colors.lightBlue],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                        // 버스 위치 애니메이션
                        Positioned(
                          left: MediaQuery.of(context).size.width *
                                  progress *
                                  0.85 -
                              8,
                          top: -4,
                          child: Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              color: isArrivingSoon ? Colors.red : Colors.blue,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withAlpha(77),
                                  blurRadius: 2,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.directions_bus,
                              color: Colors.white,
                              size: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

        // 알람이 여러 개인 경우 추가 알람 목록 표시
        if (allAlarms.length > 1) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              mainPanel,
              Container(
                width: double.infinity,
                color: Colors.yellow[100],
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '추가 알람',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...allAlarms.skip(1).map(
                        (alarm) => _buildAlarmListItem(alarm, alarmService)),
                  ],
                ),
              ),
            ],
          );
        }

        // 알람이 하나만 있는 경우 메인 패널만 표시
        return mainPanel;
      },
    );
  }
}
