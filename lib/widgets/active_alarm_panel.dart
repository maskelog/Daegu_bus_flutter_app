import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/alarm_service.dart';
import '../main.dart' show logMessage, LogLevel;

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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final alarmService = Provider.of<AlarmService>(context, listen: false);
      await alarmService.loadAlarms();
      setState(() {}); // 초기 로드 후 UI 갱신

      // 정기적인 알람 데이터 갱신 설정 (2초마다)
      Future.delayed(const Duration(seconds: 2), () async {
        if (!mounted) return;

        // 알람 데이터 갱신
        await alarmService.loadAlarms();

        // 캐시된 버스 정보 확인 및 업데이트
        if (alarmService.activeAlarms.isNotEmpty) {
          final firstAlarm = alarmService.activeAlarms.first;
          final cachedInfo = alarmService.getCachedBusInfo(
            firstAlarm.busNo,
            firstAlarm.routeId,
          );

          if (cachedInfo != null) {
            logMessage(
                '캐시된 버스 정보 발견: ${firstAlarm.busNo}, 남은 시간: ${cachedInfo.getRemainingMinutes()}분',
                level: LogLevel.debug);
          }
        }

        setState(() {}); // UI 갱신
      });

      // 버스 이동 애니메이션 타이머 설정
      _startProgressAnimation();
    });
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
    super.dispose();
  }

  // 알람 목록 아이템 위젯 생성 메서드
  Widget _buildAlarmListItem(AlarmData alarm, AlarmService alarmService) {
    // 캐시된 정보를 가져와서 최신화
    final cachedBusInfo = alarmService.getCachedBusInfo(
      alarm.busNo,
      alarm.routeId,
    );

    // 남은 시간 계산 - 캐시된 정보가 있으면 해당 값 사용, 없으면 알람 모델의 값 사용
    int arrivalMinutes;
    if (cachedBusInfo != null) {
      arrivalMinutes = cachedBusInfo.getRemainingMinutes();
      logMessage(
          '패널 표시 시간 계산: 버스=${alarm.busNo}, 마지막 갱신 시간=${cachedBusInfo.lastUpdated.toString()}, 남은 시간=$arrivalMinutes분',
          level: LogLevel.debug);
    } else {
      arrivalMinutes = alarm.getCurrentArrivalMinutes();
      logMessage(
          '패널 표시 시간 계산: 버스=${alarm.busNo}, 캐시 없음, 알람 시간=$arrivalMinutes분',
          level: LogLevel.debug);
    }

    final arrivalText = arrivalMinutes <= 1 ? '곧 도착' : '$arrivalMinutes분 후 도착';

    // 버스 현재 위치 정보 (캐시에서 최신 정보 가져오기)
    String? currentStation =
        cachedBusInfo?.currentStation ?? alarm.currentStation;
    String locationText = '';
    if (currentStation != null && currentStation.isNotEmpty) {
      locationText = ' ($currentStation)';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            Icons.alarm,
            color: arrivalMinutes <= 3 ? Colors.red : Colors.orange,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${alarm.busNo}번 버스 - ${alarm.stationName}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '$arrivalText$locationText',
                  style: TextStyle(
                    fontSize: 14,
                    color: arrivalMinutes <= 3 ? Colors.red : Colors.black87,
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
    bool? confirmDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('알람 취소'),
        content: Text('${alarm.busNo}번 버스 알람을 취소하시겠습니까?'),
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
      // 알람 즉시 취소
      final success = await alarmService.cancelAlarmByRoute(
        alarm.busNo,
        alarm.stationName,
        alarm.routeId,
      );

      if (success) {
        // 알람 취소 성공 로그
        logMessage('${alarm.busNo}번 버스 알람 취소 성공', level: LogLevel.info);

        // 스낵바 표시
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${alarm.busNo}번 버스 알람이 취소되었습니다')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AlarmService>(
      builder: (context, alarmService, child) {
        // 일반 알람은 모두 표시
        final activeAlarms = alarmService.activeAlarms;

        // 자동 알람은 예약된 시간 2분 전부터만 표시
        final autoAlarms = alarmService.autoAlarms.where((alarm) {
          final timeDiff =
              alarm.scheduledTime.difference(DateTime.now()).inMinutes;
          return timeDiff <= 2;
        }).toList();

        final allAlarms = [...activeAlarms, ...autoAlarms]
          ..sort((a, b) => a.scheduledTime.compareTo(b.scheduledTime));

        logMessage(
            'ActiveAlarmPanel 빌드: 일반=${activeAlarms.length}개, 자동=${autoAlarms.length}개',
            level: LogLevel.info);

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

        // 캐시된 정보를 가져와서 최신화
        final cachedBusInfo = alarmService.getCachedBusInfo(
          firstAlarm.busNo,
          firstAlarm.routeId,
        );

        // 남은 시간 계산
        int remainingMinutes;
        if (cachedBusInfo != null) {
          remainingMinutes = cachedBusInfo.getRemainingMinutes();
          logMessage(
              '버스 도착 정보 (캐시): ${firstAlarm.busNo}번, $remainingMinutes분 후',
              level: LogLevel.debug);
        } else {
          // 캐시된 정보가 없으면 알람 예정 시간과 현재 시간의 차이로 계산
          remainingMinutes =
              firstAlarm.scheduledTime.difference(DateTime.now()).inMinutes;
          logMessage(
              '버스 도착 정보 (예약): ${firstAlarm.busNo}번, $remainingMinutes분 후',
              level: LogLevel.debug);
        }

        final isArrivingSoon = remainingMinutes <= 2;
        final progress =
            (remainingMinutes > 30) ? 0.0 : (30 - remainingMinutes) / 30.0;
        final arrivalText = isArrivingSoon ? '곧 도착' : '$remainingMinutes분 후 도착';

        // 버스 현재 위치 정보
        String currentStation =
            cachedBusInfo?.currentStation ?? firstAlarm.currentStation ?? '';

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
