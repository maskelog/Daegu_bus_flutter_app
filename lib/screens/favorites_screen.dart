import 'dart:async';

import 'package:daegu_bus_app/services/alarm_service.dart';
import 'package:daegu_bus_app/widgets/unified_bus_detail_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:daegu_bus_app/main.dart' show logMessage, LogLevel;

import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';
import '../models/bus_route.dart';
import '../services/api_service.dart';
import '../widgets/station_item.dart';
import 'settings_screen.dart';

class FavoritesScreen extends StatefulWidget {
  final List<BusStop> favoriteStops;
  final Function(BusStop) onStopSelected;
  final Function(BusStop) onFavoriteToggle;

  const FavoritesScreen({
    super.key,
    required this.favoriteStops,
    required this.onStopSelected,
    required this.onFavoriteToggle,
  });

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final Map<String, List<BusArrival>> _stationArrivals = {};
  final Map<String, bool> _isLoadingMap = {};
  final Map<String, String?> _errorMap = {};
  BusStop? _selectedStop;
  Timer? _refreshTimer;
  final Map<String, bool> _stationTrackingStatus = {};
  final Map<String, BusRouteType> _routeTypeCache = {};

  static const _stationTrackingChannel =
      MethodChannel('com.example.daegu_bus_app/station_tracking');

  @override
  void initState() {
    super.initState();
    if (widget.favoriteStops.isNotEmpty) {
      _loadAllFavoriteArrivals();
    }
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted) {
        if (_selectedStop != null) {
          _loadStationArrivals(_selectedStop!);
        } else if (widget.favoriteStops.isNotEmpty) {
          _loadAllFavoriteArrivals();
        }
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    // 화면 종료 시 모든 추적 중지 (선택적) <-- 이 라인을 제거합니다.
    // _stopAllStationTracking();
    super.dispose();
  }

  /// 즐겨찾는 모든 정류장의 도착 정보 불러오기
  Future<void> _loadAllFavoriteArrivals() async {
    for (final station in widget.favoriteStops) {
      await _loadStationArrivals(station);
    }
  }

  Future<void> _loadStationArrivals(BusStop station) async {
    setState(() {
      _isLoadingMap[station.id] = true;
      _errorMap[station.id] = null;
    });

    try {
      final arrivals = await ApiService.getStationInfo(station.id);
      if (!mounted) return;

      // 루트 타입 캐시 업데이트
      final routeIds = arrivals.map((a) => a.routeId).toSet();
      final missingRouteIds = routeIds.where((id) => !_routeTypeCache.containsKey(id)).toList();

      if (missingRouteIds.isNotEmpty) {
        final results = await Future.wait(
          missingRouteIds.map((id) async {
            try {
              final route = await ApiService.getBusRouteDetails(id);
              return route != null ? MapEntry(id, route.getRouteType()) : null;
            } catch (e) {
              return null;
            }
          }),
        );
        final newTypes = <String, BusRouteType>{};
        for (final entry in results) {
          if (entry != null) newTypes[entry.key] = entry.value;
        }
        _routeTypeCache.addAll(newTypes);
      }

      if (mounted) {
        setState(() {
          _stationArrivals[station.id] = arrivals;
          _isLoadingMap[station.id] = false;
        });
      }

      _updateAlarmServiceCache(arrivals, station.name);
    } catch (e) {
      logMessage('Error loading arrivals for station ${station.id}: $e',
          level: LogLevel.error);
      if (!mounted) return;

      if (mounted) {
        setState(() {
          _errorMap[station.id] = '도착 정보를 불러오지 못했습니다';
          _isLoadingMap[station.id] = false;
        });
      }
    }
  }

  void _updateAlarmServiceCache(
      List<BusArrival> busArrivals, String stationName) {
    if (busArrivals.isEmpty || !mounted) return;

    final alarmService = Provider.of<AlarmService>(context, listen: false);
    final Set<String> updatedBuses = {};

    for (var busArrival in busArrivals) {
      if (busArrival.busInfoList.isNotEmpty) {
        final firstBus = busArrival.busInfoList.first;
        final remainingTime = firstBus.getRemainingMinutes();
        final busKey = "${busArrival.routeNo}:${busArrival.routeId}";
        if (updatedBuses.contains(busKey)) continue;
        updatedBuses.add(busKey);

        alarmService.updateBusInfoCache(
          busArrival.routeNo,
          busArrival.routeId,
          firstBus,
          remainingTime,
        );
        logMessage(
            '즐겨찾기 화면에서 캐시 업데이트: ${busArrival.routeNo}, 남은 시간: $remainingTime분',
            level: LogLevel.debug);
      }
    }
  }

