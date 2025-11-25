import 'dart:async';
import 'dart:convert';
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
import 'favorites_screen.dart';
import 'package:provider/provider.dart';
import '../services/alarm_service.dart';
import 'settings_screen.dart';
import '../models/auto_alarm.dart';
import '../models/bus_route.dart';
import '../widgets/station_loading_widget.dart';
import '../widgets/unified_bus_detail_widget.dart';

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
      _errorMessage = null;
    });
    try {
      await _loadBusArrivals();
      _setupPeriodicRefresh();
    } catch (e) {
      setState(() => _errorMessage = '데이터를 불러오는 중 오류가 발생했습니다: $e');
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
      // 1단계: 정류장 도착 정보 가져오기
      final stopArrivals = await ApiService.getStationInfo(busStationId);

      // 2단계: 즉시 UI 업데이트 (빠른 응답)
      if (mounted && _selectedStop != null) {
        setState(() {
          _stationArrivals[_selectedStop!.id] = stopArrivals;
          _busArrivals = stopArrivals;
          _isLoading = false;
        });
      }

      // 3단계: 노선 상세 정보는 백그라운드에서 로드 (UI 블로킹 없음)
      _loadRouteDetailsInBackground(stopArrivals);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '버스 도착 정보를 불러오지 못했습니다: $e';
        });
      }
    }
  }

  /// 노선 상세 정보를 백그라운드에서 로드 (UI 블로킹 없음)
  Future<void> _loadRouteDetailsInBackground(List<BusArrival> arrivals) async {
    try {
      final routeIds = arrivals.map((a) => a.routeId).toSet();
      final missingRouteIds =
          routeIds.where((id) => !_routeTypeCache.containsKey(id)).toList();

      if (missingRouteIds.isEmpty) return;

      // 백그라운드에서 노선 상세 정보 로드
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

      // 캐시에 추가
      final newTypes = <String, BusRouteType>{};
      for (final entry in results) {
        if (entry != null) newTypes[entry.key] = entry.value;
      }

      // 새로운 노선 타입 정보가 있으면 UI 업데이트 (색상 반영)
      if (newTypes.isNotEmpty && mounted) {
        setState(() {
          _routeTypeCache.addAll(newTypes);
        });
      }
    } catch (e) {
      // 백그라운드 로드 실패는 무시 (이미 도착 정보는 표시됨)
      print('노선 상세 정보 백그라운드 로드 실패: $e');
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
                      hint: '탭하여 정류장을 검색하세요',
                      child: GestureDetector(
                        onTap: () async {
                          // 햅틱 피드백 추가
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
                  ),
                  const SizedBox(width: 12),
                  Semantics(
                    label: '설정',
                    hint: '앱 설정을 열려면 탭하세요',
                    child: IconButton.filledTonal(
                      onPressed: () {
                        // 햅틱 피드백 추가
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
            Semantics(
              label: '메인 탭 메뉴',
              hint: '지도, 노선도, 홈, 알람, 즐겨찾기 탭을 선택할 수 있습니다',
              child: TabBar(
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
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                physics: const NeverScrollableScrollPhysics(), // 슬라이드 비활성화
                children: [
                  const MapScreen(),
                  _buildMapTab(),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Builder(
          builder: (context) {
            final alarms = Provider.of<AlarmService>(context).activeAlarms;
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
                  Align(
                    alignment: Alignment.centerLeft,
                    child: StationLoadingWidget(
                      onNearbyStopsLoaded: _onNearbyStopsLoaded,
                      onFavoriteStopsLoaded: _onFavoriteStopsLoaded,
                      onSelectedStopChanged: _onSelectedStopChanged,
                      selectedStop: _selectedStop,
                      favoriteStops: _favoriteStops,
                    ),
                  ),
                  _buildMainStationCard(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMapTab() {
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

  Widget _buildAutoAlarmChips(List<dynamic> alarms) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 4), // vertical 패딩 축소
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '자동 알람',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
              fontSize: 16, // 폰트 크기 축소
            ),
          ),
          const SizedBox(height: 4), // 간격 축소
          if (alarms.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4), // 패딩 축소
              child: Text('설정된 알람이 없습니다.',
                  style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 13)), // 폰트 크기 축소
            )
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
                      padding: const EdgeInsets.only(right: 6), // 간격 축소
                      child: ChoiceChip(
                        label: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬
                          mainAxisSize: MainAxisSize.min, // 최소 크기로 설정
                          children: [
                            Text(
                                '${alarm.routeNo}  ${alarm.hour.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')}',
                                style: TextStyle(
                                  color: isSelected
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12, // 폰트 크기 축소
                                )),
                            Text(alarm.stationName,
                                style: TextStyle(
                                  color: isSelected
                                      ? colorScheme.onPrimary
                                      : colorScheme.onSurface,
                                  fontSize: 11, // 폰트 크기 축소
                                )),
                            Text(
                              alarm.repeatDays
                                  .map((d) => [
                                        "월",
                                        "화",
                                        "수",
                                        "목",
                                        "금",
                                        "토",
                                        "일"
                                      ][d - 1])
                                  .join(","),
                              style: TextStyle(
                                color: isSelected
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurfaceVariant,
                                fontSize: 10, // 폰트 크기 축소
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
                            horizontal: 6, vertical: 2), // 패딩 축소
                        padding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 1), // 패딩 축소
                        showCheckmark: false, // 체크 아이콘 제거
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
        // 즐겨찾기에서 제거
        favorites.removeWhere((json) {
          final existing = BusStop.fromJson(jsonDecode(json));
          return existing.id == stop.id;
        });
        _favoriteStops.removeWhere((s) => s.id == stop.id);
        
        // 현재 선택된 정류장이 즐겨찾기에서 제거된 경우 UI 업데이트
        if (_selectedStop?.id == stop.id) {
          _selectedStop = stop.copyWith(isFavorite: false);
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${stop.name} 즐겨찾기에서 제거되었습니다')),
        );
      } else {
        // 즐겨찾기에 추가
        final favoriteStop = stop.copyWith(isFavorite: true);
        final stopJson = jsonEncode(favoriteStop.toJson());
        favorites.add(stopJson);
        _favoriteStops.add(favoriteStop);
        
        // 현재 선택된 정류장이 즐겨찾기에 추가된 경우 UI 업데이트
        if (_selectedStop?.id == stop.id) {
          _selectedStop = favoriteStop;
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${stop.name} 즐겨찾기에 추가되었습니다')),
        );
      }
    });
    
    await prefs.setStringList('favorites', favorites);
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
                children: _busArrivals.map((arrival) {
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
                  final stationName = _selectedStop?.name ?? '';
                  final stationId = _selectedStop?.stationId ?? _selectedStop?.id ?? '';

                  return InkWell(
                    onTap: () {
                      // 버스 클릭 시 상세 정보 모달 표시
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
