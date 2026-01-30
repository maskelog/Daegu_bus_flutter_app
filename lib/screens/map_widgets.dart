import 'package:flutter/material.dart';

import '../models/bus_arrival.dart';
import '../models/bus_stop.dart';
import '../services/bus_api_service.dart';

class MapLoadingView extends StatelessWidget {
  const MapLoadingView({super.key, required this.hasPosition});

  final bool hasPosition;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            '지도를 로딩하고 있습니다...',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (hasPosition) ...[
            const SizedBox(height: 8),
            Text(
              '주변 정류장을 검색하고 있습니다...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MapErrorView extends StatelessWidget {
  const MapErrorView({super.key, required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }
}

class MapFloatingButtons extends StatelessWidget {
  const MapFloatingButtons({
    super.key,
    required this.onSearchNearby,
    required this.onMoveToCurrent,
  });

  final VoidCallback onSearchNearby;
  final VoidCallback onMoveToCurrent;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            onPressed: onSearchNearby,
            tooltip: '주변 정류장 검색',
            child: const Icon(Icons.search),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            onPressed: onMoveToCurrent,
            tooltip: '현재 위치로 이동',
            child: const Icon(Icons.my_location),
          ),
        ],
      ),
    );
  }
}

class BusInfoList extends StatefulWidget {
  const BusInfoList({
    super.key,
    required this.station,
    required this.scrollController,
  });

  final BusStop station;
  final ScrollController scrollController;

  @override
  State<BusInfoList> createState() => _BusInfoListState();
}

class _BusInfoListState extends State<BusInfoList> {
  List<BusArrival> _busArrivals = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBusArrivals();
  }

  Future<void> _loadBusArrivals() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final busStationId = widget.station.stationId ?? widget.station.id;
      final busApiService = BusApiService();
      final arrivals = await busApiService.getStationInfo(busStationId);

      if (mounted) {
        setState(() {
          _busArrivals = arrivals;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '버스 도착 정보를 불러오지 못했습니다: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _errorMessage!,
              style: TextStyle(color: colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadBusArrivals,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }

    if (_busArrivals.isEmpty) {
      return const Center(
        child: Text('도착 예정 버스가 없습니다.'),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadBusArrivals,
      child: ListView.builder(
        controller: widget.scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _busArrivals.length,
        itemBuilder: (context, index) {
          final arrival = _busArrivals[index];
          final bus = arrival.firstBus;
          if (bus == null) return const SizedBox.shrink();

          final minutes = bus.getRemainingMinutes();
          final isLowFloor = bus.isLowFloor;
          final isOutOfService = bus.isOutOfService;

          String timeText;
          if (isOutOfService) {
            timeText = '운행 종료';
          } else if (minutes <= 0) {
            timeText = '곧 도착';
          } else {
            timeText = '$minutes분 후';
          }

          final stopsText = !isOutOfService ? '${bus.remainingStops}개 전' : '';
          final isSoon = !isOutOfService && minutes <= 1;
          final isWarning = !isOutOfService && minutes > 1 && minutes <= 3;

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: CircleAvatar(
                radius: 20,
                backgroundColor: _getBusColor(arrival, isLowFloor),
                child: Text(
                  arrival.routeNo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              title: Text(
                timeText,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isSoon
                      ? colorScheme.error
                      : isWarning
                          ? Colors.orange
                          : colorScheme.onSurface,
                ),
              ),
              subtitle: Text(stopsText),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLowFloor)
                    Icon(
                      Icons.accessible,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                  if (arrival.secondBus != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      '다음: ${arrival.getSecondArrivalTimeText()}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getBusColor(BusArrival arrival, bool isLowFloor) {
    final routeNo = arrival.routeNo;

    if (routeNo.startsWith('9')) {
      return const Color(0xFFF44336);
    } else if (routeNo.length == 3 && int.tryParse(routeNo) != null) {
      return const Color(0xFF795548);
    } else if (routeNo.startsWith('7') || routeNo.startsWith('8')) {
      return const Color(0xFF4CAF50);
    } else {
      return const Color(0xFF2196F3);
    }
  }
}