  Color _getBusColor(BusArrival arrival, bool isLowFloor) {
    final routeType = _routeTypeCache[arrival.routeId];

    // 색각이상 사용자를 위해 더 구별되는 색상 사용
    if (routeType == BusRouteType.express || arrival.routeNo.contains('급행')) {
      return const Color(0xFFE53935); // 강한 빨간색 (accessibleRed)
    }
    if (isLowFloor) {
      return const Color(0xFF2196F3); // 강한 파란색 (accessibleBlue)
    }
    return const Color(0xFF757575); // 중성 회색 (accessibleGrey)
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      children: [
        // 메인 콘텐츠
        Expanded(
          child: Container(
            color: colorScheme.surface,
            child: widget.favoriteStops.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star_border,
                            size: 64, color: colorScheme.onSurfaceVariant),
                        const SizedBox(height: 16),
                        Text(
                          '즐겨찾는 정류장이 없습니다',
                          style: TextStyle(
                              fontSize: 16, color: colorScheme.onSurface),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '정류장 검색 후 별표 아이콘을 눌러 추가하세요',
                          style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: widget.favoriteStops.length,
                    itemBuilder: (context, index) {
                      final station = widget.favoriteStops[index];
                      final isSelected = _selectedStop?.id == station.id;
                      final stationArrivals =
                          _stationArrivals[station.id] ?? [];
                      final isLoading = _isLoadingMap[station.id] ?? false;
                      final error = _errorMap[station.id];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          StationItem(
                            station: station,
                            isSelected: isSelected,
                            isTracking:
                                _stationTrackingStatus[station.id] ?? false,
                            onTap: () {
                              setState(() {
                                if (_selectedStop?.id == station.id) {
                                  _selectedStop = null;
                                } else {
                                  _selectedStop = station;
                                  if (stationArrivals.isEmpty && !isLoading) {
                                    _loadStationArrivals(station);
                                  }
                                }
                              });
                              widget.onStopSelected(station);
                            },
                            onFavoriteToggle: () =>
                                widget.onFavoriteToggle(station),
                            onTrackingToggle: () {
                              final isTracking =
                                  _stationTrackingStatus[station.id] ?? false;
                              if (isTracking) {
                                _stopStationTracking(station);
                              } else {
                                _startStationTracking(station);
                              }
                            },
                          ),
                          if (isSelected)
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: 12, top: 8, bottom: 16),
                              child: SizedBox(
                                height: 300,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isLoading)
                                      const Center(
                                        child: Padding(
                                          padding: EdgeInsets.all(16.0),
                                          child: CircularProgressIndicator(),
                                        ),
                                      )
                                    else if (error != null)
                                      Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Column(
                                            children: [
                                              Icon(Icons.error_outline,
                                                  size: 32,
                                                  color: colorScheme.error),
                                              const SizedBox(height: 8),
                                              Text(error,
                                                  style: TextStyle(
                                                      color:
                                                          colorScheme.error)),
                                              TextButton(
                                                onPressed: () =>
                                                    _loadStationArrivals(
                                                        station),
                                                child: const Text('다시 시도'),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    else if (stationArrivals.isEmpty)
                                      Center(
                                        child: Padding(
                                          padding: const EdgeInsets.all(16.0),
                                          child: Text('도착 예정 버스가 없습니다',
                                              style: TextStyle(
                                                  color:
                                                      colorScheme.onSurface)),
                                        ),
                                      )
                                    else
                                      Expanded(
                                        child: Column(
                                          children: stationArrivals.map((arrival) {
                                            final bus = arrival.firstBus;
                                            if (bus == null) return const SizedBox.shrink();

                                            final minutes = bus.getRemainingMinutes();
                                            final isLowFloor = bus.isLowFloor;
                                            final isOutOfService = bus.isOutOfService;
                                            String timeText;
                                            Color timeColor;
                                            
                                            if (isOutOfService) {
                                              timeText = '운행종료';
                                              timeColor = colorScheme.onSurfaceVariant;
                                            } else if (minutes <= 0) {
                                              timeText = '곧 도착';
                                              timeColor = colorScheme.error;
                                            } else if (minutes <= 3) {
                                              timeText = '$minutes분';
                                              timeColor = colorScheme.error;
                                            } else {
                                              timeText = '$minutes분';
                                              timeColor = colorScheme.onSurface;
                                            }
                                            
                                            final stopsText = !isOutOfService ? '${bus.remainingStops}정거장' : '';
                                            final routeNo = arrival.routeNo;
                                            final routeId = arrival.routeId;

                                            return Container(
                                              margin: const EdgeInsets.only(bottom: 4),
                                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                              decoration: BoxDecoration(
                                                color: colorScheme.surface,
                                                borderRadius: BorderRadius.circular(8),
                                                border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.3)),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    width: 50,
                                                    height: 28,
                                                    decoration: BoxDecoration(
                                                      color: _getBusColor(arrival, isLowFloor),
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Center(
                                                      child: Text(
                                                        routeNo,
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 13,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    flex: 2,
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Row(
                                                          children: [
                                                            Text(
                                                              timeText,
                                                              style: TextStyle(
                                                                color: timeColor,
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 16,
                                                              ),
                                                            ),
                                                            if (!isOutOfService) ...[
                                                              const SizedBox(width: 4),
                                                              Text(
                                                                '후',
                                                                style: TextStyle(
                                                                  color: colorScheme.onSurfaceVariant,
                                                                  fontSize: 14,
                                                                ),
                                                              ),
                                                            ],
                                                          ],
                                                        ),
                                                        if (stopsText.isNotEmpty)
                                                          Text(
                                                            stopsText,
                                                            style: TextStyle(
                                                              color: colorScheme.onSurfaceVariant,
                                                              fontSize: 12,
                                                            ),
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  if (arrival.secondBus != null) ...[
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      flex: 1,
                                                      child: Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(
                                                            '다음차',
                                                            style: TextStyle(
                                                              color: colorScheme.onSurfaceVariant,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                          Text(
                                                            arrival.getSecondArrivalTimeText(),
                                                            style: TextStyle(
                                                              color: colorScheme.onSurface,
                                                              fontSize: 12,
                                                              fontWeight: FontWeight.w500,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                  Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      if (isLowFloor)
                                                        Icon(
                                                          Icons.accessible,
                                                          size: 16,
                                                          color: colorScheme.primary,
                                                        ),
                                                      const SizedBox(width: 4),
                                                      Selector<AlarmService, bool>(
                                                        selector: (context, alarmService) =>
                                                            alarmService.hasAlarm(routeNo, station.name, routeId),
                                                        builder: (context, hasAlarm, child) {
                                                          return IconButton(
                                                            padding: EdgeInsets.zero,
                                                            constraints: const BoxConstraints(),
                                                            icon: Icon(
                                                              hasAlarm
                                                                  ? Icons.notifications_active
                                                                  : Icons.notifications_none_outlined,
                                                              color: hasAlarm
                                                                  ? colorScheme.primary
                                                                  : colorScheme.onSurfaceVariant,
                                                              size: 20,
                                                            ),
                                                            onPressed: () async {
                                                              final alarmService =
                                                                  Provider.of<AlarmService>(context, listen: false);
                                                              final scaffoldMessenger =
                                                                  ScaffoldMessenger.of(context);
                                                              try {
                                                                if (hasAlarm) {
                                                                  await alarmService.cancelAlarmByRoute(
                                                                      routeNo, station.name, routeId);
                                                                  if (mounted) {
                                                                    scaffoldMessenger.showSnackBar(
                                                                      SnackBar(
                                                                          content: Text('$routeNo번 버스 알람이 해제되었습니다')),
                                                                    );
                                                                  }
                                                                } else {
                                                                  if (minutes <= 0) {
                                                                    if (mounted) {
                                                                      scaffoldMessenger.showSnackBar(
                                                                        const SnackBar(
                                                                            content: Text('버스가 이미 도착했거나 곧 도착합니다')),
                                                                      );
                                                                    }
                                                                    return;
                                                                  }
                                                                  await alarmService.setOneTimeAlarm(
                                                                    routeNo,
                                                                    station.name,
                                                                    minutes,
                                                                    routeId: routeId,
                                                                    useTTS: true,
                                                                    isImmediateAlarm: true,
                                                                    currentStation: bus.currentStation,
                                                                  );
                                                                  if (mounted) {
                                                                    scaffoldMessenger.showSnackBar(
                                                                      SnackBar(
                                                                          content: Text('$routeNo번 버스 알람이 설정되었습니다')),
                                                                    );
                                                                  }
                                                                }
                                                              } catch (e) {
                                                                if (mounted) {
                                                                  scaffoldMessenger.showSnackBar(
                                                                    SnackBar(
                                                                        content: Text('알람 처리 중 오류가 발생했습니다: $e')),
                                                                  );
                                                                }
                                                              }
                                                            },
                                                          );
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          if (index < widget.favoriteStops.length - 1)
                            const Divider(height: 24),
                        ],
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Future<void> _startStationTracking(BusStop station) async {
    try {
      final result =
          await _stationTrackingChannel.invokeMethod('startStationTracking', {
        'stationId': station.id,
        'stationName': station.name,
      });
      if (result == true && mounted) {
        setState(() {
          _stationTrackingStatus[station.id] = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${station.name} 정류장 전체 도착 정보 추적을 시작합니다.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on PlatformException catch (e) {
      logMessage("Failed to start station tracking: '${e.message}'.",
          level: LogLevel.error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('정류장 추적 시작 실패: ${e.message}'),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        );
      }
    }
  }

  Future<void> _stopStationTracking(BusStop station) async {
    try {
      final result =
          await _stationTrackingChannel.invokeMethod('stopStationTracking');
      if (result == true && mounted) {
        setState(() {
          _stationTrackingStatus[station.id] = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${station.name} 정류장 전체 도착 정보 추적을 중지합니다.'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } on PlatformException catch (e) {
      logMessage("Failed to stop station tracking: '${e.message}'.",
          level: LogLevel.error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('정류장 추적 중지 실패: ${e.message}'),
            backgroundColor: Theme.of(context).colorScheme.errorContainer,
          ),
        );
      }
    }
  }
}
