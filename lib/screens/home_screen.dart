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
import '../models/auto_alarm.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabTitles = ['지도', '노선도', '홈', '알람', '즐겨찾기'];
  final List<IconData> _tabIcons = [
    Icons.map,
    Icons.route,
    Icons.notifications,
    Icons.star
  ];
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
          if (_selectedStop != null) {
            _loadBusArrivals();
          } else {
            _busArrivals = [];
          }
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
        if (mounted) {
          setState(() {
            _busArrivals = cachedData;
            _isLoading = false;
            _errorMessage = null;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = true;
            _errorMessage = null;
          });
        }
      }
      _loadSelectedStationData(busStationId);
      _loadOtherStationsInBackground();
    } catch (e) {
      debugPrint('❌ 버스 도착 정보 로딩 오류: $e');
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
      body: SafeArea(
        child: Column(
          children: [
            // 1. 상단 검색창
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Focus(
                      onFocusChange: (hasFocus) => setState(() {}),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        height: 52,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(28),
                          border: FocusScope.of(context).hasFocus
                              ? Border.all(
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.8),
                                  width: 2,
                                )
                              : null,
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withValues(alpha: 0.05),
                              blurRadius:
                                  FocusScope.of(context).hasFocus ? 4 : 2,
                              offset: const Offset(0, 1),
                            ),
                            if (FocusScope.of(context).hasFocus)
                              BoxShadow(
                                color:
                                    colorScheme.primary.withValues(alpha: 0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                          ],
                        ),
                        child: Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(28),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(28),
                            splashColor: colorScheme.primary.withOpacity(0.08),
                            highlightColor:
                                colorScheme.primary.withOpacity(0.04),
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
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 14),
                              child: Row(
                                children: [
                                  AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 200),
                                    child: Icon(
                                      Icons.search_rounded,
                                      key: ValueKey(
                                          FocusScope.of(context).hasFocus),
                                      color: FocusScope.of(context).hasFocus
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      "정류장 검색",
                                      style:
                                          theme.textTheme.bodyLarge?.copyWith(
                                        color: colorScheme.onSurfaceVariant,
                                        fontSize: 16,
                                        fontWeight: FontWeight.normal,
                                        height: 1.2,
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
            // 2. 중간 탭바
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
            // 3. 탭별 내용
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // 지도 탭 (TODO: 지도 위젯 연동)
                  const Center(child: Text('지도 탭 (구현 필요)')),
                  // 노선도 탭
                  _buildRouteMapTab(),
                  // 홈 탭: 자동알람 하단에 주변정류장/즐겨찾기 버튼, 스크롤 가능
                  Column(
                    children: [
                      // 자동알람 패널(Chip 스타일로 통일)
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
                  ),
                  // 알람 탭
                  _buildAlarmTab(),
                  // 즐겨찾기 탭
                  _buildFavoritesTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNearbyTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 메인 정류장 카드 (선택된 정류장)
        _buildMainStationCard(),
        // 주변 정류장
        _buildStopSelectionList(
            '주변 정류장', _getFilteredNearbyStops(), _isLoadingNearby),
        // 즐겨찾는 정류장 (홈탭에서 주변정류장 하단에 표시)
        _buildStopSelectionList('즐겨찾는 정류장', _favoriteStops, false),
        // (선택) 기타 부가 정보/광고 등
      ],
    );
  }

  // 메인 정류장 카드: 선택된 정류장과 실시간 도착 정보, 주요 액션 포함
  Widget _buildMainStationCard() {
    if (_selectedStop == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedStop!.name,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurface),
                  ),
                ),
                IconButton(
                  icon: Icon(
                      _isStopFavorite(_selectedStop!)
                          ? Icons.star
                          : Icons.star_border,
                      color: colorScheme.primary),
                  onPressed: () => _toggleFavorite(_selectedStop!),
                  tooltip: _isStopFavorite(_selectedStop!)
                      ? '즐겨찾기에서 제거'
                      : '즐겨찾기에 추가',
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(),
            if (_isLoading)
              Center(
                  child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(color: colorScheme.primary),
              ))
            else if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_errorMessage!,
                            style: TextStyle(color: colorScheme.error))),
                  ],
                ),
              )
            else if (_busArrivals.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text('도착 예정 버스가 없습니다.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant)),
              )
            else ...[
              ..._busArrivals.map((arrival) => UnifiedBusDetailWidget(
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
                  )),
            ],
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

  Widget _buildStopSelectionList(
      String title, List<BusStop> stops, bool isLoading) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFavoriteList = title.contains('즐겨찾는');
    return Padding(
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
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('로딩 중...',
                  style: TextStyle(color: colorScheme.onSurfaceVariant)),
            )
          else if (stops.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                title.contains('즐겨찾는') ? '즐겨찾는 정류장이 없습니다.' : '주변 정류장이 없습니다.',
                style: TextStyle(
                    color: colorScheme.onSurfaceVariant, fontSize: 14),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                stops.map((s) => s.name).join(', '),
                style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
      ),
    );
  }

  // 주변 정류장/즐겨찾기 정류장 버튼 리스트
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
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
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
                final label = stop.name;
                return ChoiceChip(
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
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  // 자동알람 패널(Chip 스타일로 통일)
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
                alarm = alarm;
                final isSelected = _selectedStop?.name == alarm.stationName;
                final label =
                    '${alarm.routeNo}  ${alarm.hour.toString().padLeft(2, '0')}:${alarm.minute.toString().padLeft(2, '0')}\n${alarm.stationName}\n${alarm.repeatDays.map((d) => [
                          "월",
                          "화",
                          "수",
                          "목",
                          "금",
                          "토",
                          "일"
                        ][d - 1]).join(",")}';
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
                    // 해당 알람의 정류장으로 이동
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
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                );
              }).toList(),
            ),
        ],
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
