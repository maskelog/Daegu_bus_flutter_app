import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/bus_arrival.dart';
import '../models/bus_info.dart';
import '../services/alarm_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../utils/simple_tts_helper.dart';

/// 통합된 버스 상세정보 위젯 (최적화 버전)
class UnifiedBusDetailWidget extends StatefulWidget {
  final BusArrival busArrival;
  final String stationId;
  final String stationName;
  final VoidCallback? onTap;
  final bool isCompact; // true: 컴팩트 뷰, false: 풀 뷰

  const UnifiedBusDetailWidget({
    super.key,
    required this.busArrival,
    required this.stationId,
    required this.stationName,
    this.onTap,
    this.isCompact = true,
  });

  @override
  State<UnifiedBusDetailWidget> createState() => _UnifiedBusDetailWidgetState();
}

class _UnifiedBusDetailWidgetState extends State<UnifiedBusDetailWidget>
    with WidgetsBindingObserver {
  Timer? _updateTimer;
  bool _isUpdating = false;
  late BusInfo _currentBus;
  late int _remainingTime;
  bool _isVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeBusInfo();
    _startOptimizedPeriodicUpdate();
  }

  @override
  void didUpdateWidget(UnifiedBusDetailWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.busArrival != oldWidget.busArrival) {
      _initializeBusInfo();
      // 부모 위젯에서 데이터가 갱신되었을 때 알림도 동기화
      _updateNotification();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isVisible = state == AppLifecycleState.resumed;
    if (!_isVisible) {
      _updateTimer?.cancel(); // 백그라운드에서 Timer 정지
    } else {
      _startOptimizedPeriodicUpdate(); // 포그라운드 복귀 시 Timer 재시작
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _updateTimer?.cancel();
    super.dispose();
  }

  void _initializeBusInfo() {
    if (widget.busArrival.busInfoList.isNotEmpty) {
      _currentBus = widget.busArrival.busInfoList.first;
      _remainingTime = _currentBus.getRemainingMinutes();
    }
  }

  void _startOptimizedPeriodicUpdate() {
    if (!_isVisible) return;

    _updateTimer?.cancel();
    // 30초 → 60초로 주기 증가 (배터리 절약)
    _updateTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      if (mounted && !_isUpdating && _isVisible) {
        _updateBusInfo();
      }
    });
  }

  Future<void> _updateBusInfo() async {
    if (_isUpdating || !mounted || !_isVisible) return;

    setState(() => _isUpdating = true);
    try {
      final updatedArrivals = await ApiService.getBusArrivalByRouteId(
        widget.stationId,
        widget.busArrival.routeId,
      );

      if (mounted &&
          updatedArrivals.isNotEmpty &&
          updatedArrivals[0].busInfoList.isNotEmpty) {
        final newBus = updatedArrivals[0].busInfoList.first;
        final newRemainingTime = newBus.getRemainingMinutes();

        // 실제 데이터 변화가 있을 때만 상태 업데이트
        if (_currentBus.currentStation != newBus.currentStation ||
            _remainingTime != newRemainingTime ||
            _currentBus.isOutOfService != newBus.isOutOfService) {
          setState(() {
            if (!newBus.isOutOfService) {
              _currentBus = newBus;
              _remainingTime = newRemainingTime;
            }
          });

          if (kDebugMode) {
            debugPrint(
                '🔄 버스 정보 업데이트: ${widget.busArrival.routeNo}번, $newRemainingTime분');
          }
        }
      }

      // 알람이 있을 때만 알림 업데이트
      if (!mounted) return;
      final alarmService = Provider.of<AlarmService>(context, listen: false);
      final hasAlarm = alarmService.hasAlarm(
        widget.busArrival.routeNo,
        widget.stationName,
        widget.busArrival.routeId,
      );

      if (hasAlarm) {
        NotificationService().updateBusTrackingNotification(
          busNo: widget.busArrival.routeNo,
          stationName: widget.stationName,
          remainingMinutes: _remainingTime,
          currentStation: _currentBus.currentStation,
          routeId: widget.busArrival.routeId,
          stationId: widget.stationId,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 버스 정보 업데이트 오류: $e');
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _updateNotification() async {
    if (!mounted) return;
    try {
      final alarmService = Provider.of<AlarmService>(context, listen: false);
      final hasAlarm = alarmService.hasAlarm(
        widget.busArrival.routeNo,
        widget.stationName,
        widget.busArrival.routeId,
      );

      if (hasAlarm) {
        if (kDebugMode) {
          debugPrint('🔄 알림 동기화: ${widget.busArrival.routeNo}번, $_remainingTime분');
        }
        await NotificationService().updateBusTrackingNotification(
          busNo: widget.busArrival.routeNo,
          stationName: widget.stationName,
          remainingMinutes: _remainingTime,
          currentStation: _currentBus.currentStation,
          routeId: widget.busArrival.routeId,
          stationId: widget.stationId,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 알림 동기화 오류: $e');
      }
    }
  }

  Future<void> _toggleAlarm() async {
    if (!mounted) return;

    try {
      final alarmService = Provider.of<AlarmService>(context, listen: false);
      final hasAlarm = alarmService.hasAlarm(
        widget.busArrival.routeNo,
        widget.stationName,
        widget.busArrival.routeId,
      );

      if (kDebugMode) {
        debugPrint(
            '🔔 알람 토글: hasAlarm=$hasAlarm, 버스=${widget.busArrival.routeNo}번');
      }

      if (hasAlarm) {
        await _cancelAlarm();
      } else {
        await _setAlarm();
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 알람 토글 중 오류: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('알람 처리 중 오류가 발생했습니다: $e')),
      );
    }
  }

  Future<void> _cancelAlarm() async {
    if (!mounted) return;

    final alarmService = Provider.of<AlarmService>(context, listen: false);
    final notificationService = NotificationService();

    if (kDebugMode) {
      debugPrint('🔔 알람 취소 시작: ${widget.busArrival.routeNo}번');
    }

    try {
      // 알림 취소
      await notificationService.cancelOngoingTracking();
      await notificationService.cancelAllNotifications();

      // 알람 제거
      final success = await alarmService.cancelAlarmByRoute(
        widget.busArrival.routeNo,
        widget.stationName,
        widget.busArrival.routeId,
      );

      if (kDebugMode) {
        debugPrint('✅ 알람 취소 ${success ? '성공' : '실패'}');
      }

      // TTS 알림 (간단하게)
      if (mounted) {
        try {
          await SimpleTTSHelper.speak(
            "${widget.busArrival.routeNo}번 버스 알람이 해제되었습니다.",
            earphoneOnly: true,
          );
        } catch (e) {
          if (kDebugMode) {
            debugPrint('⚠️ TTS 알림 오류: $e');
          }
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('승차 알람이 해제되었습니다')),
        );
        
        // UI 강제 업데이트
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 알람 취소 중 오류: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('알람 취소 중 오류가 발생했습니다: $e')),
      );
    }
  }

  Future<void> _setAlarm() async {
    if (!mounted) return;

    if (_remainingTime <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('버스가 이미 도착했거나 곧 도착합니다')),
      );
      return;
    }

    final alarmService = Provider.of<AlarmService>(context, listen: false);

    try {
      if (kDebugMode) {
        debugPrint('🔔 알람 설정 시작: ${widget.busArrival.routeNo}번');
      }

      // 동일한 정류장의 다른 버스 알람 취소
      for (var alarm in alarmService.activeAlarms) {
        if (alarm.stationName == widget.stationName &&
            alarm.busNo != widget.busArrival.routeNo) {
          await alarmService.cancelAlarmByRoute(
              alarm.busNo, alarm.stationName, alarm.routeId);
        }
      }

      // 알람 설정
      final success = await alarmService.setOneTimeAlarm(
        widget.busArrival.routeNo,
        widget.stationName,
        _remainingTime,
        routeId: widget.busArrival.routeId,
        stationId: widget.stationId,
        useTTS: true,
        isImmediateAlarm: true,
        currentStation: _currentBus.currentStation,
      );

      if (!mounted) return;

      if (success) {
        if (kDebugMode) {
          debugPrint('✅ 알람 설정 성공');
        }

        // TTS 알림 (간단하게)
        final settings = Provider.of<SettingsService>(context, listen: false);
        if (!mounted) return;
        if (settings.useTts) {
          try {
            await SimpleTTSHelper.speak(
              "${widget.busArrival.routeNo}번 버스 알람이 설정되었습니다.",
              earphoneOnly: true,
            );
          } catch (e) {
            if (kDebugMode) {
              debugPrint('⚠️ TTS 알림 오류: $e');
            }
          }
        }

        if (!mounted) return;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('승차 알람이 설정되었습니다')),
        );
        
        // UI 강제 업데이트
        if (mounted) {
          setState(() {});
        }
      } else {
        if (kDebugMode) {
          debugPrint('❌ 알람 설정 실패');
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('알람 설정에 실패했습니다')),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ 알람 설정 중 오류: $e');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('알람 설정 중 오류가 발생했습니다: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.busArrival.busInfoList.isEmpty) return _buildEmptyCard();
    return widget.isCompact ? _buildCompactCard() : _buildFullCard();
  }

  Widget _buildEmptyCard() {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      color:
          Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(76),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20),
            const SizedBox(width: 8),
            Text('도착 정보를 불러오는 중...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactCard() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest.withAlpha(76),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: colorScheme.outline.withAlpha(51),
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 첫 번째 행: 버스 번호와 알람 버튼
                Row(
                  children: [
                    // 버스 번호 배지
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.directions_bus,
                            size: 16,
                            color: colorScheme.onPrimary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.busArrival.routeNo,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: colorScheme.onPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // 알람 버튼 (Selector로 최적화)
                    Selector<AlarmService, bool>(
                      selector: (context, alarmService) =>
                          alarmService.hasAlarm(
                        widget.busArrival.routeNo,
                        widget.stationName,
                        widget.busArrival.routeId,
                      ),
                      builder: (context, hasAlarm, child) {
                        // 디버깅 로그 (개발 모드에서만)
                        if (kDebugMode) {
                          debugPrint(
                              '🔄 컴팩트 Selector 리빌드: ${widget.busArrival.routeNo}번, hasAlarm=$hasAlarm');
                        }

                        return Material(
                          color: hasAlarm
                              ? colorScheme.primaryContainer
                              : colorScheme.surface,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            onTap: _toggleAlarm,
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: hasAlarm
                                      ? colorScheme.primary
                                      : colorScheme.outline.withAlpha(128),
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Icon(
                                hasAlarm
                                    ? Icons.notifications_active
                                    : Icons.notifications_none,
                                size: 20,
                                color: hasAlarm
                                    ? colorScheme.primary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // 두 번째 행: 시간 정보
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _getTimeBackgroundColor(colorScheme),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getTimeIcon(),
                              size: 16,
                              color: _getTimeIconColor(colorScheme),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _getFormattedTime(),
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: _getTimeTextColor(colorScheme),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // 세 번째 행: 현재 위치
                if (_currentBus.currentStation.isNotEmpty &&
                    _currentBus.currentStation != "정보 없음")
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer.withAlpha(76),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: 14,
                          color: colorScheme.onTertiaryContainer,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            _currentBus.currentStation,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onTertiaryContainer,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),

                // 저상버스 표시
                if (_currentBus.isLowFloor) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.accessible,
                          size: 12,
                          color: colorScheme.onSecondaryContainer,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '저상버스',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 시간에 따른 배경색 결정
  Color _getTimeBackgroundColor(ColorScheme colorScheme) {
    if (_currentBus.isOutOfService) return colorScheme.errorContainer;

    switch (_remainingTime) {
      case 0:
        return colorScheme.primaryContainer;
      case 1:
      case 2:
        return colorScheme.tertiaryContainer;
      default:
        if (_remainingTime <= 5) return colorScheme.secondaryContainer;
        return colorScheme.surfaceContainerHighest;
    }
  }

  // 시간에 따른 텍스트 색상 결정
  Color _getTimeTextColor(ColorScheme colorScheme) {
    if (_currentBus.isOutOfService) return colorScheme.onErrorContainer;

    switch (_remainingTime) {
      case 0:
        return colorScheme.onPrimaryContainer;
      case 1:
      case 2:
        return colorScheme.onTertiaryContainer;
      default:
        if (_remainingTime <= 5) return colorScheme.onSecondaryContainer;
        return colorScheme.onSurfaceVariant;
    }
  }

  // 시간에 따른 아이콘 색상 결정
  Color _getTimeIconColor(ColorScheme colorScheme) {
    return _getTimeTextColor(colorScheme);
  }

  // 시간에 따른 아이콘 결정
  IconData _getTimeIcon() {
    if (_currentBus.isOutOfService) return Icons.block;

    switch (_remainingTime) {
      case 0:
        return Icons.flash_on;
      case 1:
      case 2:
        return Icons.warning_amber;
      default:
        return Icons.schedule;
    }
  }

  // 시간 포맷팅
  String _getFormattedTime() {
    if (_currentBus.isOutOfService) return '운행종료';
    if (_currentBus.estimatedTime == '곧 도착' || _remainingTime == 0) {
      return '곧 도착';
    }
    if (_remainingTime == 1) return '약 1분 후';
    if (_remainingTime > 1) return '약 $_remainingTime분 후';

    return _currentBus.estimatedTime.isNotEmpty
        ? _currentBus.estimatedTime
        : '정보 없음';
  }

  Widget _buildFullCard() {
    return Selector<AlarmService, bool>(
      selector: (context, alarmService) => alarmService.hasAlarm(
        widget.busArrival.routeNo,
        widget.stationName,
        widget.busArrival.routeId,
      ),
      builder: (context, hasAlarm, child) {
        // 디버깅 로그 (개발 모드에서만)
        if (kDebugMode) {
          debugPrint(
              '🔄 풀 Selector 리빌드: ${widget.busArrival.routeNo}번, hasAlarm=$hasAlarm');
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Theme.of(context).dividerColor, width: 0.5),
          ),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.directions_bus,
                          color: Theme.of(context).colorScheme.primary,
                          size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                            '${widget.busArrival.routeNo}번 - ${widget.stationName}',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                )),
                      ),
                      if (_isUpdating)
                        const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // 시간 정보와 알람 버튼
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _getFormattedTime(),
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(
                                    color: _currentBus.isOutOfService
                                        ? Theme.of(context).colorScheme.error
                                        : Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            if (_currentBus.currentStation.isNotEmpty &&
                                _currentBus.currentStation != "정보 없음")
                              Row(
                                children: [
                                  Icon(
                                    Icons.location_on_outlined,
                                    size: 16,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      _currentBus.currentStation,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            if (_currentBus.isLowFloor) ...[
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.accessible,
                                    size: 16,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '저상버스',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),

                      // 알람 설정/해제 버튼
                      Column(
                        children: [
                          ElevatedButton.icon(
                            onPressed: _toggleAlarm,
                            icon: Icon(
                              hasAlarm
                                  ? Icons.notifications_off
                                  : Icons.notifications_active,
                              size: 20,
                            ),
                            label: Text(hasAlarm ? '알람 해제' : '승차 알람'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: hasAlarm
                                  ? Theme.of(context).colorScheme.errorContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .primaryContainer,
                              foregroundColor: hasAlarm
                                  ? Theme.of(context)
                                      .colorScheme
                                      .onErrorContainer
                                  : Theme.of(context)
                                      .colorScheme
                                      .onPrimaryContainer,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 8),
                            ),
                          ),
                        ],
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

/// 버스 상세정보 모달을 표시하는 헬퍼 함수
void showUnifiedBusDetailModal(
  BuildContext context,
  BusArrival busArrival,
  String stationId,
  String stationName,
) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    backgroundColor: Theme.of(context).colorScheme.surface,
    barrierColor: Theme.of(context).colorScheme.scrim.withAlpha(138),
    builder: (context) {
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // 드래그 핸들
                Center(
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    height: 5,
                    width: 40,
                    decoration: BoxDecoration(
                      color:
                          Theme.of(context).colorScheme.onSurface.withAlpha(76),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                ),
                // 헤더
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${busArrival.routeNo}번 버스',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  )),
                          Text('$stationName → ${busArrival.direction}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close,
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.zero,
                    children: [
                      UnifiedBusDetailWidget(
                        busArrival: BusArrival(
                          routeNo: busArrival.routeNo,
                          routeId: busArrival.routeId,
                          busInfoList: busArrival.busInfoList.isNotEmpty
                              ? [busArrival.busInfoList.first]
                              : [],
                          direction: busArrival.direction,
                        ),
                        stationId: stationId,
                        stationName: stationName,
                        isCompact: false,
                      ),
                      if (busArrival.busInfoList.length > 1) ...[
                        const SizedBox(height: 24),
                        Text('다음 버스 정보',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                )),
                        const SizedBox(height: 16),
                        ...busArrival.busInfoList.skip(1).map((bus) {
                          final remainingMinutes = bus.getRemainingMinutes();
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 1,
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                  color: Theme.of(context).dividerColor),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(busArrival.routeNo,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                        color: bus
                                                                .isOutOfService
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant
                                                            : Theme.of(context)
                                                                .colorScheme
                                                                .primary,
                                                        fontWeight:
                                                            FontWeight.bold)),
                                            if (bus.isLowFloor)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                    left: 8),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .tertiaryContainer,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text('저상',
                                                    style: Theme.of(context)
                                                        .textTheme
                                                        .labelSmall
                                                        ?.copyWith(
                                                            color: Theme.of(
                                                                    context)
                                                                .colorScheme
                                                                .onTertiaryContainer,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w500)),
                                              ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(bus.currentStation,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant)),
                                        Text(bus.remainingStops,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (!bus.isOutOfService)
                                        Text('도착예정',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant)),
                                      Text(
                                          bus.isOutOfService
                                              ? '운행종료'
                                              : '$remainingMinutes분',
                                          style: Theme.of(
                                                  context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                  color:
                                                      bus
                                                              .isOutOfService
                                                          ? Theme.of(context)
                                                              .colorScheme
                                                              .onSurfaceVariant
                                                          : (remainingMinutes <=
                                                                  3
                                                              ? Theme.of(
                                                                      context)
                                                                  .colorScheme
                                                                  .error
                                                              : Theme.of(
                                                                      context)
                                                                  .colorScheme
                                                                  .primary),
                                                  fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 100), // 하단 여백
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
