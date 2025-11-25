import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:daegu_bus_app/models/bus_arrival.dart';
import 'package:daegu_bus_app/models/bus_info.dart';
import 'package:daegu_bus_app/services/alarm_service.dart';
import 'package:daegu_bus_app/main.dart' show logMessage, LogLevel;

/// 경량화된 버스 카드 위젯
/// 메모리 사용량과 성능을 최적화
class LightweightBusCard extends StatefulWidget {
  final BusArrival busArrival;
  final VoidCallback onTap;
  final String? stationName;
  final String stationId;

  const LightweightBusCard({
    super.key,
    required this.busArrival,
    required this.onTap,
    this.stationName,
    required this.stationId,
  });

  @override
  State<LightweightBusCard> createState() => _LightweightBusCardState();
}

class _LightweightBusCardState extends State<LightweightBusCard> {
  late BusInfo _currentBus;
  Timer? _refreshTimer;
  bool _isDisposed = false;

  // 메모리 절약을 위한 상수
  static const Duration _refreshInterval = Duration(minutes: 1);

  @override
  void initState() {
    super.initState();
    _initializeBusInfo();
    _startRefreshTimer();
  }

  @override
  void didUpdateWidget(LightweightBusCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busArrival != oldWidget.busArrival) {
      _initializeBusInfo();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// 버스 정보 초기화 (안전하게)
  void _initializeBusInfo() {
    if (widget.busArrival.busInfoList.isNotEmpty) {
      _currentBus = widget.busArrival.busInfoList.first;
    } else {
      // 기본 버스 정보 생성
      _currentBus = BusInfo(
        busNumber: widget.busArrival.routeNo,
        currentStation: '정보 없음',
        estimatedTime: '정보 없음',
        remainingStops: '0',
        isLowFloor: false,
        isOutOfService: true,
      );
    }
  }

  /// 경량화된 새로고침 타이머
  void _startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (!_isDisposed && mounted) {
        _refreshBusInfo();
      }
    });
  }

  /// 버스 정보 새로고침 (경량화)
  void _refreshBusInfo() {
    if (!mounted || _isDisposed) return;

    try {
      // 위젯 데이터만 사용하여 새로고침 (API 호출 최소화)
      if (widget.busArrival.busInfoList.isNotEmpty) {
        final newBusInfo = widget.busArrival.busInfoList.first;
        if (!newBusInfo.isOutOfService) {
          setState(() {
            _currentBus = newBusInfo;
          });
        }
      }
    } catch (e) {
      logMessage('경량화 버스 카드 새로고침 오류: $e', level: LogLevel.error);
    }
  }

  /// 버스 알람 토글 (간소화)
  Future<void> _toggleAlarm() async {
    try {
      final alarmService = Provider.of<AlarmService>(context, listen: false);
      final hasAlarm = alarmService.hasAlarm(
        widget.busArrival.routeNo,
        widget.stationName ?? '정류장 정보 없음',
        widget.busArrival.routeId,
      );

      if (hasAlarm) {
        // 알람 취소
        await alarmService.cancelAlarmByRoute(
          widget.busArrival.routeNo,
          widget.stationName ?? '정류장 정보 없음',
          widget.busArrival.routeId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('알람이 취소되었습니다')),
          );
        }
      } else {
        // 알람 설정
        final remainingTime = _currentBus.getRemainingMinutes();
        if (remainingTime > 0) {
          await alarmService.setOneTimeAlarm(
            widget.busArrival.routeNo,
            widget.stationName ?? '정보 없음',
            remainingTime,
            routeId: widget.busArrival.routeId,
            stationId: widget.stationId,
            useTTS: true,
            isImmediateAlarm: true,
            currentStation: _currentBus.currentStation,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('알람이 설정되었습니다')),
            );
          }
        }
      }
    } catch (e) {
      logMessage('알람 토글 오류: $e', level: LogLevel.error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('알람 설정 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 데이터 검증
    if (widget.busArrival.busInfoList.isEmpty ||
        _currentBus.estimatedTime == '정보 없음') {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        color: Colors.grey[50],
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.refresh, color: Colors.grey[600], size: 20),
              const SizedBox(width: 8),
              Text('버스 정보를 불러오는 중...',
                  style: TextStyle(color: Colors.grey[600])),
            ],
          ),
        ),
      );
    }

    final remainingTime = _currentBus.getRemainingMinutes();
    final isOutOfService =
        _currentBus.isOutOfService || _currentBus.estimatedTime == '운행종료';

    String arrivalTimeText;
    if (isOutOfService) {
      arrivalTimeText = '운행종료';
    } else if (remainingTime <= 0) {
      arrivalTimeText = '곧 도착';
    } else {
      arrivalTimeText = '$remainingTime분';
    }

    return Consumer<AlarmService>(
      builder: (context, alarmService, child) {
        final bool hasAlarm = alarmService.hasAlarm(
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 헤더
                  Row(
                    children: [
                      Icon(Icons.directions_bus,
                          color: Colors.blue[500], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${widget.busArrival.routeNo}번 - ${widget.stationName ?? "정류장"}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 메인 정보
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            arrivalTimeText,
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: isOutOfService
                                  ? Colors.grey
                                  : (remainingTime <= 3
                                      ? Colors.red
                                      : Colors.blue[600]),
                            ),
                          ),
                          if (!isOutOfService &&
                              _currentBus.currentStation.isNotEmpty)
                            Text(
                              _currentBus.currentStation,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                            ),
                        ],
                      ),

                      // 알람 버튼 (간소화)
                      ElevatedButton.icon(
                        onPressed: isOutOfService ? null : _toggleAlarm,
                        icon: Icon(
                          hasAlarm
                              ? Icons.notifications_active
                              : Icons.notifications_none,
                          color: Colors.white,
                          size: 18,
                        ),
                        label: Text(
                          hasAlarm ? '해제' : '알람',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isOutOfService
                              ? Colors.grey
                              : (hasAlarm
                                  ? Colors.orange[600]
                                  : Colors.blue[600]),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          minimumSize: const Size(80, 36),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
