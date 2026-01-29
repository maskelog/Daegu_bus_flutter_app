import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    if (bus == null) return '도착 정보 없음';
    if (bus.isOutOfService) return '운행 종료';
    final minutes = bus.getRemainingMinutes();
    if (minutes < 0) return '운행 종료';
    if (minutes == 0) return '곧 도착';
    return '$minutes분';
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
                      '${arrival.routeNo}번',
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
        child: CustomScrollView(
          slivers: [
            // Header section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                colorScheme.primary,
                                colorScheme.primary.withOpacity(0.7),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.primary.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.star_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '즐겨찾기',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: colorScheme.onSurface,
                                  letterSpacing: -0.5,
                                ),
                              ),
                              if (_favoriteBuses.isNotEmpty)
                                Text(
                                  '${_favoriteBuses.length}개의 버스',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        FilledButton.tonalIcon(
                          onPressed: _openAddFavoriteFlow,
                          icon: const Icon(Icons.add_rounded, size: 20),
                          label: const Text('추가'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            // Content
            if (_isLoading)
              const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: TextStyle(color: colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_favoriteBuses.isEmpty)
              SliverFillRemaining(
                child: _buildEmptyState(colorScheme),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final favorite = _favoriteBuses[index];
                      return _buildFavoriteCard(favorite, index);
                    },
                    childCount: _favoriteBuses.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.star_outline_rounded,
                  size: 40,
                  color: colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '즐겨찾기가 비어있어요',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '자주 이용하는 버스를 추가하면\n더 빠르게 확인할 수 있어요',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _openAddFavoriteFlow,
              icon: const Icon(Icons.add_rounded),
              label: const Text('버스 추가하기'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFavoriteCard(FavoriteBus favorite, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final arrivals = _stationArrivals[favorite.stationId] ?? const <BusArrival>[];
    final arrival = _pickArrivalForFavorite(arrivals, favorite);
    final bus = arrival.firstBus;
    final timeText = bus == null ? '도착 정보 없음' : _formatArrivalTime(arrival);
    final currentStation = bus?.currentStation ?? '위치 정보 없음';
    final minutes = bus?.getRemainingMinutes() ?? -1;
    final isArriving = minutes >= 0 && minutes <= 3;
    final isOutOfService = bus?.isOutOfService ?? true;

    return TweenAnimationBuilder<double>(
      key: ValueKey(favorite.key),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + (index * 50)),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 30 * (1 - value)),
          child: Opacity(opacity: value, child: child),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
          border: isArriving
              ? Border.all(
                  color: colorScheme.error.withOpacity(0.5),
                  width: 2,
                )
              : Border.all(
                  color: colorScheme.outlineVariant.withOpacity(0.2),
                  width: 1,
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () {
              HapticFeedback.lightImpact();
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
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Route badge
                      Container(
                        width: 60,
                        height: 36,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              colorScheme.primary,
                              colorScheme.primary.withOpacity(0.8),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.primary.withOpacity(0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            favorite.routeNo,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Station info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              favorite.stationName,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: colorScheme.onSurface,
                                letterSpacing: -0.3,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 14,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    currentStation,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Bottom section with time and actions
                  Row(
                    children: [
                      // Arrival time indicator
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isArriving
                                ? colorScheme.errorContainer
                                : isOutOfService
                                    ? colorScheme.surfaceContainerHigh
                                    : colorScheme.primaryContainer.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isOutOfService
                                    ? Icons.nightlight_round
                                    : Icons.schedule_rounded,
                                size: 16,
                                color: isArriving
                                    ? colorScheme.onErrorContainer
                                    : isOutOfService
                                        ? colorScheme.onSurfaceVariant
                                        : colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                timeText,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isArriving
                                      ? colorScheme.onErrorContainer
                                      : isOutOfService
                                          ? colorScheme.onSurfaceVariant
                                          : colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Earphone alarm button
                      _buildCardActionButton(
                        icon: Icons.headphones_rounded,
                        color: colorScheme.tertiary,
                        onPressed: () => _handleEarphoneAlarm(favorite, arrival),
                      ),
                      const SizedBox(width: 8),
                      // Remove favorite button
                      _buildCardActionButton(
                        icon: Icons.star_rounded,
                        color: colorScheme.primary,
                        onPressed: () => _toggleFavorite(favorite),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }

  Future<void> _handleEarphoneAlarm(FavoriteBus favorite, BusArrival arrival) async {
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
    final alarmService = Provider.of<AlarmService>(context, listen: false);
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
        content: Text('${favorite.routeNo}번 버스 이어폰 알람을 설정했습니다.'),
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
