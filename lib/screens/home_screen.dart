import 'dart:async';
import 'dart:convert';
import 'package:daegu_bus_app/screens/profile_screen.dart';
import 'package:daegu_bus_app/screens/reoute_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/alarm_service.dart';
import '../widgets/active_alarm_panel.dart';
import '../widgets/bus_card.dart';
import '../widgets/compact_bus_card.dart';
import 'search_screen.dart';
import 'favorites_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  final List<BusStop> _favoriteStops = [];
  List<BusStop> _nearbyStops = [];
  BusStop? _selectedStop;
  List<BusArrival> _busArrivals = [];
  bool _isLoading = false;
  bool _isLoadingNearby = false;
  String? _errorMessage;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadFavoriteStops();
    _loadNearbyStations();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      if (mounted && _selectedStop != null) {
        _loadBusArrivals();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

// 주변 정류장 로드 (500m 이내)
  Future<void> _loadNearbyStations() async {
    setState(() => _isLoadingNearby = true);
    try {
      // 500미터로 변경 (1000에서 500으로 수정)
      final nearbyStations =
          await LocationService.getNearbyStations(500, context: context);
      if (!mounted) return;
      setState(() {
        _nearbyStops = nearbyStations;
        _isLoadingNearby = false;
        if (_nearbyStops.isNotEmpty && _selectedStop == null) {
          _selectedStop = _nearbyStops.first;
          _loadBusArrivals();
        }
      });
    } catch (e) {
      debugPrint('Error loading nearby stations: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingNearby = false;
        _errorMessage = '주변 정류장을 불러오는 중 오류가 발생했습니다: $e';
      });
    }
  }

  // 즐겨찾기 불러오기
  Future<void> _loadFavoriteStops() async {
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList('favorites') ?? [];
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
        _loadBusArrivals();
      }
    } catch (e) {
      debugPrint('Error loading favorites: $e');
      setState(() {
        _errorMessage = '즐겨찾기를 불러오는 중 오류가 발생했습니다.';
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 즐겨찾기 저장
  Future<void> _saveFavoriteStops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> favorites =
          _favoriteStops.map((stop) => jsonEncode(stop.toJson())).toList();
      await prefs.setStringList('favorites', favorites);
    } catch (e) {
      debugPrint('Error saving favorites: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('즐겨찾기 저장에 실패했습니다')),
      );
    }
  }

  // 즐겨찾기 추가/제거
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
      _saveFavoriteStops();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isStopFavorite(stop)
              ? '${stop.name} 정류장이 즐겨찾기에 추가되었습니다'
              : '${stop.name} 정류장이 즐겨찾기에서 제거되었습니다',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  bool _isStopFavorite(BusStop stop) {
    return _favoriteStops.any((s) => s.id == stop.id);
  }

  // 버스 도착 정보 로드
  Future<void> _loadBusArrivals() async {
    if (_selectedStop == null) return;

    debugPrint(
        'Loading bus arrivals for station: ${_selectedStop!.id}, ${_selectedStop!.name}');

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final arrivalsData =
          await ApiService.getStationInfo(_selectedStop!.id); // bsId 사용
      debugPrint('Bus arrivals loaded: ${arrivalsData.length} routes');

      if (!mounted) return;

      setState(() {
        _busArrivals = arrivalsData;
      });

      _updateAlarmServiceCache();
    } catch (e) {
      debugPrint('Error loading arrivals: $e');
      setState(() {
        _errorMessage = '버스 도착 정보를 불러오지 못했습니다: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('버스 도착 정보를 불러오지 못했습니다: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // AlarmService 캐시 업데이트 메소드
  void _updateAlarmServiceCache() {
    if (_busArrivals.isEmpty || !mounted) return;

    final alarmService = Provider.of<AlarmService>(context, listen: false);
    final Set<String> updatedBuses = {};

    for (var busArrival in _busArrivals) {
      if (busArrival.buses.isNotEmpty) {
        final firstBus = busArrival.buses.first;
        final remainingTime = firstBus.getRemainingMinutes();
        final busKey = "${busArrival.routeNo}:${busArrival.routeId}";
        if (updatedBuses.contains(busKey)) continue;
        updatedBuses.add(busKey);
        alarmService.updateBusInfoCache(
            busArrival.routeNo, busArrival.routeId, firstBus, remainingTime);
        debugPrint(
            '홈스크린에서 캐시 업데이트: ${busArrival.routeNo}, 남은 시간: $remainingTime분');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: Column(
        children: [
          const ActiveAlarmPanel(),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    String title = '';
    switch (_currentIndex) {
      case 0:
        title = '주변 정류장';
        break;
      case 1:
        title = '노선도';
        break;
      case 2:
        title = '즐겨찾는 정류장';
        break;
      case 3:
        title = '내정보';
        break;
    }
    return AppBar(
      title: Text(title),
      actions: [
        if (_currentIndex == 0)
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadNearbyStations();
              if (_selectedStop != null) {
                await _loadBusArrivals();
              }
            },
          ),
        if (_currentIndex == 2)
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () async {
              await _loadFavoriteStops();
            },
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_currentIndex == 0) return _buildNearbyTab();
    if (_currentIndex == 1) return _buildRouteMapTab();
    if (_currentIndex == 2) return _buildFavoritesTab();
    return _buildProfileTab();
  }

  Widget _buildNearbyTab() {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16.0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  color: Colors.grey[100],
                ),
                child: TextField(
                  controller: _searchController,
                  readOnly: true,
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
                        setState(() {
                          _selectedStop = result;
                          if (result.isFavorite && !_isStopFavorite(result)) {
                            _favoriteStops.add(result);
                            _saveFavoriteStops();
                          }
                          _loadBusArrivals();
                        });
                      } else if (result is List) {
                        setState(() {
                          _favoriteStops.clear();
                          for (var stop in result) {
                            if (stop is BusStop) {
                              _favoriteStops.add(stop);
                            }
                          }
                          _saveFavoriteStops();
                        });
                      }
                    }
                  },
                  decoration: InputDecoration(
                    hintText: '정류장을 검색하세요',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      vertical: 16,
                      horizontal: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ]),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '주변 정류장',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                if (_isLoadingNearby)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.only(top: 12, bottom: 20),
          sliver: _isLoadingNearby
              ? SliverToBoxAdapter(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 16),
                          Text(
                            '주변 정류장을 로딩 중입니다...',
                            style: TextStyle(
                                fontSize: 14, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : _nearbyStops.isEmpty
                  ? SliverToBoxAdapter(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.location_off,
                                size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text('주변 정류장을 찾을 수 없습니다',
                                style: TextStyle(
                                    fontSize: 16, color: Colors.grey[600])),
                            const SizedBox(height: 8),
                            ElevatedButton.icon(
                              onPressed: _loadNearbyStations,
                              icon: const Icon(Icons.refresh),
                              label: const Text('다시 시도'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[50],
                                foregroundColor: Colors.blue[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : SliverToBoxAdapter(
                      child: SizedBox(
                        height: 120,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: _nearbyStops.length,
                          itemBuilder: (context, index) {
                            final stop = _nearbyStops[index];
                            return Container(
                              width: 220,
                              margin: const EdgeInsets.only(right: 12),
                              child: Card(
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(
                                    color: _selectedStop?.id == stop.id
                                        ? Colors.blue.shade300
                                        : Colors.grey.shade200,
                                    width: _selectedStop?.id == stop.id ? 2 : 1,
                                  ),
                                ),
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedStop = stop;
                                      _loadBusArrivals();
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.location_on,
                                                color:
                                                    _selectedStop?.id == stop.id
                                                        ? Colors.blue
                                                        : Colors.grey[600],
                                                size: 16),
                                            const SizedBox(width: 4),
                                            if (stop.wincId != null &&
                                                stop.wincId!.isNotEmpty)
                                              Text(
                                                stop.wincId!,
                                                style: TextStyle(
                                                    color: Colors.grey[600],
                                                    fontSize: 12),
                                              ),
                                            const Spacer(),
                                            InkWell(
                                              onTap: () {
                                                _toggleFavorite(stop);
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              child: const Padding(
                                                padding: EdgeInsets.all(4.0),
                                                child: Icon(Icons.star,
                                                    color: Colors.amber,
                                                    size: 20),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          stop.name,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: _selectedStop?.id == stop.id
                                                ? Colors.blue.shade700
                                                : Colors.black87,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            if (stop.distance != null)
                                              Text(
                                                _formatDistance(stop.distance!),
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                    fontWeight:
                                                        FontWeight.w500),
                                              ),
                                            const SizedBox(width: 8),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
        ),
        if (_favoriteStops.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '즐겨찾는 정류장',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _currentIndex = 2;
                      });
                    },
                    child: const Text('전체보기'),
                  ),
                ],
              ),
            ),
          ),
        if (_favoriteStops.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.only(top: 8, bottom: 20),
            sliver: SliverToBoxAdapter(
              child: SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _favoriteStops.length,
                  itemBuilder: (context, index) {
                    final stop = _favoriteStops[index];
                    return Container(
                      width: 200,
                      margin: const EdgeInsets.only(right: 12),
                      child: Card(
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: _selectedStop?.id == stop.id
                                ? Colors.blue.shade300
                                : Colors.grey.shade200,
                            width: _selectedStop?.id == stop.id ? 2 : 1,
                          ),
                        ),
                        child: InkWell(
                          onTap: () {
                            setState(() {
                              _selectedStop = stop;
                              _loadBusArrivals();
                            });
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Icon(
                                      Icons.location_on,
                                      color: _selectedStop?.id == stop.id
                                          ? Colors.blue
                                          : Colors.grey[600],
                                      size: 16,
                                    ),
                                    const SizedBox(width: 4),
                                    if (stop.wincId != null &&
                                        stop.wincId!.isNotEmpty)
                                      Text(
                                        stop.wincId!,
                                        style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12),
                                      ),
                                    const Spacer(),
                                    InkWell(
                                      onTap: () {
                                        _toggleFavorite(stop);
                                      },
                                      borderRadius: BorderRadius.circular(16),
                                      child: Padding(
                                        padding: const EdgeInsets.all(4.0),
                                        child: Icon(
                                          _isStopFavorite(stop)
                                              ? Icons.star
                                              : Icons.star_border,
                                          color: _isStopFavorite(stop)
                                              ? Colors.amber
                                              : Colors.grey,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  stop.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: _selectedStop?.id == stop.id
                                        ? Colors.blue.shade700
                                        : Colors.black87,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        if (_selectedStop != null)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_selectedStop!.name} 버스 도착 정보',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: Icon(
                      _isStopFavorite(_selectedStop!)
                          ? Icons.star
                          : Icons.star_border,
                      color: _isStopFavorite(_selectedStop!)
                          ? Colors.amber
                          : Colors.grey,
                    ),
                    onPressed: () => _toggleFavorite(_selectedStop!),
                  ),
                ],
              ),
            ),
          ),
        if (_selectedStop != null)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _isLoading
                ? const SliverToBoxAdapter(
                    child: Center(child: CircularProgressIndicator()))
                : _errorMessage != null
                    ? SliverToBoxAdapter(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.error_outline,
                                  size: 48, color: Colors.red[300]),
                              const SizedBox(height: 16),
                              Text(
                                _errorMessage!,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.red[700]),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadBusArrivals,
                                child: const Text('다시 시도'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : _busArrivals.isEmpty
                        ? const SliverToBoxAdapter(
                            child: Center(child: Text('도착 예정 버스가 없습니다')))
                        : SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                return CompactBusCard(
                                  busArrival: _busArrivals[index],
                                  onTap: () {
                                    _showBusDetailModal(_busArrivals[index]);
                                  },
                                );
                              },
                              childCount: _busArrivals.length,
                            ),
                          ),
          ),
      ],
    );
  }

  void _showBusDetailModal(BusArrival busArrival) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              BusCard(
                busArrival: busArrival,
                onTap: () {},
                stationName: _selectedStop?.name,
                stationId: _selectedStop?.id ?? "",
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRouteMapTab() {
    return const RouteMapScreen();
  }

  Widget _buildFavoritesTab() {
    return FavoritesScreen(
      favoriteStops: _favoriteStops,
      onStopSelected: (stop) {
        setState(() {
          _selectedStop = stop;
          debugPrint('Favorite stop selected: ${stop.id}, ${stop.name}');
          _loadBusArrivals();
        });
      },
      onFavoriteToggle: _toggleFavorite,
    );
  }

  Widget _buildProfileTab() {
    return const ProfileScreen();
  }

  String _formatDistance(double? distance) {
    if (distance == null) return '거리 정보 없음';
    return distance < 1000
        ? '${distance.toStringAsFixed(0)}m'
        : '${(distance / 1000).toStringAsFixed(1)}km';
  }

  Widget _buildBottomNavigationBar() {
    return NavigationBar(
      selectedIndex: _currentIndex,
      onDestinationSelected: (index) {
        setState(() {
          _currentIndex = index;
        });
      },
      destinations: const <NavigationDestination>[
        NavigationDestination(icon: Icon(Icons.location_on), label: '주변'),
        NavigationDestination(icon: Icon(Icons.map), label: '노선도'),
        NavigationDestination(icon: Icon(Icons.star), label: '즐겨찾기'),
        NavigationDestination(icon: Icon(Icons.person), label: '내정보'),
      ],
    );
  }
}
