import 'dart:async';
import 'dart:convert';
import 'dart:ui'; // For BackdropFilter
import 'package:flutter/services.dart';
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
import '../widgets/unified_bus_detail_widget.dart';
import '../models/favorite_bus.dart';
import '../utils/favorite_bus_store.dart';

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
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: '정류장 검색',
                      hint: '정류장 이름을 입력해 검색합니다',
                      child: GestureDetector(
                        onTap: () async {
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
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(28),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 14),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.search_rounded,
                                  color: colorScheme.onSurfaceVariant,
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '정류장 검색',
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 16,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    label: '설정',
                    hint: '설정 화면으로 이동',
                    child: IconButton.filledTonal(
                      onPressed: () {
                        HapticFeedback.lightImpact();
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SettingsScreen(),
                          ),
                        );
                      },
                      icon: Icon(Icons.settings_outlined,
                          color: colorScheme.onSurface),
                      tooltip: '설정',
                    ),
                  ),
                ],
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
          // Nearby stops section with improved design
          _buildSectionHeader(
            title: '근처 정류장',
            icon: Icons.location_on_rounded,
            iconColor: colorScheme.tertiary,
          ),
          const SizedBox(height: 8),
          _buildNearbyStopsRow(
            stops: _nearbyStops,
            maxItems: 8,
          ),
          const SizedBox(height: 20),
          // Favorites section with improved design
          _buildSectionHeader(
            title: '즐겨찾기',
            icon: Icons.star_rounded,
            iconColor: colorScheme.primary,
          ),
          const SizedBox(height: 8),
          _buildFavoriteBusList(),
          const SizedBox(height: 12),
          _buildMainStationCard(),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required IconData icon,
    required Color iconColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: iconColor),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
              letterSpacing: -0.3,
            ),
          ),
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
                          final stops = [..._favoriteStops, ..._nearbyStops];
                          final match = stops.firstWhere(
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
    return "${minutes} min";
  }

  Widget _buildFavoriteBusList() {
    final colorScheme = Theme.of(context).colorScheme;

    if (_favoriteBuses.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                colorScheme.primaryContainer.withOpacity(0.3),
                colorScheme.surfaceContainerHighest.withOpacity(0.5),
              ],
            ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.outlineVariant.withOpacity(0.3),
            ),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.star_outline_rounded,
                  size: 28,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '즐겨찾기한 버스가 없습니다',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '정류장에서 버스를 선택하여 추가하세요',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        children: _favoriteBuses.asMap().entries.map((entry) {
          final index = entry.key;
          final favorite = entry.value;
          final arrivals = _stationArrivals[favorite.stationId] ??
              const <BusArrival>[];
          final arrival = arrivals.firstWhere(
            (item) => item.routeId == favorite.routeId,
            orElse: () => BusArrival(
              routeId: favorite.routeId,
              routeNo: favorite.routeNo,
              direction: '',
              busInfoList: const [],
            ),
          );
          final bus = arrival.firstBus;
          final timeText = bus == null ? '도착 정보 없음' : _formatArrivalTime(arrival);
          final currentStation = bus?.currentStation ?? '위치 정보 없음';
          final minutes = bus?.getRemainingMinutes() ?? -1;
          final isArriving = minutes >= 0 && minutes <= 3;

          return TweenAnimationBuilder<double>(
            key: ValueKey(favorite.key),
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 200 + (index * 50)),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, 20 * (1 - value)),
                child: Opacity(opacity: value, child: child),
              );
            },
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
                border: isArriving
                    ? Border.all(color: colorScheme.error.withOpacity(0.4), width: 1.5)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    showUnifiedBusDetailModal(
                      context,
                      arrival,
                      favorite.stationId,
                      favorite.stationName,
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        // Route number badge with gradient
                        Container(
                          width: 54,
                          height: 32,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                colorScheme.primary,
                                colorScheme.primary.withOpacity(0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: colorScheme.primary.withOpacity(0.3),
                                blurRadius: 4,
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
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        // Station and time info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                favorite.stationName,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                  letterSpacing: -0.2,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  if (isArriving)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      margin: const EdgeInsets.only(right: 6),
                                      decoration: BoxDecoration(
                                        color: colorScheme.errorContainer,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        timeText,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: colorScheme.onErrorContainer,
                                        ),
                                      ),
                                    )
                                  else
                                    Text(
                                      timeText,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  if (!isArriving) ...[
                                    Text(
                                      ' · ',
                                      style: TextStyle(
                                        color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                                      ),
                                    ),
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
                                ],
                              ),
                            ],
                          ),
                        ),
                        // Action buttons
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildActionButton(
                              icon: Icons.headphones_rounded,
                              color: colorScheme.tertiary,
                              onPressed: () => _handleEarphoneAlarm(favorite, arrival),
                            ),
                            const SizedBox(width: 4),
                            _buildActionButton(
                              icon: Icons.star_rounded,
                              color: colorScheme.primary,
                              onPressed: () {
                                final stop = BusStop(
                                  id: favorite.stationId,
                                  stationId: favorite.stationId,
                                  name: favorite.stationName,
                                  isFavorite: false,
                                );
                                _toggleFavoriteBus(stop, arrival);
                              },
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
        }).toList(),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(8),
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

  Widget _buildStopsSection({
    required String title,
    required List<BusStop> stops,
    required int maxItems,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleStops = stops.take(maxItems).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (visibleStops.isEmpty)
            const SizedBox.shrink()
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: visibleStops.map((stop) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      onTap: () => _onSelectedStopChanged(stop),
                      borderRadius: BorderRadius.circular(18),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withOpacity(0.4),
                          ),
                        ),
                        child: Text(
                          stop.name,
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNearbyStopsRow({
    required List<BusStop> stops,
    required int maxItems,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final visibleStops = stops.take(maxItems).toList();

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
          final isSelected = _selectedStop?.id == stop.id;
          final arrivals = _stationArrivals[stop.id] ?? [];
          final topBus = arrivals.isNotEmpty ? arrivals.first : null;

          return Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _onSelectedStopChanged(stop),
                borderRadius: BorderRadius.circular(16),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                    boxShadow: isSelected ? [
                      BoxShadow(
                        color: colorScheme.primary.withOpacity(0.15),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ] : null,
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
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                              _formatArrivalTime(topBus),
                              style: TextStyle(
                                fontSize: 11,
                                color: isSelected
                                    ? colorScheme.onPrimaryContainer.withOpacity(0.8)
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

  Widget _buildMainStationCard() {
    if (_selectedStop == null) return const SizedBox.shrink();
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
                        _selectedStop!.name,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (_selectedStop!.id.isNotEmpty)
                        Text(
                          '정류장 번호: ${_selectedStop!.id}',
                          style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  onPressed: _clearSelectedStop,
                  tooltip: 'Close',
                ),
              ],
            ),
            Divider(height: 24, color: colorScheme.outlineVariant),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_errorMessage != null)
              Text(_errorMessage!, style: TextStyle(color: colorScheme.error))
            else if (_busArrivals.isEmpty)
              const Text('해당 정류장에 도착하는 버스가 없습니다.')
            else
              Column(
                children: _busArrivals.map((arrival) {
                  final bus = arrival.firstBus;
                  if (bus == null) return const SizedBox.shrink();

                  final minutes = bus.getRemainingMinutes();
                  final isLowFloor = bus.isLowFloor;
                  final isOutOfService = bus.isOutOfService;
                  String timeText;
                  Color timeColor;
                  
                  if (isOutOfService) {
                    timeText = '운행 종료';
                    timeColor = colorScheme.onSurfaceVariant;
                  } else if (minutes < 0) {
                    timeText = '운행 종료';
                    timeColor = colorScheme.onSurfaceVariant;
                  } else if (minutes <= 0) {
                    timeText = '곧 도착';
                    timeColor = colorScheme.error;
                  } else if (minutes <= 3) {
                    timeText = minutes.toString();
                    timeColor = colorScheme.error;
                  } else {
                    timeText = minutes.toString();
                    timeColor = colorScheme.onSurface;
                  }
                  
                  final remainingStops = int.tryParse(
                        bus.remainingStops.toString(),
                      ) ??
                      -1;
                  final stopsText = !isOutOfService && remainingStops >= 0
                      ? '${remainingStops} stops'
                      : '';
                  final routeNo = arrival.routeNo;
                  final routeId = arrival.routeId;
                  final stationName = _selectedStop?.name ?? '';
                  final stationId = _selectedStop?.stationId ?? _selectedStop?.id ?? '';

                  return InkWell(
                    onTap: () {
                      showUnifiedBusDetailModal(
                        context,
                        arrival,
                        stationId,
                        stationName,
                      );
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
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
                            color: _getBusColor(context, arrival, isLowFloor),
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
                                  if (!isOutOfService && minutes > 0) ...[
                                    const SizedBox(width: 4),
                                    Text(
                                      'min',
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
                                  'Next',
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
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              icon: Icon(
                                _isFavoriteBus(FavoriteBus(
                                  stationId: stationId,
                                  stationName: stationName,
                                  routeId: routeId,
                                  routeNo: routeNo,
                                ))
                                    ? Icons.star
                                    : Icons.star_border,
                                color: colorScheme.primary,
                                size: 20,
                              ),
                              onPressed: () {
                                if (_selectedStop == null) return;
                                _toggleFavoriteBus(_selectedStop!, arrival);
                              },
                            ),
                            Selector<AlarmService, bool>(
                              selector: (context, alarmService) =>
                                  alarmService.hasAlarm(routeNo, stationName, routeId),
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
                                            routeNo, stationName, routeId);
                                        if (mounted) {
                                          scaffoldMessenger.showSnackBar(
                                            SnackBar(
                                                content: Text(' alarm cancelled')),
                                          );
                                        }
                                      } else {
                                        if (minutes <= 0) {
                                          if (mounted) {
                                            scaffoldMessenger.showSnackBar(
                                              const SnackBar(
                                                  content: Text('Bus is arriving or already arrived')),
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
                                            SnackBar(
                                                content: Text(' alarm set')),
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        scaffoldMessenger.showSnackBar(
                                          SnackBar(
                                              content: Text('알람처리 오류가 발생했습니다: $e')),
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
                  ),
                );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}
