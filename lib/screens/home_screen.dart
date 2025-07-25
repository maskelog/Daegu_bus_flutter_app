import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:daegu_bus_app/screens/alarm_screen.dart';
import 'package:daegu_bus_app/screens/route_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import 'search_screen.dart';
import 'favorites_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../services/alarm_service.dart';
import 'settings_screen.dart';
import '../models/auto_alarm.dart';
import '../models/bus_route.dart';

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
  bool _isLoadingNearby = false;
  String? _errorMessage;
  Timer? _refreshTimer;
  final List<BusStop> _favoriteStops = [];
  List<BusStop> _nearbyStops = [];
  BusStop? _selectedStop;
  List<BusArrival> _busArrivals = [];
  final Map<String, List<BusArrival>> _stationArrivals = {};
  int? _expandedBusIndex;
  final Map<String, BusRouteType> _routeTypeCache = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this, initialIndex: 2);
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    alarmService.initialize();
    alarmService.addListener(_onAlarmChanged);
    _initializeData();
  }

  @override
  void dispose() {
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
      _isLoadingNearby = true;
      _errorMessage = null;
    });
    try {
      await Future.wait([_loadFavoriteStops(), _loadNearbyStations()]);
      await _loadBusArrivals();
      _setupPeriodicRefresh();
    } catch (e) {
      setState(() => _errorMessage = '데이터를 불러오는 중 오류가 발생했습니다: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingNearby = false;
        });
      }
    }
  }

  Future<void> _loadFavoriteStops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList('favorites') ?? [];
      if (!mounted) return;
      setState(() {
        _favoriteStops.clear();
        for (var json in favorites) {
          final data = jsonDecode(json);
          final stop = BusStop.fromJson(data);
          _favoriteStops.add(stop);
        }
        if (_favoriteStops.isNotEmpty && _selectedStop == null) {
          _selectedStop = _favoriteStops.first;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = '즐겨찾기를 불러오는 중 오류가 발생했습니다.');
    }
  }

  Future<void> _loadNearbyStations() async {
    setState(() {
      _isLoadingNearby = true;
      _errorMessage = null;
    });
    try {
      final status = await Permission.location.status;
      if (!status.isGranted) {
        final requestedStatus = await Permission.location.request();
        if (!requestedStatus.isGranted) {
          setState(() {
            _isLoadingNearby = false;
            _nearbyStops = [];
          });
          if (requestedStatus.isPermanentlyDenied && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('위치 권한이 영구적으로 거부되었습니다. 앱 설정에서 허용해주세요.'),
                action:
                    SnackBarAction(label: '설정 열기', onPressed: openAppSettings),
              ),
            );
          }
          return;
        }
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() {
          _isLoadingNearby = false;
          _nearbyStops = [];
          _errorMessage = '위치 서비스가 비활성화되어 있습니다. GPS를 켜주세요.';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 서비스(GPS)를 활성화해주세요.')),
          );
        }
        return;
      }
      if (!mounted) return;
      final nearbyStations =
          await LocationService.getNearbyStations(500, context: context);
      if (!mounted) return;
      setState(() {
        _nearbyStops = nearbyStations;
        if (_nearbyStops.isNotEmpty && _selectedStop == null) {
          _selectedStop = _nearbyStops.first;
          _loadBusArrivals();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '주변 정류장을 불러오는 중 오류 발생: ${e.toString()}';
          _nearbyStops = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingNearby = false);
      }
    }
  }

  Future<void> _saveFavoriteStops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites =
          _favoriteStops.map((stop) => jsonEncode(stop.toJson())).toList();
      await prefs.setStringList('favorites', favorites);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('즐겨찾기 저장에 실패했습니다')));
    }
  }

  void _toggleFavorite(BusStop stop) {
    setState(() {
      if (_isStopFavorite(stop)) {
        _favoriteStops.removeWhere((s) => s.id == stop.id);
        if (_selectedStop?.id == stop.id) {
          _selectedStop =
              _favoriteStops.isNotEmpty ? _favoriteStops.first : null;
          if (_selectedStop != null) {
            _loadBusArrivals();
          } else {
            _busArrivals = [];
          }
        }
      } else {
        _favoriteStops.add(stop.copyWith(isFavorite: true));
      }
    });
    _saveFavoriteStops();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isStopFavorite(stop)
            ? '${stop.name} 정류장이 즐겨찾기에 추가되었습니다'
            : '${stop.name} 정류장이 즐겨찾기에서 제거되었습니다'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  bool _isStopFavorite(BusStop stop) =>
      _favoriteStops.any((s) => s.id == stop.id);

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
          _errorMessage = '버스 도착 정보를 불러오지 못했습니다: $e';
        });
      }
    }
  }

  Future<void> _loadSelectedStationData(String busStationId) async {
    try {
      final stopArrivals = await ApiService.getStationInfo(busStationId);
      final routeIds = stopArrivals.map((a) => a.routeId).toSet();
      final missingRouteIds =
          routeIds.where((id) => !_routeTypeCache.containsKey(id)).toList();

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

      if (mounted && _selectedStop != null) {
        setState(() {
          _stationArrivals[_selectedStop!.id] = stopArrivals;
          _busArrivals = stopArrivals;
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
            const Duration(seconds: 30), (timer) => _loadBusArrivals())
        : null;
  }

  String _formatDistance(double? distance) {
    if (distance == null) return '';
    return distance < 1000
        ? '${distance.round()}m'
        : '${(distance / 1000).toStringAsFixed(1)}km';
  }

  Color _getBusColor(BuildContext context, BusArrival arrival, bool isLowFloor) {
    final routeType = _routeTypeCache[arrival.routeId];
    if (routeType == BusRouteType.express || arrival.routeNo.contains('급행')) {
      return Colors.red;
    }
    if (isLowFloor) {
      return Colors.blue;
    }
    return Colors.grey;
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
                    child: GestureDetector(
                      onTap: () async {
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
                                  "정류장 검색",
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
                  const SizedBox(width: 12),
                  IconButton.filledTonal(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => const SettingsScreen()),
                      );
                    },
                    icon: Icon(Icons.settings_outlined,
                        color: colorScheme.onSurface),
                    tooltip: '설정',
                  ),
                ],
              ),
            ),
            TabBar(
              controller: _tabController,
              labelColor: colorScheme.primary,
              unselectedLabelColor: colorScheme.onSurfaceVariant,
              indicatorColor: colorScheme.primary,
              tabs: const [
                Tab(text: '지도'),
                Tab(text: '노선도'),
                Tab(text: '홈'),
                Tab(text: '알람'),
                Tab(text: '즐겨찾기'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  const Center(child: Text('지도 탭 (구현 필요)')),
                  _buildRouteMapTab(),
                  _buildHomeTab(),
                  _buildAlarmTab(),
                  _buildFavoritesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHomeTab() {
    return Column(
      children: [
        Builder(
          builder: (context) {
            final alarms =
                Provider.of<AlarmService>(context).activeAlarms;
            return _buildAutoAlarmChips(alarms);
          },
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _initializeData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildStopSelectionButtons(
                      '주변 정류장', _getFilteredNearbyStops(),
                      isNearby: true),
                  _buildStopSelectionButtons(
                      '즐겨찾는 정류장', _favoriteStops,
                      isNearby: false),
                  _buildMainStationCard(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRouteMapTab() {
    return const SafeArea(top: true, bottom: false, child: RouteMapScreen());
  }

  Widget _buildFavoritesTab() {
    return SafeArea(
      top: true,
      bottom: false,
      child: FavoritesScreen(
        favoriteStops: _favoriteStops,
        onStopSelected: (stop) {
          // Handle stop selection from favorites
        },
        onFavoriteToggle: _toggleFavorite,
      ),
    );
  }

  Widget _buildAlarmTab() {
    return const AlarmScreen();
  }

  Widget _buildStopSelectionButtons(String title, List<BusStop> stops,
      {bool isNearby = false}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          if (stops.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                isNearby ? '주변 정류장이 없습니다.' : '즐겨찾는 정류장이 없습니다.',
                style: TextStyle(
                    color: colorScheme.onSurfaceVariant, fontSize: 14),
              ),
            )
          else if (isNearby)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: stops.map((stop) {
                  final isSelected = _selectedStop?.id == stop.id;
                  final label =
                      '${stop.name} - ${_formatDistance(stop.distance)}';
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(
                        label,
                        style: TextStyle(
                          color: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface,
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() => _selectedStop = stop);
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
                    ),
                  );
                }).toList(),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: stops.map((stop) {
                final isSelected = _selectedStop?.id == stop.id;
                return ChoiceChip(
                  label: Text(
                    stop.name,
                    style: TextStyle(
                      color: isSelected
                          ? colorScheme.onPrimary
                          : colorScheme.onSurface,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (_) {
                    setState(() => _selectedStop = stop);
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
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildAutoAlarmChips(List<dynamic> alarms) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '자동 알람',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          if (alarms.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('설정된 자동 알람이 없습니다.',
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant, fontSize: 14)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: alarms.whereType<AutoAlarm>().map((alarm) {
                final isSelected = _selectedStop?.name == alarm.stationName;
                return ChoiceChip(
                  label: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${alarm.routeNo}  ${alarm.hour.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(
                            color: isSelected
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          )),
                      Text(alarm.stationName,
                          style: TextStyle(
                            color: isSelected
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            fontSize: 13,
                          )),
                      Text(
                        alarm.repeatDays
                            .map((d) =>
                                ["월", "화", "수", "목", "금", "토", "일"][d - 1])
                            .join(","),
                        style: TextStyle(
                          color: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onSurfaceVariant,
                          fontSize: 12,
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
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  List<BusStop> _getFilteredNearbyStops() {
    final favoriteStopIds = _favoriteStops.map((stop) => stop.id).toSet();
    return _nearbyStops
        .where((stop) => !favoriteStopIds.contains(stop.id))
        .toList();
  }

  Widget _buildMainStationCard() {
    if (_selectedStop == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
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
                    _isStopFavorite(_selectedStop!)
                        ? Icons.star
                        : Icons.star_border,
                    color: colorScheme.primary,
                  ),
                  onPressed: () => _toggleFavorite(_selectedStop!),
                  tooltip: _isStopFavorite(_selectedStop!)
                      ? '즐겨찾기에서 제거'
                      : '즐겨찾기에 추가',
                ),
              ],
            ),
            Divider(height: 24, color: colorScheme.outlineVariant),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_errorMessage != null)
              Text(_errorMessage!, style: TextStyle(color: colorScheme.error))
            else if (_busArrivals.isEmpty)
              const Text('도착 예정 버스가 없습니다.')
            else
              Column(
                children: _busArrivals.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final arrival = entry.value;
                  final bus = arrival.firstBus;
                  if (bus == null) return const SizedBox.shrink();
                  final minutes = bus.getRemainingMinutes();
                  final isLowFloor = bus.isLowFloor;
                  final isOutOfService = bus.isOutOfService;
                  String timeText;
                  if (isOutOfService) {
                    timeText = '운행종료';
                  } else if (minutes <= 0) {
                    timeText = '곧 도착';
                  } else {
                    timeText = '$minutes분 후 도착';
                  }
                  final stopsText =
                      !isOutOfService ? '${bus.remainingStops}개 전' : '';
                  final isSoon = !isOutOfService && minutes <= 1;
                  final isWarning =
                      !isOutOfService && minutes > 1 && minutes <= 3;
                  final routeNo = arrival.routeNo;
                  final routeId = arrival.routeId;
                  final stationName = _selectedStop?.name ?? '';
                  return Column(
                    children: [
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _expandedBusIndex =
                                _expandedBusIndex == idx ? null : idx;
                          });
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(14),
                            border:
                                Border.all(color: colorScheme.outlineVariant),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            leading: CircleAvatar(
                              backgroundColor:
                                  _getBusColor(context, arrival, isLowFloor),
                              child: Text(
                                arrival.routeNo,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize:
                                      arrival.routeNo.length > 4 ? 13 : 16,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            title: Row(
                              children: [
                                Text(
                                  timeText,
                                  style: TextStyle(
                                    color: isOutOfService
                                        ? colorScheme.onSurfaceVariant
                                        : isSoon
                                            ? colorScheme.error
                                            : isWarning
                                                ? colorScheme.tertiary
                                                : colorScheme.onSurface,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                if (stopsText.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(stopsText,
                                      style: TextStyle(
                                          color: colorScheme.onSurfaceVariant,
                                          fontSize: 13)),
                                ],
                                if (isLowFloor)
                                  Icon(Icons.accessible,
                                      size: 18, color: Colors.blue),
                              ],
                            ),
                            subtitle: bus.currentStation.isNotEmpty
                                ? Text('현재 위치: ${bus.currentStation}',
                                    style: TextStyle(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 12))
                                : null,
                            trailing: Selector<AlarmService, bool>(
                              selector: (context, alarmService) => alarmService
                                  .hasAlarm(routeNo, stationName, routeId),
                              builder: (context, hasAlarm, child) {
                                return IconButton(
                                  icon: Icon(
                                    hasAlarm
                                        ? Icons.notifications_active
                                        : Icons.notifications_none,
                                    color: hasAlarm
                                        ? colorScheme.primary
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                  tooltip: hasAlarm ? '알람 해제' : '승차 알람',
                                  onPressed: () async {
                                    final alarmService =
                                        Provider.of<AlarmService>(context,
                                            listen: false);
                                    try {
                                      if (hasAlarm) {
                                        await alarmService.cancelAlarmByRoute(
                                            routeNo, stationName, routeId);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    '$routeNo번 버스 알람이 해제되었습니다')),
                                          );
                                        }
                                      } else {
                                        if (minutes <= 0) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                  content: Text(
                                                      '버스가 이미 도착했거나 곧 도착합니다')),
                                            );
                                          }
                                          return;
                                        }
                                        await alarmService.setOneTimeAlarm(
                                          routeNo,
                                          stationName,
                                          minutes,
                                          routeId: routeId,
                                          useTTS: true,
                                          isImmediateAlarm: true,
                                          currentStation: bus.currentStation,
                                        );
                                        if (mounted) {
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    '$routeNo번 버스 알람이 설정되었습니다')),
                                          );
                                        }
                                      }
                                    } catch (e) {
                                      if (mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          SnackBar(
                                              content: Text(
                                                  '알람 처리 중 오류가 발생했습니다: $e')),
                                        );
                                      }
                                    }
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                      if (_expandedBusIndex == idx)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                            border:
                                Border.all(color: colorScheme.outlineVariant),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (arrival.secondBus != null)
                                Row(
                                  children: [
                                    Icon(Icons.directions_bus,
                                        size: 16, color: colorScheme.primary),
                                    const SizedBox(width: 6),
                                    Text(
                                      '다음차: ${arrival.getSecondArrivalTimeText()}',
                                      style: TextStyle(
                                          fontSize: 14,
                                          color: colorScheme.onSurface),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }
}