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
import 'package:daegu_bus_app/models/bus_info.dart';
import 'package:daegu_bus_app/services/alarm_manager.dart';
import 'package:daegu_bus_app/services/settings_service.dart';
import 'package:daegu_bus_app/utils/tts_switcher.dart';
import 'package:flutter/services.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 2;
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
    if (mounted) setState(() {});
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
      if (mounted) setState(() => _isLoadingNearby = false);
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
    if (_nearbyStops.isEmpty && _favoriteStops.isEmpty) return;
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
              if (mounted) setState(() => _stationArrivals[stop.id] = arrivals);
            }
          } catch (e) {
            debugPrint('${stop.id} 백그라운드 로딩 오류: $e');
            if (mounted)
              setState(() => _stationArrivals[stop.id] = <BusArrival>[]);
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
      body: CustomScrollView(
        slivers: [
          // Material 3 스타일 AppBar
          SliverAppBar.large(
            backgroundColor: colorScheme.surface,
            surfaceTintColor: colorScheme.surfaceTint,
            foregroundColor: colorScheme.onSurface,
            elevation: 0,
            pinned: true,
            expandedHeight: 180,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 16),
              title: Text(
                '대구버스',
                style: theme.textTheme.headlineLarge?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colorScheme.primary.withOpacity(0.05),
                      colorScheme.surface,
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              // Material 3 스타일 설정 버튼
              IconButton.filledTonal(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const SettingsScreen()),
                  );
                },
                icon: const Icon(Icons.settings_outlined),
                tooltip: '설정',
              ),
              const SizedBox(width: 8),
            ],
          ),

          // 검색 필드 (Material 3 스타일)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.2),
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
                              style: theme.textTheme.bodyMedium?.copyWith(
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
          ),

          // 활성 알람 패널
          Consumer<AlarmService>(
            builder: (context, alarmService, child) {
              return alarmService.alarms.isNotEmpty
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ActiveAlarmPanel(alarms: alarmService.alarms),
                      ),
                    )
                  : const SliverToBoxAdapter(child: SizedBox.shrink());
            },
          ),

          // 탭 선택기 (Material 3 스타일)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(4),
                child: Row(
                  children: [
                    Expanded(
                      child: Material(
                        color: _currentIndex == 0
                            ? colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          onTap: () => setState(() => _currentIndex = 0),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.favorite,
                                  size: 18,
                                  color: _currentIndex == 0
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '즐겨찾기',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: _currentIndex == 0
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Material(
                        color: _currentIndex == 1
                            ? colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          onTap: () => setState(() => _currentIndex = 1),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.location_on,
                                  size: 18,
                                  color: _currentIndex == 1
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '주변정류장',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: _currentIndex == 1
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Material(
                        color: _currentIndex == 2
                            ? colorScheme.primaryContainer
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        child: InkWell(
                          onTap: () => setState(() => _currentIndex = 2),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.directions_bus,
                                  size: 18,
                                  color: _currentIndex == 2
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '실시간 도착',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: _currentIndex == 2
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 내용
          if (_isLoading)
            SliverFillRemaining(
              child: Center(
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
              ),
            )
          else if (_errorMessage != null)
            SliverFillRemaining(
              child: Center(
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
              ),
            )
          else
            ..._buildTabContent(),
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
      case 0:
        return Container(
            color: colorScheme.surface, child: _buildRouteMapTab());
      case 1:
        return Container(
            color: colorScheme.surface, child: _buildFavoritesTab());
      case 2:
        return Container(color: colorScheme.surface, child: _buildNearbyTab());
      case 3:
        return Container(color: colorScheme.surface, child: _buildAlarmTab());
      case 4:
        return Container(
            color: colorScheme.surface, child: _buildSettingsTab());
      default:
        return Container(color: colorScheme.surface, child: _buildNearbyTab());
    }
  }

  Widget _buildSettingsTab() {
    return const SafeArea(top: true, bottom: false, child: SettingsScreen());
  }

  Widget _buildNearbyTab() {
    return SafeArea(
      top: false,
      bottom: false,
      child: RefreshIndicator(
        onRefresh: _initializeData,
        child: CustomScrollView(
          slivers: [
            const SliverToBoxAdapter(child: ActiveAlarmPanel()),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: Colors.grey[100],
                  ),
                  child: TextField(
                    readOnly: true,
                    onTap: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (context) => SearchScreen(
                                  favoriteStops: _favoriteStops,
                                )),
                      );
                      if (result != null) {
                        if (result is BusStop) {
                          setState(() => _selectedStop = result);
                          _loadBusArrivals();
                        } else if (result is List<BusStop>) {
                          setState(() {
                            _favoriteStops.clear();
                            _favoriteStops.addAll(result);
                          });
                        }
                      }
                      await _loadFavoriteStops();
                    },
                    decoration: InputDecoration(
                      hintText: '정류장 이름 또는 번호 검색 (예: 동대구역, 2001)',
                      prefixIcon: Icon(Icons.search, color: Colors.blue[700]),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 16),
                    ),
                  ),
                ),
              ),
            ),
            _buildStopSelectionList('주변 정류장', _nearbyStops, _isLoadingNearby),
            _buildStopSelectionList('즐겨찾는 정류장', _favoriteStops, false),
            if (_selectedStop != null)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.symmetric(
                      vertical: 8.0, horizontal: 16.0),
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.grey.withOpacity(0.1), blurRadius: 4),
                    ],
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _isStopFavorite(_selectedStop!)
                              ? Icons.star
                              : Icons.star_border,
                          color: _isStopFavorite(_selectedStop!)
                              ? Colors.amber
                              : Colors.grey,
                          size: 24,
                        ),
                        onPressed: () => _toggleFavorite(_selectedStop!),
                        tooltip: _isStopFavorite(_selectedStop!)
                            ? '즐겨찾기 제거'
                            : '즐겨찾기 추가',
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedStop!.name,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
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
                        _selectedStop!.id,
                        _selectedStop!.name,
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

  Widget _buildBusDetailCard(BusInfo busInfo, {required bool isFirst}) {
    final remainingMinutes = busInfo.getRemainingMinutes();
    String arrivalTimeText;
    Color arrivalTextColor;

    if (busInfo.isOutOfService) {
      arrivalTimeText = '운행종료';
      arrivalTextColor = Colors.grey;
    } else if (remainingMinutes <= 0) {
      arrivalTimeText = '곧 도착';
      arrivalTextColor = Colors.red;
    } else {
      arrivalTimeText = '$remainingMinutes분';
      arrivalTextColor = remainingMinutes <= 3
          ? Colors.red
          : (Colors.blue[600] ?? Colors.blue);
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isFirst ? Colors.blue.shade200 : Colors.grey.shade200,
          width: isFirst ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 버스 타입 표시
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        isFirst ? Colors.blue.shade100 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isFirst ? '이번 버스' : '다음 버스',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color:
                          isFirst ? Colors.blue.shade700 : Colors.grey.shade700,
                    ),
                  ),
                ),
                const Spacer(),
                if (busInfo.isLowFloor)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '저상',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // 메인 정보
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '현재 위치',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        busInfo.currentStation,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        busInfo.remainingStops,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // 도착 시간
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '도착 예정',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      arrivalTimeText,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: arrivalTextColor,
                      ),
                    ),
                    if (!busInfo.isOutOfService && remainingMinutes > 0)
                      Text(
                        busInfo.estimatedTime,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactBusInfo(BusInfo busInfo) {
    final remainingMinutes = busInfo.getRemainingMinutes();
    String arrivalTimeText;
    Color arrivalTextColor;

    if (busInfo.isOutOfService) {
      arrivalTimeText = '운행종료';
      arrivalTextColor = Colors.grey;
    } else if (remainingMinutes <= 0) {
      arrivalTimeText = '곧 도착';
      arrivalTextColor = Colors.red;
    } else {
      arrivalTimeText = '$remainingMinutes분';
      arrivalTextColor =
          remainingMinutes <= 3 ? Colors.red : Colors.blue.shade600;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  busInfo.currentStation,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  busInfo.remainingStops,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                arrivalTimeText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: arrivalTextColor,
                ),
              ),
              if (busInfo.isLowFloor)
                Container(
                  margin: const EdgeInsets.only(top: 2),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.green.shade100,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '저상',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showBusDetailModal(BusArrival busArrival) {
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    final hasActiveAlarm = _selectedStop != null &&
        alarmService.hasAlarm(
            busArrival.routeNo, _selectedStop!.name, busArrival.routeId);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (modalContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.5,
              minChildSize: 0.5,
              maxChildSize: 0.85,
              expand: false,
              builder: (context, scrollController) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      // 드래그 핸들
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        height: 4,
                        width: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // 헤더 정보
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${busArrival.routeNo}번 버스',
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (_selectedStop != null)
                                  Text(
                                    '${_selectedStop!.name} → ${busArrival.direction}',
                                    style: TextStyle(
                                        fontSize: 14, color: Colors.grey[800]),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(modalContext),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: EdgeInsets.zero,
                          children: [
                            // 첫 번째 버스 카드
                            if (busArrival.busInfoList.isNotEmpty)
                              _buildDetailedBusCard(
                                  busArrival.busInfoList.first,
                                  busArrival.routeNo,
                                  isFirst: true),
                            // 다음 버스 정보 안내 (다음 버스가 있는 경우만)
                            if (busArrival.busInfoList.length > 1) ...[
                              const SizedBox(height: 12),
                              const Text(
                                '다음 버스 정보',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              ...busArrival.busInfoList.skip(1).map(
                                    (bus) => _buildDetailedBusCard(
                                        bus, busArrival.routeNo,
                                        isFirst: false),
                                  ),
                            ],
                            const SizedBox(height: 20),
                          ],
                        ),
                      ),
                      // 하단 버튼 영역
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              Navigator.pop(modalContext); // 모달 닫기
                              await _handleBoardingAlarm(
                                  busArrival, modalContext);
                            },
                            icon: Icon(
                              hasActiveAlarm
                                  ? Icons.notifications_off
                                  : Icons.notifications_active,
                            ),
                            label: Text(
                              hasActiveAlarm ? '승차 알람 해제' : '승차 알람 설정',
                            ),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor:
                                  hasActiveAlarm ? Colors.red[100] : null,
                              foregroundColor:
                                  hasActiveAlarm ? Colors.red[700] : null,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildDetailedBusCard(dynamic busInfo, String routeNo,
      {required bool isFirst}) {
    final remainingMinutes = busInfo.getRemainingMinutes();
    String arrivalTimeText;
    Color arrivalTextColor;

    if (busInfo.isOutOfService) {
      arrivalTimeText = '운행종료';
      arrivalTextColor = Colors.grey;
    } else if (remainingMinutes <= 0) {
      arrivalTimeText = '곧 도착';
      arrivalTextColor = Colors.red;
    } else {
      arrivalTimeText = '$remainingMinutes분';
      arrivalTextColor = remainingMinutes <= 3
          ? Colors.red
          : (Colors.blue[600] ?? Colors.blue);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isFirst ? 2 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isFirst ? Colors.blue[200]! : Colors.grey[200]!,
          width: isFirst ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 버스 번호와 상태 표시
            Row(
              children: [
                Text(
                  routeNo,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isFirst ? Colors.blue[700] : Colors.grey[700],
                  ),
                ),
                const SizedBox(width: 8),
                if (busInfo.isLowFloor)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '저상',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.green[700],
                      ),
                    ),
                  ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isFirst ? Colors.blue[50] : Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isFirst ? '이번 버스' : '다음 버스',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isFirst ? Colors.blue[700] : Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // 메인 정보
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '현재 위치',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        busInfo.currentStation,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        busInfo.remainingStops,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                // 도착 시간
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '도착예정',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      arrivalTimeText,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: arrivalTextColor,
                      ),
                    ),
                    if (!busInfo.isOutOfService && remainingMinutes > 0)
                      Text(
                        busInfo.estimatedTime,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusDetailRow(BusInfo busInfo, {required bool isFirst}) {
    final remainingMinutes = busInfo.getRemainingMinutes();
    String arrivalTimeText;
    Color arrivalTextColor;
    if (busInfo.isOutOfService) {
      arrivalTimeText = '운행종료';
      arrivalTextColor = Colors.grey;
    } else if (remainingMinutes <= 0) {
      arrivalTimeText = '곧 도착';
      arrivalTextColor = Colors.red;
    } else {
      arrivalTimeText = '$remainingMinutes분';
      arrivalTextColor =
          remainingMinutes <= 3 ? Colors.red : Theme.of(context).primaryColor;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(isFirst ? '이번 버스' : '다음 버스',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey[600])),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(busInfo.currentStation,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(busInfo.remainingStops,
                      style: TextStyle(fontSize: 13, color: Colors.grey[700])),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text(arrivalTimeText,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: arrivalTextColor)),
          ],
        ),
      ],
    );
  }

  void _setupPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = _selectedStop != null
        ? Timer.periodic(
            const Duration(seconds: 30), (timer) => _loadBusArrivals())
        : null;
  }

  Future<void> _startNativeTracking(
      String busNo, String stationName, String routeId) async {
    try {
      const platform = MethodChannel('com.example.daegu_bus_app/notification');
      await platform.invokeMethod('startBusTrackingService', {
        'busNo': busNo,
        'stationName': stationName,
        'routeId': routeId,
      });
      log('🔔 ✅ 네이티브 추적 시작 요청 완료');
    } catch (e) {
      log('❌ [ERROR] 네이티브 추적 시작 실패: $e');
      rethrow;
    }
  }

  Future<void> _stopSpecificNativeTracking(
      String busNo, String stationName, String routeId) async {
    try {
      const platform = MethodChannel('com.example.daegu_bus_app/notification');
      await platform.invokeMethod('stopSpecificTracking', {
        'busNo': busNo,
        'routeId': routeId,
        'stationName': stationName,
      });
      log('🔔 ✅ 네이티브 특정 추적 중지 요청 완료');
    } catch (e) {
      log('❌ [ERROR] 네이티브 특정 추적 중지 실패: $e');
    }
  }

  Future<void> _handleBoardingAlarm(
      BusArrival busArrival, BuildContext modalContext) async {
    if (_selectedStop == null || busArrival.busInfoList.isEmpty) return;
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    final firstBus = busArrival.busInfoList.first;
    final routeId = busArrival.routeId;
    final stationId = _selectedStop!.id;
    final wincId = _selectedStop!.wincId ?? '';
    final busNo = busArrival.routeNo;
    final stationName = _selectedStop!.name;
    final remainingMinutes = firstBus.getRemainingMinutes();
    final hasAlarm = alarmService.hasAlarm(busNo, stationName, routeId);
    Navigator.pop(modalContext);
    try {
      if (hasAlarm) {
        await _stopSpecificNativeTracking(busNo, stationName, routeId);
        await AlarmManager.cancelAlarm(
            busNo: busNo, stationName: stationName, routeId: routeId);
        await alarmService.cancelAlarmByRoute(busNo, stationName, routeId);
        await TtsSwitcher.stopTtsTracking(busNo);
        await alarmService.refreshAlarms();
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('승차 알람이 취소되었습니다.')));
      } else {
        if (remainingMinutes <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('이미 도착했거나 운행이 종료된 버스입니다.')));
          return;
        }
        for (var alarm in [...alarmService.activeAlarms]) {
          if (alarm.stationName == stationName) {
            await alarmService.cancelAlarmByRoute(
                alarm.busNo, alarm.stationName, alarm.routeId);
            await TtsSwitcher.stopTtsTracking(alarm.busNo);
          }
        }
        await AlarmManager.addAlarm(
            busNo: busNo,
            stationName: stationName,
            routeId: routeId,
            wincId: wincId);
        await _startNativeTracking(busNo, stationName, routeId);
        bool success = await alarmService.setOneTimeAlarm(
          busNo,
          stationName,
          remainingMinutes,
          routeId: routeId,
          useTTS: true,
          isImmediateAlarm: true,
          currentStation: firstBus.currentStation,
        );
        if (success) {
          await alarmService.startBusMonitoringService(
              stationId: stationId,
              stationName: stationName,
              routeId: routeId,
              busNo: busNo);
          final settings = Provider.of<SettingsService>(context, listen: false);
          if (settings.useTts) {
            TtsSwitcher.startTtsTracking(
                routeId: routeId,
                stationId: stationId,
                busNo: busNo,
                stationName: stationName,
                remainingMinutes: remainingMinutes);
          }
          await alarmService.refreshAlarms();
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('승차 알람이 설정되었습니다.')));
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('승차 알람 설정에 실패했습니다.')));
        }
      }
    } catch (e) {
      log('알람 처리 중 오류: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('알람 처리 중 오류가 발생했습니다: $e')));
    }
  }

  int _getBottomNavIndex() {
    switch (_currentIndex) {
      case 0:
        return 0;
      case 1:
        return 1;
      case 2:
        return 2;
      case 3:
        return 3;
      case 4:
        return 4;
      default:
        return 2;
    }
  }

  void _navigateToScreen(int index) {
    setState(() => _currentIndex = index);
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
          borderRadius: BorderRadius.circular(10), // 둥근 모서리 축소
          side: BorderSide(
              color: isSelected ? Colors.blue.shade300 : Colors.grey.shade200,
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
                    fontSize: 14, // 폰트 크기 축소 (16->14)
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.blue.shade700 : Colors.black87,
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
                          color: Colors.grey[600], fontSize: 11), // 폰트 크기 축소
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
