import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:daegu_bus_app/widgets/home_search_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:daegu_bus_app/screens/alarm_screen.dart';
import 'package:daegu_bus_app/screens/map_screen.dart';
import 'package:daegu_bus_app/screens/route_map_screen.dart';
import 'package:flutter/material.dart';
import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';
import '../services/api_service.dart';
import 'search_screen.dart';
import 'package:provider/provider.dart';
import '../services/alarm_service.dart';
import 'settings_screen.dart';
import '../models/auto_alarm.dart';
import '../models/bus_route.dart';
import '../widgets/station_loading_widget.dart';
import '../models/favorite_bus.dart';
import '../utils/favorite_bus_store.dart';
import 'home_widgets.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _refreshTimer;
  final List<BusStop> _favoriteStops = [];
  List<BusStop> _nearbyStops = [];
  BusStop? _selectedStop;
  List<BusArrival> _busArrivals = [];
  final Map<String, List<BusArrival>> _stationArrivals = {};
  final Map<String, BusRouteType> _routeTypeCache = {};
  List<FavoriteBus> _favoriteBuses = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: 2); // 4 tabs: 지도, 노선도, 홈, 알람
    _tabController.addListener(_handleTabSelection); // 리스너 추가
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    alarmService.initialize();
    alarmService.addListener(_onAlarmChanged);
    _initializeData();
  }

  void _handleTabSelection() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabSelection); // 리스너 제거
    _tabController.dispose();
    Provider.of<AlarmService>(context, listen: false)
        .removeListener(_onAlarmChanged);
    _searchController.dispose();
    _refreshTimer?.cancel();

    super.dispose();
  }

  void _onAlarmChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _loadFavoriteBuses();
      await _loadBusArrivals();
      _setupPeriodicRefresh();
    } catch (e) {
      setState(() => _errorMessage = '버스 정보를 불러오는 데 실패했습니다: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _onNearbyStopsLoaded(List<BusStop> nearbyStops) {
    setState(() {
      _nearbyStops = nearbyStops;
    });
  }

  void _onFavoriteStopsLoaded(List<BusStop> favoriteStops) {
    setState(() {
      _favoriteStops.clear();
      _favoriteStops.addAll(favoriteStops);
    });
  }

  void _onSelectedStopChanged(BusStop? selectedStop) {
    setState(() {
      _selectedStop = selectedStop;
    });
    if (selectedStop != null) {
      _loadBusArrivals();
    } else {
      _busArrivals = [];
    }
  }

  void _clearSelectedStop() {
    if (!mounted) return;
    setState(() {
      _selectedStop = null;
      _busArrivals = [];
      _errorMessage = null;
    });
    _setupPeriodicRefresh();
  }

  Future<void> _loadFavoriteBuses() async {
    final loaded = await FavoriteBusStore.load();
    if (!mounted) return;
    setState(() {
      _favoriteBuses = loaded;
    });
    _loadFavoriteBusArrivals();
  }

  Future<void> _loadFavoriteBusArrivals() async {
    final stationIds = _favoriteBuses
        .map((bus) => bus.stationId)
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final stationId in stationIds) {
      if (_stationArrivals.containsKey(stationId)) {
        continue;
      }
      try {
        final arrivals = await ApiService.getStationInfo(stationId);
        if (mounted) {
          setState(() => _stationArrivals[stationId] = arrivals);
        }
      } catch (e) {
        if (mounted) {
          setState(() => _stationArrivals[stationId] = <BusArrival>[]);
        }
      }
    }
  }

  bool _isFavoriteBus(FavoriteBus bus) {
    return _favoriteBuses.any((item) => item.key == bus.key);
  }

  Future<void> _toggleFavoriteBus(BusStop stop, BusArrival arrival) async {
    final stationId = stop.stationId ?? stop.id;
    final favorite = FavoriteBus(
      stationId: stationId,
      stationName: stop.name,
      routeId: arrival.routeId,
      routeNo: arrival.routeNo,
    );
    final isAlreadyFavorite = _isFavoriteBus(favorite);
    final updated = FavoriteBusStore.toggle(_favoriteBuses, favorite);
    await FavoriteBusStore.save(updated);
    if (!mounted) return;
    setState(() {
      _favoriteBuses = updated;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isAlreadyFavorite
            ? '${favorite.routeNo}번 버스 즐겨찾기를 해제했습니다.'
            : '${favorite.routeNo}번 버스를 즐겨찾기에 추가했습니다.'),
      ),
    );
  }

  Future<void> _loadBusArrivals() async {
    if (_selectedStop == null) {
      if (mounted) {
        setState(() {
          _busArrivals = [];
          _isLoading = false;
        });
      }
      return;
    }
    final String busStationId = _selectedStop!.stationId ?? _selectedStop!.id;
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }
    try {
      await _loadSelectedStationData(busStationId);
      _loadOtherStationsInBackground();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '버스 도착 정보를 불러오는 데 실패했습니다: $e';
        });
      }
    }
  }

  Future<void> _loadSelectedStationData(String busStationId) async {
    try {
      final stopArrivals = await ApiService.getStationInfo(busStationId);

      // UI 업데이트
      if (mounted && _selectedStop != null) {
        setState(() {
          _stationArrivals[_selectedStop!.id] = stopArrivals;
          _busArrivals = stopArrivals;
          _isLoading = false;
        });
      }

      _loadRouteDetailsInBackground(stopArrivals);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '버스 도착 정보를 불러오는 데 실패했습니다: $e';
        });
      }
    }
  }

  Future<void> _loadRouteDetailsInBackground(List<BusArrival> arrivals) async {
    try {
      final routeIds = arrivals.map((a) => a.routeId).toSet();
      final missingRouteIds =
          routeIds.where((id) => !_routeTypeCache.containsKey(id)).toList();

      if (missingRouteIds.isEmpty) return;

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
      if (newTypes.isNotEmpty && mounted) {
        setState(() {
          _routeTypeCache.addAll(newTypes);
        });
      }
    } catch (e) {
      print('백그라운드 로드 실패: $e');
    }
  }

  void _loadOtherStationsInBackground() {
    Future.microtask(() async {
      final allStops = [..._nearbyStops, ..._favoriteStops];
      final otherStops = allStops
          .where(
              (stop) => _selectedStop == null || stop.id != _selectedStop!.id)
          .toList();
      const batchSize = 5;
      for (int i = 0; i < otherStops.length; i += batchSize) {
        final batch = otherStops.skip(i).take(batchSize);
        await Future.wait(batch.map((stop) async {
          try {
            final stationId = stop.stationId ?? stop.id;
            if (stationId.isNotEmpty) {
              final arrivals = await ApiService.getStationInfo(stationId);
              if (mounted) {
                setState(() => _stationArrivals[stop.id] = arrivals);
              }
            }
          } catch (e) {
            if (mounted) {
              setState(() => _stationArrivals[stop.id] = <BusArrival>[]);
            }
          }
        }));
        await Future.delayed(const Duration(milliseconds: 50));
      }
    });
  }

  void _setupPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = _selectedStop != null
        ? Timer.periodic(
            const Duration(seconds: 60), (timer) => _loadBusArrivals())
        : null;
  }

  Color _getBusColor(
      BuildContext context, BusArrival arrival, bool isLowFloor) {
    final routeType = _routeTypeCache[arrival.routeId];

    if (routeType == BusRouteType.express || arrival.routeNo.contains('급행')) {
      return const Color(0xFFE53935);
    }
    if (isLowFloor) {
      return const Color(0xFF2196F3);
    }
    return const Color(0xFF757575);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: HomeSearchBar(
                hintText: '버스 또는 정류장 검색',
                onSearchTap: () async {
                  HapticFeedback.lightImpact();
                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SearchScreen(
                        favoriteStops: _favoriteStops,
                      ),
                    ),
                  );
                  if (result != null && result is BusStop) {
                    setState(() => _selectedStop = result);
                    _loadBusArrivals();
                  }
                },
                onSettingsTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  TabBarView(
                    controller: _tabController,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      const MapScreen(),
                      _buildMapTab(),
                      _buildHomeTab(),
                      _buildAlarmTab(),
                    ],
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 20,
                              offset: const Offset(0, 8),
                            ),
                            BoxShadow(
                              color: colorScheme.primary.withOpacity(0.1),
                              blurRadius: 30,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(28),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 6),
                              decoration: BoxDecoration(
                                color: colorScheme.surface.withOpacity(0.95),
                                borderRadius: BorderRadius.circular(28),
                                border: Border.all(
                                  color: colorScheme.outline.withOpacity(0.2),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildNavItem(
                                    icon: Icons.map_rounded,
                                    label: '지도',
                                    index: 0,
                                    colorScheme: colorScheme,
                                  ),
                                  _buildNavItem(
                                    icon: Icons.route_rounded,
                                    label: '노선도',
                                    index: 1,
                                    colorScheme: colorScheme,
                                  ),
                                  _buildNavItem(
                                    icon: Icons.home_rounded,
                                    label: '홈',
                                    index: 2,
                                    colorScheme: colorScheme,
                                  ),
                                  _buildNavItem(
                                    icon: Icons.notifications_active_rounded,
                                    label: '알람',
                                    index: 3,
                                    colorScheme: colorScheme,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    final alarms = Provider.of<AlarmService>(context).activeAlarms;
    final colorScheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _initializeData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _buildAutoAlarmChips(alarms),
          const SizedBox(height: 8),
          StationLoadingWidget(
            onNearbyStopsLoaded: _onNearbyStopsLoaded,
            onFavoriteStopsLoaded: _onFavoriteStopsLoaded,
            onSelectedStopChanged: _onSelectedStopChanged,
            selectedStop: _selectedStop,
            favoriteStops: _favoriteStops,
            showSelectors: false,
          ),
          const SizedBox(height: 12),
          // Nearby \uac1c\uc18c\uc804 section with improved design
          HomeSectionHeader(
            title: '근처 정류장',
            icon: Icons.location_on_rounded,
            iconColor: colorScheme.tertiary,
          ),
          const SizedBox(height: 8),
          HomeNearbyStopsRow(
            nearbyStops: _nearbyStops,
            maxItems: 8,
            selectedStop: _selectedStop,
            stationArrivals: _stationArrivals,
            onStopSelected: _onSelectedStopChanged,
            formatArrivalTime: _formatArrivalTime,
          ),
          const SizedBox(height: 20),
          // Favorites section with improved design
          HomeSectionHeader(
            title: '즐겨찾기',
            icon: Icons.star_rounded,
            iconColor: colorScheme.primary,
          ),
          const SizedBox(height: 8),
          HomeFavoriteBusList(
            favoriteBuses: _favoriteBuses,
            stationArrivals: _stationArrivals,
            getBusColor: _getBusColor,
            isFavoriteBus: _isFavoriteBus,
            onToggleFavorite: _toggleFavoriteBus,
            onAlarmTap: _handleAlarmClick,
          ),
          const SizedBox(height: 12),
          HomeMainStationCard(
            selectedStop: _selectedStop,
            isLoading: _isLoading,
            errorMessage: _errorMessage,
            busArrivals: _busArrivals,
            onClearSelectedStop: _clearSelectedStop,
            getBusColor: _getBusColor,
            isFavoriteBus: _isFavoriteBus,
            onToggleFavorite: _toggleFavoriteBus,
            onAlarmTap: _handleAlarmClick,
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildMapTab() {

    return const SafeArea(top: true, bottom: false, child: RouteMapScreen());
  }

  Widget _buildAlarmTab() {
    return const AlarmScreen();
  }

  // Material 3 Expressive Floating Navigation Item
  Widget _buildNavItem({
    required IconData icon,
    required String label,
    required int index,
    required ColorScheme colorScheme,
  }) {
    final isSelected = _tabController.index == index;
    
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _tabController.animateTo(index);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8), // Reduced padding
          decoration: BoxDecoration(
            color: isSelected 
                ? colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(20), // Slightly reduced inner radius
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isSelected ? 1.1 : 1.0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                child: Icon(
                  icon,
                  color: isSelected 
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                  size: 24, // Reduced icon size
                ),
              ),
              const SizedBox(height: 2), // Reduced gap
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 300),
                style: TextStyle(
                  fontSize: isSelected ? 12 : 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected 
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
                child: Text(label),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAutoAlarmChips(List<dynamic> alarms) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (alarms.isEmpty)
            const SizedBox.shrink()
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: alarms.whereType<AutoAlarm>().map((alarm) {
                    final isSelected = _selectedStop?.name == alarm.stationName;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                '${alarm.routeNo}  ${alarm.hour.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  color: isSelected
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                )),
                            Text(alarm.stationName,
                                style: TextStyle(
                                  color: isSelected
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface,
                                  fontSize: 11,
                                )),
                            Text(
                              alarm.repeatDays
                                  .map((d) => ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][d - 1])
                                  .join(","),
                              style: TextStyle(
                                color: isSelected
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurfaceVariant,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                        selected: isSelected,
                        onSelected: (_) {
                          final allStops = [..._favoriteStops, ..._nearbyStops];
                          final match = allStops.firstWhere(
                            (s) => s.name == alarm.stationName,
                            orElse: () => BusStop(
                                id: alarm.stationId,
                                name: alarm.stationName,
                                isFavorite: false),
                          );
                          setState(() => _selectedStop = match);
                          _loadBusArrivals();
                        },
                        selectedColor: colorScheme.primary,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        side: BorderSide(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant,
                          width: isSelected ? 2 : 1,
                        ),
                        labelPadding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 1), 
                        showCheckmark: false,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _isStopFavorite(BusStop stop) =>
      _favoriteStops.any((s) => s.id == stop.id);

  Future<void> _toggleFavorite(BusStop stop) async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList('favorites') ?? [];
    
    final isCurrentlyFavorite = _favoriteStops.any((s) => s.id == stop.id);
    
    setState(() {
      if (isCurrentlyFavorite) {
        // 즐겨찾기 제거
        favorites.removeWhere((json) {
          final existing = BusStop.fromJson(jsonDecode(json));
          return existing.id == stop.id;
        });
        _favoriteStops.removeWhere((s) => s.id == stop.id);
        
        // 현재 선택된 정류소가 즐겨찾기 제거된 경우 UI 업데이트
        if (_selectedStop?.id == stop.id) {
          _selectedStop = stop.copyWith(isFavorite: false);
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(' removed from favorites')),
        );
      } else {
        // 즐겨찾기 추가
        final favoriteStop = stop.copyWith(isFavorite: true);
        final stopJson = jsonEncode(favoriteStop.toJson());
        favorites.add(stopJson);
        _favoriteStops.add(favoriteStop);
        
        // 현재 선택된 정류소가 즐겨찾기 추가된 경우 UI 업데이트
        if (_selectedStop?.id == stop.id) {
          _selectedStop = favoriteStop;
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(' added to favorites')),
        );
      }
    });
    
    await prefs.setStringList('favorites', favorites);
  }


  String _formatArrivalTime(BusArrival arrival) {
    final bus = arrival.firstBus;
    if (bus == null) return "도착 정보 없음";
    if (bus.isOutOfService) return "운행 종료";
    final minutes = bus.getRemainingMinutes();
    if (minutes < 0) return "운행 종료";
    if (minutes <= 0) return "곧 도착";
    return "${minutes}분";
  }

  Future<void> _handleAlarmClick(
      BusArrival arrival, String stationId, String stationName, bool hasAlarm) async {
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final bus = arrival.firstBus;
    if (bus == null) return;
    final minutes = bus.getRemainingMinutes();
    final routeNo = arrival.routeNo;
    final routeId = arrival.routeId;

    try {
      if (hasAlarm) {
        await alarmService.cancelAlarmByRoute(routeNo, stationName, routeId);
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('알람이 해제되었습니다.')),
          );
        }
      } else {
        if (minutes <= 0) {
          if (mounted) {
            scaffoldMessenger.showSnackBar(
              const SnackBar(content: Text('버스가 이미 도착했거나 지나갔습니다.')),
            );
          }
          return;
        }
        await alarmService.setOneTimeAlarm(
          routeNo,
          stationName,
          minutes,
          routeId: routeId,
          stationId: stationId,
          useTTS: true,
          isImmediateAlarm: true,
          currentStation: bus.currentStation,
        );
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text('$routeNo번 버스 알람이 설정되었습니다.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('알람 처리에 실패했습니다: $e')),
        );
      }
    }
  }
  

}
