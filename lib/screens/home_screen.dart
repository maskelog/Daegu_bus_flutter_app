import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:daegu_bus_app/screens/alarm_screen.dart';
import 'package:daegu_bus_app/screens/route_map_screen.dart';
import 'package:daegu_bus_app/widgets/unified_bus_detail_widget.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../widgets/active_alarm_panel.dart';
import 'search_screen.dart';
import 'favorites_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../services/alarm_service.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _isLoadingNearby = false;
  String? _errorMessage;
  Timer? _refreshTimer;
  Timer? _smartRefreshTimer;
  final List<BusStop> _favoriteStops = [];
  List<BusStop> _nearbyStops = [];
  BusStop? _selectedStop;
  List<BusArrival> _busArrivals = [];
  final Map<String, List<BusArrival>> _stationArrivals = {};

  @override
  void initState() {
    super.initState();
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    alarmService.initialize();
    alarmService.addListener(_onAlarmChanged);
    _initializeData();
  }

  @override
  void dispose() {
    Provider.of<AlarmService>(context, listen: false)
        .removeListener(_onAlarmChanged);
    _searchController.dispose();
    _refreshTimer?.cancel();
    _smartRefreshTimer?.cancel();
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
      setState(() {
        _isLoading = false;
        _isLoadingNearby = false;
      });
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
          debugPrint('Loaded favorite stop: ${stop.id}, ${stop.name}');
        }
        if (_favoriteStops.isNotEmpty && _selectedStop == null) {
          _selectedStop = _favoriteStops.first;
          debugPrint(
              'Selected stop: ${_selectedStop!.id}, ${_selectedStop!.name}');
        }
      });
    } catch (e) {
      debugPrint('Error loading favorites: $e');
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
      log('📍 Location permission status: $status');
      if (!status.isGranted) {
        final requestedStatus = await Permission.location.request();
        log('📍 Location permission request result: $requestedStatus');
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
        log('📍 Location services disabled.');
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
      log('📍 Permissions granted and services enabled. Fetching nearby stations...');
      if (!mounted) return;
      final nearbyStations =
          await LocationService.getNearbyStations(500, context: context);
      log('📍 Found ${nearbyStations.length} nearby stations.');
      if (!mounted) return;
      setState(() {
        _nearbyStops = nearbyStations;
        if (_nearbyStops.isNotEmpty && _selectedStop == null) {
          _selectedStop = _nearbyStops.first;
          _loadBusArrivals();
        }
      });
    } catch (e, stackTrace) {
      log('❌ Error loading nearby stations: $e\n$stackTrace');
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
      debugPrint('홈화면 즐겨찾기 저장 완료: ${_favoriteStops.length}개 정류장');
    } catch (e) {
      debugPrint('Error saving favorites: $e');
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
          if (_selectedStop != null)
            _loadBusArrivals();
          else
            _busArrivals = [];
        }
        debugPrint('홈화면에서 즐겨찾기 제거: ${stop.name}');
      } else {
        _favoriteStops.add(stop.copyWith(isFavorite: true));
        debugPrint('홈화면에서 즐겨찾기 추가: ${stop.name}');
      }
    });

    // 즐겨찾기 저장
    _saveFavoriteStops();

    // 사용자 피드백
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
    if (_nearbyStops.isEmpty && _favoriteStops.isEmpty) {
      return;
    }
    if (_selectedStop == null) {
      debugPrint('❌ 선택된 정류장이 없음');
      return;
    }
    final String busStationId = _selectedStop!.stationId ?? _selectedStop!.id;
    debugPrint(
        '📌 선택된 정류장: ${_selectedStop!.name} (id: ${_selectedStop!.id}, stationId: $busStationId)');
    try {
      final cachedData = _stationArrivals[_selectedStop!.id];
      if (cachedData != null && cachedData.isNotEmpty) {
        debugPrint('⚡ 캐시된 데이터 즉시 표시: ${cachedData.length}개 버스');
        if (mounted)
          setState(() {
            _busArrivals = cachedData;
            _isLoading = false;
            _errorMessage = null;
          });
      } else {
        if (mounted)
          setState(() {
            _isLoading = true;
            _errorMessage = null;
          });
      }
      _loadSelectedStationData(busStationId);
      _loadOtherStationsInBackground();
    } catch (e) {
      debugPrint('❌ 버스 도착 정보 로딩 오류: $e');
      if (mounted)
        setState(() {
          _isLoading = false;
          _errorMessage = '버스 도착 정보를 불러오지 못했습니다: $e';
        });
    }
  }

  Future<void> _loadSelectedStationData(String busStationId) async {
    try {
      debugPrint('🚌 선택된 정류장의 최신 정보 로드 중: $busStationId');
      final stopArrivals = await ApiService.getStationInfo(busStationId);
      debugPrint('✅ 최신 정보 로드 완료: ${stopArrivals.length}개 버스 발견');
      if (mounted && _selectedStop != null) {
        setState(() {
          _stationArrivals[_selectedStop!.id] = stopArrivals;
          _busArrivals = stopArrivals;
          _isLoading = false;
          debugPrint('🔄 UI 업데이트: ${_busArrivals.length}개 버스 도착 정보 설정');
        });
      }
    } catch (e) {
      debugPrint('❌ 선택된 정류장 데이터 로딩 오류: $e');
      if (mounted)
        setState(() {
          _isLoading = false;
          _errorMessage = '버스 도착 정보를 불러오지 못했습니다: $e';
        });
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
            debugPrint('${stop.id} 백그라운드 로딩 오류: $e');
            if (mounted) {
              setState(() => _stationArrivals[stop.id] = <BusArrival>[]);
            }
          }
        }));
        await Future.delayed(const Duration(milliseconds: 50));
      }
      if (mounted && _selectedStop != null) {
        debugPrint('📊 최종 버스 도착 정보: ${_busArrivals.length}개');
        debugPrint('📋 전체 정류장 캐시: ${_stationArrivals.keys.length}개 정류장');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          // 검색 필드와 설정 버튼을 같은 줄에 배치 - 홈 탭에서만 표시
          if (_currentIndex == 0)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // 검색 필드
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color:
                              colorScheme.surfaceContainerHighest.withAlpha(40),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.outline.withAlpha(20),
                            width: 1,
                          ),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SearchScreen(
                                    favoriteStops: _favoriteStops,
                                  ),
                                ),
                              );
                              if (result != null) {
                                if (result is BusStop) {
                                  setState(() => _selectedStop = result);
                                  _loadBusArrivals();
                                }
                              }
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 16),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.search,
                                    color: colorScheme.primary,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      "정류장 이름 또는 번호 검색 (예: 동대구역, 2001)",
                                      style:
                                          theme.textTheme.bodyMedium?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                      ),
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
                    // 설정 버튼
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
            ),

          // 활성 알람 패널 - 홈 탭에서만 표시
          if (_currentIndex == 0)
            Consumer<AlarmService>(
              builder: (context, alarmService, child) {
                return alarmService.activeAlarms.isNotEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: ActiveAlarmPanel(),
                      )
                    : const SizedBox.shrink();
              },
            ),

          // 내용
          Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: colorScheme.primary),
                        const SizedBox(height: 16),
                        Text(
                          '데이터를 불러오는 중...',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.error_outline,
                              size: 64,
                              color: colorScheme.error,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _errorMessage!,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colorScheme.onSurface,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.tonal(
                              onPressed: _initializeData,
                              child: const Text('다시 시도'),
                            ),
                          ],
                        ),
                      )
                    : _buildTabContent(),
          ),
        ],
      ),
      // Material 3 스타일 NavigationBar
      bottomNavigationBar: NavigationBar(
        selectedIndex: _getBottomNavIndex(),
        onDestinationSelected: (index) => _navigateToScreen(index),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surfaceTint,
        indicatorColor: colorScheme.secondaryContainer,
        destinations: [
          NavigationDestination(
            icon:
                Icon(Icons.home_outlined, color: colorScheme.onSurfaceVariant),
            selectedIcon:
                Icon(Icons.home, color: colorScheme.onSecondaryContainer),
            label: '홈',
          ),
          NavigationDestination(
            icon:
                Icon(Icons.route_outlined, color: colorScheme.onSurfaceVariant),
            selectedIcon:
                Icon(Icons.route, color: colorScheme.onSecondaryContainer),
            label: '노선도',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined,
                color: colorScheme.onSurfaceVariant),
            selectedIcon: Icon(Icons.notifications,
                color: colorScheme.onSecondaryContainer),
            label: '알람',
          ),
          NavigationDestination(
            icon: Icon(Icons.star_border, color: colorScheme.onSurfaceVariant),
            selectedIcon:
                Icon(Icons.star, color: colorScheme.onSecondaryContainer),
            label: '즐겨찾기',
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    final colorScheme = Theme.of(context).colorScheme;
    switch (_currentIndex) {
      case 0: // 홈 탭 - 즐겨찾기와 주변정류장 실시간 도착 정보 표시
        return Container(color: colorScheme.surface, child: _buildNearbyTab());
      case 1: // 노선도 탭
        return Container(
            color: colorScheme.surface, child: _buildRouteMapTab());
      case 2: // 알람 탭
        return Container(color: colorScheme.surface, child: _buildAlarmTab());
      case 3: // 즐겨찾기 탭
        return Container(
            color: colorScheme.surface, child: _buildFavoritesTab());
      default:
        return Container(color: colorScheme.surface, child: _buildNearbyTab());
    }
  }

  Widget _buildNearbyTab() {
    return SafeArea(
      top: false,
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _initializeData,
        child: CustomScrollView(
          slivers: [
            _buildStopSelectionList('즐겨찾는 정류장', _favoriteStops, false),
            _buildStopSelectionList(
                '주변 정류장', _getFilteredNearbyStops(), _isLoadingNearby),
            if (_busArrivals.isNotEmpty && _selectedStop != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_selectedStop!.name} 실시간 도착 정보',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black87,
                                ),
                      ),
                      IconButton(
                        onPressed: () => _toggleFavorite(_selectedStop!),
                        icon: Icon(
                          _isStopFavorite(_selectedStop!)
                              ? Icons.star
                              : Icons.star_border,
                          color: _isStopFavorite(_selectedStop!)
                              ? Colors.amber
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        tooltip: _isStopFavorite(_selectedStop!)
                            ? '즐겨찾기에서 제거'
                            : '즐겨찾기에 추가',
                      ),
                    ],
                  ),
                ),
              ),
            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_errorMessage != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      title: Text(_errorMessage!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 16)),
                      leading: const Icon(Icons.error, color: Colors.red),
                    ),
                  ),
                ),
              )
            else if (_busArrivals.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Center(
                      child: Text('도착 예정 버스가 없습니다.',
                          style: TextStyle(fontSize: 16))),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final arrival = _busArrivals[index];
                    return UnifiedBusDetailWidget(
                      busArrival: arrival,
                      stationId: _selectedStop!.id,
                      stationName: _selectedStop!.name,
                      isCompact: true,
                      onTap: () => showUnifiedBusDetailModal(
                        context,
                        arrival,
                        _selectedStop?.stationId ?? _selectedStop?.id ?? '',
                        _selectedStop?.name ?? '',
                      ),
                    );
                  },
                  childCount: _busArrivals.length,
                ),
              ),
            const SliverPadding(
              padding: EdgeInsets.only(bottom: 20),
            ),
          ],
        ),
      ),
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
          // 더 이상 홈 탭으로 이동하지 않고 즐겨찾기 화면에서 바로 처리
          // 이 주석을 남겨두어 나중에 필요하면 다시 활성화 가능
          /*
          setState(() {
            _currentIndex = 2; // 홈 탭으로 이동
            _selectedStop = stop;
          });
          _loadBusArrivals();
          */
        },
        onFavoriteToggle: _toggleFavorite,
      ),
    );
  }

  Widget _buildAlarmTab() {
    return const AlarmScreen();
  }

  String _formatDistance(double? distance) {
    if (distance == null) return '';
    return distance < 1000
        ? '${distance.round()}m'
        : '${(distance / 1000).toStringAsFixed(1)}km';
  }

  void _setupPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = _selectedStop != null
        ? Timer.periodic(
            const Duration(seconds: 30), (timer) => _loadBusArrivals())
        : null;
  }

  int _getBottomNavIndex() {
    switch (_currentIndex) {
      case 0: // 홈
        return 0;
      case 1: // 노선도
        return 1;
      case 2: // 알람
        return 2;
      case 3: // 즐겨찾기
        return 3;
      default:
        return 0;
    }
  }

  void _navigateToScreen(int index) {
    setState(() => _currentIndex = index);
  }

  Widget _buildStopSelectionList(
      String title, List<BusStop> stops, bool isLoading) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFavoriteList = title.contains('즐겨찾는');

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                    fontSize: 18,
                  ),
            ),
            const SizedBox(height: 8),
            if (isLoading)
              Container(
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: colorScheme.surfaceContainerHighest.withAlpha(30),
                ),
                child: const Center(child: CircularProgressIndicator()),
              )
            else if (stops.isEmpty)
              Container(
                height: 80,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: colorScheme.surfaceContainerHighest.withAlpha(30),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        title.contains('즐겨찾는')
                            ? Icons.star_border
                            : Icons.location_off,
                        color: colorScheme.onSurfaceVariant,
                        size: 24,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        title.contains('즐겨찾는')
                            ? '즐겨찾는 정류장이 없습니다.\n정류장을 선택하고 별표를 눌러 추가하세요.'
                            : '주변 정류장을 찾을 수 없습니다.\n위치 권한을 확인해주세요.',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 90,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: stops.length,
                  itemBuilder: (context, index) {
                    final stop = stops[index];
                    return Container(
                      width: 160,
                      margin: const EdgeInsets.only(right: 8),
                      child: Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: InkWell(
                          onTap: () {
                            setState(() => _selectedStop = stop);
                            _loadBusArrivals();
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      size: 14,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        stop.name,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: Theme.of(context)
                                                          .brightness ==
                                                      Brightness.dark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                if (!isFavoriteList) ...[
                                  if (stop.distance != null) ...[
                                    Text(
                                      _formatDistance(stop.distance),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color:
                                                Theme.of(context).brightness ==
                                                        Brightness.dark
                                                    ? Colors.white70
                                                    : Colors.black54,
                                            fontSize: 11,
                                          ),
                                    ),
                                  ],
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<BusStop> _getFilteredNearbyStops() {
    // 즐겨찾기에 있는 정류장 ID들을 Set으로 만들어 빠른 검색
    final favoriteStopIds = _favoriteStops.map((stop) => stop.id).toSet();

    // 주변 정류장에서 즐겨찾기에 있는 정류장들을 제외
    return _nearbyStops
        .where((stop) => !favoriteStopIds.contains(stop.id))
        .toList();
  }
}

class StopCard extends StatelessWidget {
  final BusStop stop;
  final bool isSelected;
  final VoidCallback onTap;
  final bool showDistance;
  final String? distanceText;

  const StopCard({
    super.key,
    required this.stop,
    required this.isSelected,
    required this.onTap,
    this.showDistance = false,
    this.distanceText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150, // 너비를 170에서 150으로 축소
      margin: const EdgeInsets.only(right: 8), // 마진도 줄임
      child: Card(
        elevation: 1, // elevation 축소
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline.withAlpha(50),
              width: isSelected ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(8.0), // 패딩 축소 (10->8)
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  stop.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (showDistance &&
                    distanceText != null &&
                    distanceText!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0), // 패딩 축소
                    child: Text(
                      distanceText!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 11),
                    ),
                  ),
                const SizedBox(height: 2), // 높이 축소
              ],
            ),
          ),
        ),
      ),
    );
  }
}
