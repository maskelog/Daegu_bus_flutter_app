import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/bus_arrival.dart';
import '../models/bus_stop.dart';
import '../models/favorite_bus.dart';
import '../services/alarm_service.dart';
import '../widgets/unified_bus_detail_widget.dart';

typedef BusColorResolver = Color Function(
  BuildContext context,
  BusArrival arrival,
  bool isLowFloor,
);

typedef FavoriteBusPredicate = bool Function(FavoriteBus bus);

typedef FavoriteToggleHandler = Future<void> Function(
  BusStop stop,
  BusArrival arrival,
);

typedef AlarmTapHandler = Future<void> Function(
  BusArrival arrival,
  String stationId,
  String stationName,
  bool hasAlarm,
);

typedef ArrivalTimeFormatter = String Function(BusArrival arrival);

class HomeSectionHeader extends StatelessWidget {
  const HomeSectionHeader({
    super.key,
    required this.title,
    required this.icon,
    required this.iconColor,
  });

  final String title;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class HomeNearbyStopsRow extends StatelessWidget {
  const HomeNearbyStopsRow({
    super.key,
    required this.nearbyStops,
    required this.maxItems,
    required this.selectedStop,
    required this.stationArrivals,
    required this.onStopSelected,
    required this.formatArrivalTime,
  });

  final List<BusStop> nearbyStops;
  final int maxItems;
  final BusStop? selectedStop;
  final Map<String, List<BusArrival>> stationArrivals;
  final ValueChanged<BusStop> onStopSelected;
  final ArrivalTimeFormatter formatArrivalTime;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleStops = nearbyStops.take(maxItems).toList();

    if (visibleStops.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.3),
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.location_searching_rounded,
                size: 20,
                color: colorScheme.onSurfaceVariant.withOpacity(0.6),
              ),
              const SizedBox(width: 10),
              Text(
                '주변 정류장을 찾는 중...',
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 72,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: visibleStops.length,
        itemBuilder: (context, index) {
          final stop = visibleStops[index];
          final isSelected = selectedStop?.id == stop.id;
          final arrivals = stationArrivals[stop.id] ?? [];
          final topBus = arrivals.isNotEmpty ? arrivals.first : null;

          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onStopSelected(stop),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primaryContainer
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? colorScheme.primary.withOpacity(0.5)
                          : colorScheme.outlineVariant.withOpacity(0.3),
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: colorScheme.primary.withOpacity(0.15),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        stop.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      if (topBus != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? colorScheme.primary.withOpacity(0.2)
                                    : colorScheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                topBus.routeNo,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              formatArrivalTime(topBus),
                              style: TextStyle(
                                fontSize: 11,
                                color: isSelected
                                    ? colorScheme.onPrimaryContainer
                                        .withOpacity(0.8)
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        )
                      else
                        Text(
                          '도착 정보 없음',
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class HomeFavoriteBusList extends StatelessWidget {
  const HomeFavoriteBusList({
    super.key,
    required this.favoriteBuses,
    required this.stationArrivals,
    required this.getBusColor,
    required this.isFavoriteBus,
    required this.onToggleFavorite,
    required this.onAlarmTap,
  });

  final List<FavoriteBus> favoriteBuses;
  final Map<String, List<BusArrival>> stationArrivals;
  final BusColorResolver getBusColor;
  final FavoriteBusPredicate isFavoriteBus;
  final FavoriteToggleHandler onToggleFavorite;
  final AlarmTapHandler onAlarmTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (favoriteBuses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    colorScheme.primaryContainer.withOpacity(0.4),
                    colorScheme.secondaryContainer.withOpacity(0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colorScheme.primary.withOpacity(0.2),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.star_outline_rounded,
                      size: 32,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '자주 타는 버스를 추가해 보세요',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '정류장 검색 후 버스를 선택하여\n별 아이콘을 눌러 즐겨찾기에 추가할 수 있습니다.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: favoriteBuses.asMap().entries.map((entry) {
        final index = entry.key;
        final favorite = entry.value;
        final arrivals =
            stationArrivals[favorite.stationId] ?? const <BusArrival>[];
        final arrival = arrivals.firstWhere(
          (item) => item.routeId == favorite.routeId,
          orElse: () => BusArrival(
            routeId: favorite.routeId,
            routeNo: favorite.routeNo,
            direction: '',
            busInfoList: const [],
          ),
        );

        return TweenAnimationBuilder<double>(
          key: ValueKey(favorite.key),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 300 + (index * 80)),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Transform.translate(
              offset: Offset(0, 30 * (1 - value)),
              child: Opacity(opacity: value, child: child),
            );
          },
          child: HomeRouteItem(
            arrival: arrival,
            stationId: favorite.stationId,
            stationName: favorite.stationName,
            getBusColor: getBusColor,
            isFavoriteBus: isFavoriteBus,
            onToggleFavorite: onToggleFavorite,
            onAlarmTap: onAlarmTap,
          ),
        );
      }).toList(),
    );
  }
}

class HomeMainStationCard extends StatelessWidget {
  const HomeMainStationCard({
    super.key,
    required this.selectedStop,
    required this.isLoading,
    required this.errorMessage,
    required this.busArrivals,
    required this.onClearSelectedStop,
    required this.getBusColor,
    required this.isFavoriteBus,
    required this.onToggleFavorite,
    required this.onAlarmTap,
  });

