import 'dart:async';

import 'package:daegu_bus_app/services/alarm_service.dart';
import 'package:daegu_bus_app/widgets/unified_bus_detail_widget.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:daegu_bus_app/main.dart' show logMessage, LogLevel;

import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';
import '../services/api_service.dart';
import '../widgets/station_item.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (widget.favoriteStops.isEmpty) {
      return Container(
        color: colorScheme.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.star_border,
                  size: 64, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                '즐겨찾는 정류장이 없습니다',
                style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                '정류장 검색 후 별표 아이콘을 눌러 추가하세요',
                style: TextStyle(
                    fontSize: 14, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: colorScheme.surface,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: widget.favoriteStops.length,
        itemBuilder: (context, index) {
          final station = widget.favoriteStops[index];
          final isSelected = _selectedStop?.id == station.id;
          final stationArrivals = _stationArrivals[station.id] ?? [];
          final isLoading = _isLoadingMap[station.id] ?? false;
          final error = _errorMap[station.id];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              StationItem(
                station: station,
                isSelected: isSelected,
                isTracking: _stationTrackingStatus[station.id] ?? false,
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
                onFavoriteToggle: () => widget.onFavoriteToggle(station),
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
                  padding: const EdgeInsets.only(left: 12, top: 8, bottom: 16),
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
                                      size: 32, color: colorScheme.error),
                                  const SizedBox(height: 8),
                                  Text(error,
                                      style:
                                          TextStyle(color: colorScheme.error)),
                                  TextButton(
                                    onPressed: () =>
                                        _loadStationArrivals(station),
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
                                  style:
                                      TextStyle(color: colorScheme.onSurface)),
                            ),
                          )
                        else
                          Expanded(
                            child: Scrollbar(
                              thickness: 6.0,
                              radius: const Radius.circular(10),
                              child: ListView.builder(
                                physics: const BouncingScrollPhysics(),
                                padding: EdgeInsets.zero,
                                itemCount: stationArrivals.length,
                                itemBuilder: (context, idx) {
                                  final busArrival = stationArrivals[idx];
                                  return UnifiedBusDetailWidget(
                                    busArrival: busArrival,
                                    stationName: station.name,
                                    stationId: station.id,
                                    isCompact: true,
                                    onTap: () => showUnifiedBusDetailModal(
                                      context,
                                      busArrival,
                                      station.stationId ?? station.id,
                                      station.name,
                                    ),
                                  );
                                },
                              ),
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
