import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/bus_arrival.dart';
import '../models/bus_info.dart';
import '../models/favorite_bus.dart';
import '../services/alarm_service.dart';
import '../services/api_service.dart';
import '../services/notification_service.dart';
import '../services/settings_service.dart';
import '../utils/favorite_bus_store.dart';
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

  List<FavoriteBus> _favoriteBuses = [];
  bool _isLoadingFavorites = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeBusInfo();
    _startOptimizedPeriodicUpdate();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final loaded = await FavoriteBusStore.load();
    if (mounted) {
      setState(() {
        _favoriteBuses = loaded;
        _isLoadingFavorites = false;
      });
    }
  }

  bool _isFavorite() {
    if (_isLoadingFavorites) return false;
    final favorite = FavoriteBus(
      stationId: widget.stationId,
      stationName: widget.stationName,
      routeId: widget.busArrival.routeId,
      routeNo: widget.busArrival.routeNo,
    );
    return _favoriteBuses.any((item) => item.key == favorite.key);
  }

  Future<void> _toggleFavorite() async {
    HapticFeedback.lightImpact();
    final favorite = FavoriteBus(
      stationId: widget.stationId,
      stationName: widget.stationName,
      routeId: widget.busArrival.routeId,
      routeNo: widget.busArrival.routeNo,
    );
    final wasFavorite = _isFavorite();
    final updated = FavoriteBusStore.toggle(_favoriteBuses, favorite);
    await FavoriteBusStore.save(updated);

    if (!mounted) return;
    setState(() {
      _favoriteBuses = updated;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasFavorite
              ? '${widget.busArrival.routeNo}번 버스 즐겨찾기를 해제했습니다.'
              : '${widget.busArrival.routeNo}번 버스를 즐겨찾기에 추가했습니다.',
        ),
      ),
    );
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
    if (_currentBus.isOutOfService) return '운행 종료';
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

                      // 액션 버튼들 (알람, 즐겨찾기)
                      Column(
                        children: [
                          FilledButton.icon(
                            onPressed: _toggleAlarm,
                            icon: Icon(
                              hasAlarm
                                  ? Icons.notifications_off
                                  : Icons.notifications_active,
                              size: 18,
                            ),
                            label: Text(hasAlarm ? '알람 해제' : '승차 알람'),
                            style: FilledButton.styleFrom(
                              backgroundColor: hasAlarm
                                  ? Theme.of(context).colorScheme.errorContainer
                                  : Theme.of(context).colorScheme.primaryContainer,
                              foregroundColor: hasAlarm
                                  ? Theme.of(context).colorScheme.onErrorContainer
                                  : Theme.of(context).colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed: _toggleFavorite,
                            icon: Icon(
                              _isFavorite() ? Icons.star : Icons.star_border,
                              size: 18,
                            ),
                            label: Text(_isFavorite() ? '즐겨찾기 해제' : '즐겨찾기 추가'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
                              foregroundColor: Theme.of(context).colorScheme.onTertiaryContainer,
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
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    backgroundColor: Theme.of(context).colorScheme.surface,
    barrierColor: Theme.of(context).colorScheme.scrim.withAlpha(138),
    builder: (context) {
      return _BusDetailModalContent(
        busArrival: busArrival,
        stationId: stationId,
        stationName: stationName,
      );
    },
  );
}

/// 버스 상세 모달 내용 (StatefulWidget for favorite toggle)
class _BusDetailModalContent extends StatefulWidget {
  final BusArrival busArrival;
  final String stationId;
  final String stationName;

  const _BusDetailModalContent({
    required this.busArrival,
    required this.stationId,
    required this.stationName,
  });

  @override
  State<_BusDetailModalContent> createState() => _BusDetailModalContentState();
}

class _BusDetailModalContentState extends State<_BusDetailModalContent> {
  List<FavoriteBus> _favoriteBuses = [];

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final loaded = await FavoriteBusStore.load();
    if (mounted) {
      setState(() {
        _favoriteBuses = loaded;
      });
    }
  }

  bool _isFavorite() {
    final favorite = FavoriteBus(
      stationId: widget.stationId,
      stationName: widget.stationName,
      routeId: widget.busArrival.routeId,
      routeNo: widget.busArrival.routeNo,
    );
    return _favoriteBuses.any((item) => item.key == favorite.key);
  }

  Future<void> _toggleFavorite() async {
    HapticFeedback.lightImpact();
    final favorite = FavoriteBus(
      stationId: widget.stationId,
      stationName: widget.stationName,
      routeId: widget.busArrival.routeId,
      routeNo: widget.busArrival.routeNo,
    );
    final wasFavorite = _isFavorite();
    final updated = FavoriteBusStore.toggle(_favoriteBuses, favorite);
    await FavoriteBusStore.save(updated);

    if (!mounted) return;
    setState(() {
      _favoriteBuses = updated;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          wasFavorite
              ? '${widget.busArrival.routeNo}번 버스 즐겨찾기를 해제했습니다.'
              : '${widget.busArrival.routeNo}번 버스를 즐겨찾기에 추가했습니다.',
        ),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 80),
      ),
    );
  }

  Future<void> _handleAlarmToggle(
      BuildContext context, bool hasAlarm, BusInfo? bus) async {
    HapticFeedback.lightImpact();
    if (!mounted) return;

    final alarmService = Provider.of<AlarmService>(context, listen: false);
    final remainingMinutes = bus?.getRemainingMinutes() ?? -1;

    if (hasAlarm) {
      await alarmService.cancelAlarmByRoute(
        widget.busArrival.routeNo,
        widget.stationName,
        widget.busArrival.routeId,
      );
      await NotificationService().cancelOngoingTracking();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('승차 알람이 해제되었습니다'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      if (remainingMinutes <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('버스가 이미 도착했거나 곧 도착합니다'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }
      await alarmService.setOneTimeAlarm(
        widget.busArrival.routeNo,
        widget.stationName,
        remainingMinutes,
        routeId: widget.busArrival.routeId,
        stationId: widget.stationId,
        useTTS: true,
        isImmediateAlarm: true,
        currentStation: bus?.currentStation ?? '',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('승차 알람이 설정되었습니다'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final busList = widget.busArrival.busInfoList;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            // 드래그 핸들
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              height: 4,
              width: 36,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withAlpha(102),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 헤더 영역: 버스뱃지 + 정류장명 + 즐겨찾기 + 닫기
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
              child: Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.primary,
                          colorScheme.primary.withAlpha(204),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: colorScheme.primary.withAlpha(77),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.directions_bus_rounded,
                            size: 20, color: Colors.white),
                        const SizedBox(width: 6),
                        Text(
                          widget.busArrival.routeNo,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.stationName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.busArrival.direction.isNotEmpty)
                          Text(
                            '\u2192 ${widget.busArrival.direction}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                  // 즐겨찾기 아이콘 버튼
                  IconButton(
                    onPressed: _toggleFavorite,
                    icon: Icon(
                      _isFavorite()
                          ? Icons.star_rounded
                          : Icons.star_outline_rounded,
                      color: _isFavorite()
                          ? Colors.amber
                          : colorScheme.onSurfaceVariant,
                    ),
                    tooltip: _isFavorite() ? '즐겨찾기 해제' : '즐겨찾기 추가',
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded,
                        color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),

            // 메인 콘텐츠
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                children: [
                  if (busList.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 20),
                      child: Text('도착 정보가 없습니다.'),
                    )
                  else ...[
                    // 첫 번째 버스 섹션
                    _buildSectionLabel(
                      theme,
                      colorScheme,
                      icon: Icons.looks_one_rounded,
                      label: '첫 번째 버스',
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 8),
                    _buildBusCard(context, busList[0], isMainBus: true),

                    // 다음 버스 섹션
                    if (busList.length > 1) ...[
                      const SizedBox(height: 20),
                      _buildSectionLabel(
                        theme,
                        colorScheme,
                        icon: Icons.looks_two_rounded,
                        label: '다음 버스',
                        color: colorScheme.secondary,
                      ),
                      const SizedBox(height: 8),
                      ...busList
                          .skip(1)
                          .map((nextBus) =>
                              _buildBusCard(context, nextBus, isMainBus: false)),
                    ],
                  ],
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionLabel(
    ThemeData theme,
    ColorScheme colorScheme, {
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildBusCard(BuildContext context, BusInfo bus,
      {required bool isMainBus}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final minutes = bus.getRemainingMinutes();
    final isArriving = minutes >= 0 && minutes <= 3;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isMainBus
            ? colorScheme.primaryContainer.withAlpha(102)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMainBus
              ? colorScheme.primary.withAlpha(102)
              : colorScheme.outlineVariant.withAlpha(77),
          width: isMainBus ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          // 왼쪽: 시간 표시
          Container(
            width: isMainBus ? 68 : 60,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: bus.isOutOfService
                  ? colorScheme.surfaceContainerHigh
                  : isArriving
                      ? colorScheme.errorContainer
                      : colorScheme.primaryContainer.withAlpha(128),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  bus.isOutOfService
                      ? '종료'
                      : (minutes == 0 ? '곧' : '$minutes'),
                  style: (isMainBus
                          ? theme.textTheme.headlineSmall
                          : theme.textTheme.titleMedium)
                      ?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: bus.isOutOfService
                        ? colorScheme.onSurfaceVariant
                        : isArriving
                            ? colorScheme.error
                            : colorScheme.primary,
                  ),
                ),
                if (!bus.isOutOfService)
                  Text(
                    minutes == 0 ? '도착' : '분',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: isArriving
                          ? colorScheme.error.withAlpha(179)
                          : colorScheme.primary.withAlpha(179),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          // 가운데: 위치 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 현재 정류장
                Row(
                  children: [
                    Icon(
                      Icons.location_on,
                      size: 16,
                      color: isMainBus
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        bus.currentStation,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 남은 정거장
                Text(
                  bus.remainingStops,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                // 저상버스 뱃지
                if (bus.isLowFloor) ...[
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
                        Icon(Icons.accessible,
                            size: 12,
                            color: colorScheme.onSecondaryContainer),
                        const SizedBox(width: 3),
                        Text(
                          '저상',
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
          const SizedBox(width: 8),
          // 오른쪽: 개별 알람 버튼
          Selector<AlarmService, bool>(
            selector: (context, alarmService) => alarmService.hasAlarm(
              widget.busArrival.routeNo,
              widget.stationName,
              widget.busArrival.routeId,
            ),
            builder: (context, hasAlarm, child) {
              return Material(
                color: hasAlarm
                    ? colorScheme.errorContainer
                    : colorScheme.primaryContainer.withAlpha(102),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => _handleAlarmToggle(context, hasAlarm, bus),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: hasAlarm
                            ? colorScheme.error.withAlpha(128)
                            : colorScheme.primary.withAlpha(77),
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      hasAlarm
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                      size: 22,
                      color: hasAlarm
                          ? colorScheme.onErrorContainer
                          : colorScheme.primary,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

