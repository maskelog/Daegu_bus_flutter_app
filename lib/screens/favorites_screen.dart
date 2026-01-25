import 'dart:async';

import 'package:flutter/material.dart';

import '../models/bus_arrival.dart';
import '../models/bus_stop.dart';
import '../models/favorite_bus.dart';
import '../services/alarm_service.dart';
import '../services/api_service.dart';
import '../utils/favorite_bus_store.dart';
import '../widgets/unified_bus_detail_widget.dart';
import 'search_screen.dart';
import 'package:provider/provider.dart';

class FavoritesScreen extends StatefulWidget {
  final List<FavoriteBus> favoriteBuses;
  final ValueChanged<List<FavoriteBus>> onFavoritesUpdated;

  const FavoritesScreen({
    super.key,
    required this.favoriteBuses,
    required this.onFavoritesUpdated,
  });

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<FavoriteBus> _favoriteBuses = [];
  final Map<String, List<BusArrival>> _stationArrivals = {};
  Timer? _refreshTimer;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _favoriteBuses = List<FavoriteBus>.from(widget.favoriteBuses);
    _loadFavorites();
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshArrivals(),
    );
  }

  @override
  void didUpdateWidget(covariant FavoritesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.favoriteBuses != widget.favoriteBuses) {
      setState(() {
        _favoriteBuses = List<FavoriteBus>.from(widget.favoriteBuses);
      });
      _refreshArrivals();
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final loaded = await FavoriteBusStore.load();
      if (!mounted) return;
      setState(() {
        _favoriteBuses = loaded;
      });
      widget.onFavoritesUpdated(loaded);
      await _refreshArrivals();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '즐겨찾기를 불러오는 중 오류가 발생했습니다: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _refreshArrivals() async {
    final stationIds = _favoriteBuses
        .map((bus) => bus.stationId)
        .where((id) => id.isNotEmpty)
        .toSet();

    for (final stationId in stationIds) {
      try {
        final arrivals = await ApiService.getStationInfo(stationId);
        if (!mounted) return;
        setState(() {
          _stationArrivals[stationId] = arrivals;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _stationArrivals[stationId] = <BusArrival>[];
        });
      }
    }
  }

  String _formatArrivalTime(BusArrival arrival) {
    final bus = arrival.firstBus;
    if (bus == null) return '?? ?? ??';
    if (bus.isOutOfService) return '?? ??';
    final minutes = bus.getRemainingMinutes();
    if (minutes < 0) return '?? ??';
    if (minutes == 0) return '? ??';
    return '${minutes}?';
  }

  Future<void> _toggleFavorite(FavoriteBus bus) async {
    final updated = FavoriteBusStore.toggle(_favoriteBuses, bus);
    await FavoriteBusStore.save(updated);
    if (!mounted) return;
    setState(() {
      _favoriteBuses = updated;
    });
    widget.onFavoritesUpdated(updated);
  }

  Future<void> _openAddFavoriteFlow() async {
    final selectedStop = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SearchScreen(),
      ),
    );
    if (!mounted) return;
    if (selectedStop is! BusStop) return;

    try {
      final arrivals = await ApiService.getStationInfo(
        selectedStop.stationId ?? selectedStop.id,
      );
      if (!mounted) return;
      _showArrivalPicker(selectedStop, arrivals);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('정류장 정보를 불러오지 못했습니다: $e')),
      );
    }
  }

  void _showArrivalPicker(BusStop stop, List<BusArrival> arrivals) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        if (arrivals.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              '선택할 버스가 없습니다.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stop.name,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                ...arrivals.map((arrival) {
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '${arrival.routeNo}?',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _formatArrivalTime(arrival),
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                    trailing: Icon(
                      Icons.star_border,
                      color: colorScheme.primary,
                    ),
                    onTap: () async {
                      final favorite = FavoriteBus(
                        stationId: stop.stationId ?? stop.id,
                        stationName: stop.name,
                        routeId: arrival.routeId,
                        routeNo: arrival.routeNo,
                      );
                      await _toggleFavorite(favorite);
                      if (!mounted) return;
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('${arrival.routeNo}번 버스를 추가했습니다.')),
                      );
                    },
                  );
                }).toList(),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: _loadFavorites,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '즐겨찾기',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: _openAddFavoriteFlow,
                  icon: const Icon(Icons.add),
                  label: const Text('?? ??'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: TextStyle(color: colorScheme.error),
              )
            else if (_favoriteBuses.isEmpty)
              Text(
                '즐겨찾기한 버스가 없습니다.',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              )
            else
              ..._favoriteBuses.map((favorite) {
                final arrivals =
                    _stationArrivals[favorite.stationId] ?? const <BusArrival>[];
                final arrival = _pickArrivalForFavorite(arrivals, favorite);
                final bus = arrival.firstBus;
                final timeText =
                    bus == null ? '?? ?? ??' : _formatArrivalTime(arrival);
                final currentStation = bus?.currentStation ?? '?? ?? ??';

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: InkWell(
                    onTap: () {
                      final stop = BusStop(
                        id: favorite.stationId,
                        stationId: favorite.stationId,
                        name: favorite.stationName,
                        isFavorite: false,
                      );
                      showUnifiedBusDetailModal(
                        context,
                        arrival,
                        stop.stationId ?? stop.id,
                        stop.name,
                      );
                    },
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 28,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              favorite.routeNo,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                favorite.stationName,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$timeText ? $currentStation',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.headset,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                          tooltip: '이어폰 알람',
                          onPressed: () async {
                            final bus = arrival.firstBus;
                            if (bus == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('도착 정보가 없습니다.')),
                              );
                              return;
                            }
                            final minutes = bus.getRemainingMinutes();
                            if (minutes < 0) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('운행 종료 상태입니다.')),
                              );
                              return;
                            }
                            final alarmService = Provider.of<AlarmService>(
                              context,
                              listen: false,
                            );
                            await alarmService.setOneTimeAlarm(
                              favorite.routeNo,
                              favorite.stationName,
                              minutes,
                              routeId: favorite.routeId,
                              stationId: favorite.stationId,
                              useTTS: true,
                              isImmediateAlarm: true,
                              earphoneOnlyOverride: true,
                              currentStation: bus.currentStation,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${favorite.routeNo}번 버스 이어폰 알람을 설정했습니다.',
                                ),
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.star,
                            color: colorScheme.primary,
                            size: 20,
                          ),
                          onPressed: () => _toggleFavorite(favorite),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  BusArrival _pickArrivalForFavorite(
      List<BusArrival> arrivals, FavoriteBus favorite) {
    if (arrivals.isEmpty) {
      return BusArrival(
        routeId: favorite.routeId,
        routeNo: favorite.routeNo,
        direction: '',
        busInfoList: const [],
      );
    }

    final byRouteId = arrivals.where((item) => item.routeId == favorite.routeId);
    final byRouteNo = arrivals.where((item) => item.routeNo == favorite.routeNo);
    final candidates = byRouteId.isNotEmpty ? byRouteId.toList() : byRouteNo.toList();
    if (candidates.isEmpty) {
      return BusArrival(
        routeId: favorite.routeId,
        routeNo: favorite.routeNo,
        direction: '',
        busInfoList: const [],
      );
    }

    BusArrival? best;
    int? bestMinutes;
    for (final candidate in candidates) {
      final bus = candidate.firstBus;
      if (bus == null || bus.isOutOfService) {
        continue;
      }
      final minutes = bus.getRemainingMinutes();
      if (minutes < 0) {
        continue;
      }
      if (bestMinutes == null || minutes < bestMinutes) {
        bestMinutes = minutes;
        best = candidate;
      }
    }

    return best ?? candidates.first;
  }
}