  final BusStop? selectedStop;
  final bool isLoading;
  final String? errorMessage;
  final List<BusArrival> busArrivals;
  final VoidCallback onClearSelectedStop;
  final BusColorResolver getBusColor;
  final FavoriteBusPredicate isFavoriteBus;
  final FavoriteToggleHandler onToggleFavorite;
  final AlarmTapHandler onAlarmTap;

  @override
  Widget build(BuildContext context) {
    if (selectedStop == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 3,
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        selectedStop!.name,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (selectedStop!.id.isNotEmpty)
                        Text(
                          '정류장 번호: ${selectedStop!.id}',
                          style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onPressed: onClearSelectedStop,
                  tooltip: 'Close',
                ),
              ],
            ),
            Divider(height: 24, color: colorScheme.outlineVariant),
            if (isLoading)
              const Center(child: CircularProgressIndicator())
            else if (errorMessage != null)
              Text(errorMessage!, style: TextStyle(color: colorScheme.error))
            else if (busArrivals.isEmpty)
              const Text('해당 정류장에 도착하는 버스가 없습니다.')
            else
              Column(
                children: busArrivals.map((arrival) {
                  return HomeRouteItem(
                    arrival: arrival,
                    stationId: selectedStop?.stationId ?? selectedStop?.id ?? '',
                    stationName: selectedStop?.name ?? '',
                    getBusColor: getBusColor,
                    isFavoriteBus: isFavoriteBus,
                    onToggleFavorite: onToggleFavorite,
                    onAlarmTap: onAlarmTap,
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class HomeRouteItem extends StatelessWidget {
  const HomeRouteItem({
    super.key,
    required this.arrival,
    required this.stationId,
    required this.stationName,
    required this.getBusColor,
    required this.isFavoriteBus,
    required this.onToggleFavorite,
    required this.onAlarmTap,
  });

  final BusArrival arrival;
  final String stationId;
  final String stationName;
  final BusColorResolver getBusColor;
  final FavoriteBusPredicate isFavoriteBus;
  final FavoriteToggleHandler onToggleFavorite;
  final AlarmTapHandler onAlarmTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bus = arrival.firstBus;
    if (bus == null) return const SizedBox.shrink();

    final minutes = bus.getRemainingMinutes();
    final isLowFloor = bus.isLowFloor;
    final isOutOfService = bus.isOutOfService;

    // 1st Bus
    String timeText1 = '운행 종료';
    Color timeColor1 = colorScheme.onSurfaceVariant;

    if (!isOutOfService && minutes >= 0) {
      if (minutes == 0) {
        timeText1 = '곧 도착';
        timeColor1 = colorScheme.error;
      } else {
        timeText1 = '$minutes분';
        timeColor1 = minutes <= 3 ? colorScheme.error : colorScheme.onSurface;
      }
    } else if (minutes < 0) {
      timeText1 = '운행 종료';
    }

    String stopsText1 = '';
    if (!isOutOfService && bus.remainingStops.isNotEmpty) {
      final match = RegExp(r'\d+').firstMatch(bus.remainingStops);
      if (match != null) {
        stopsText1 = '${match.group(0)} 개소전';
      } else {
        stopsText1 = bus.remainingStops;
      }
    }

    // 2nd Bus
    String timeText2 = '';
    String stopsText2 = '';
    if (arrival.busInfoList.length > 1) {
      final bus2 = arrival.busInfoList[1];
      if (!bus2.isOutOfService) {
        final min2 = bus2.getRemainingMinutes();
        if (min2 >= 0) {
          timeText2 = min2 == 0 ? '곧 도착' : '$min2분';
          final match = RegExp(r'\d+').firstMatch(bus2.remainingStops);
          if (match != null) {
            stopsText2 = '${match.group(0)} 개소전';
          } else {
            stopsText2 = bus2.remainingStops;
          }
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          showUnifiedBusDetailModal(context, arrival, stationId, stationName);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 28,
                decoration: BoxDecoration(
                  color: getBusColor(context, arrival, isLowFloor),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(
                  child: Text(
                    arrival.routeNo,
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
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            timeText1,
                            style: TextStyle(
                              color: timeColor1,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          if (stopsText1.isNotEmpty)
                            Text(
                              stopsText1,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (timeText2.isNotEmpty)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              timeText2,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (stopsText2.isNotEmpty)
                              Text(
                                stopsText2,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
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
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      isFavoriteBus(FavoriteBus(
                        stationId: stationId,
                        stationName: stationName,
                        routeId: arrival.routeId,
                        routeNo: arrival.routeNo,
                      ))
                          ? Icons.star
                          : Icons.star_border,
                      color: colorScheme.primary,
                      size: 20,
                    ),
                    onPressed: () {
                      final stop = BusStop(
                        id: stationId,
                        stationId: stationId,
                        name: stationName,
                        isFavorite: false,
                      );
                      onToggleFavorite(stop, arrival);
                    },
                  ),
                  Selector<AlarmService, bool>(
                    selector: (context, alarmService) => alarmService.hasAlarm(
                      arrival.routeNo,
                      stationName,
                      arrival.routeId,
                    ),
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
                        onPressed: () {
                          onAlarmTap(
                            arrival,
                            stationId,
                            stationName,
                            hasAlarm,
                          );
                        },
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
