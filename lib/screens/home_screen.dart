import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
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
  List<BusStop> _nearbyStops = []; // 주변 정류장 목록
  BusStop? _selectedStop;
  List<BusArrival> _busArrivals = [];
  bool _isLoading = false;
  bool _isLoadingNearby = false; // 주변 정류장 로딩 상태
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadFavoriteStops();
    _loadNearbyStations(); // 주변 정류장 로드
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 주변 정류장 로드
  Future<void> _loadNearbyStations() async {
    if (!mounted) return;

    setState(() {
      _isLoadingNearby = true;
    });

    try {
      // 1000m(1km) 이내의 정류장 검색
      final nearbyStations = await LocationService.getNearbyStations(1000);

      if (mounted) {
        setState(() {
          _nearbyStops = nearbyStations;
          _isLoadingNearby = false;

          // 주변 정류장이 있고 아직 선택된 정류장이 없으면 가장 가까운 정류장 선택
          if (_nearbyStops.isNotEmpty && _selectedStop == null) {
            _selectedStop = _nearbyStops.first;
            _loadBusArrivals();
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading nearby stations: $e');
      if (mounted) {
        setState(() {
          _isLoadingNearby = false;
        });
      }
    }
  }

  // 즐겨찾기 불러오기
  Future<void> _loadFavoriteStops() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      final favorites = prefs.getStringList('favorites') ?? [];

      _favoriteStops.clear();

      for (var json in favorites) {
        final data = jsonDecode(json);
        _favoriteStops.add(BusStop(
          id: data['id'],
          name: data['name'],
          isFavorite: true,
          wincId: data['wincId'],
          routeList: data['routeList'],
          ngisXPos: data['ngisXPos'],
          ngisYPos: data['ngisYPos'],
        ));
      }

      // 즐겨찾기가 있고 아직 선택된 정류장이 없으면 첫번째 즐겨찾기 정류장 선택
      if (_favoriteStops.isNotEmpty && _selectedStop == null) {
        _selectedStop = _favoriteStops.first;
        _loadBusArrivals();
      }
    } catch (e) {
      debugPrint('Error loading favorites: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '즐겨찾기를 불러오는 중 오류가 발생했습니다.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // 즐겨찾기 저장
  Future<void> _saveFavoriteStops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> favorites = [];

      for (var stop in _favoriteStops) {
        favorites.add(jsonEncode({
          'id': stop.id,
          'name': stop.name,
          'isFavorite': true,
          'wincId': stop.wincId,
          'routeList': stop.routeList,
          'ngisXPos': stop.ngisXPos,
          'ngisYPos': stop.ngisYPos,
        }));
      }

      await prefs.setStringList('favorites', favorites);
    } catch (e) {
      debugPrint('Error saving favorites: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('즐겨찾기 저장에 실패했습니다')),
        );
      }
    }
  }

  // 정류장 즐겨찾기 추가/제거
  void _toggleFavorite(BusStop stop) {
    setState(() {
      if (_isStopFavorite(stop)) {
        _favoriteStops.removeWhere((s) => s.id == stop.id);

        // 현재 선택된 정류장이 즐겨찾기에서 제거된 경우, 다른 정류장 선택
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

    // 즐겨찾기 추가/제거 알림
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isStopFavorite(stop)
            ? '${stop.name} 정류장이 즐겨찾기에 추가되었습니다'
            : '${stop.name} 정류장이 즐겨찾기에서 제거되었습니다'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // 정류장이 즐겨찾기에 있는지 확인
  bool _isStopFavorite(BusStop stop) {
    return _favoriteStops.any((s) => s.id == stop.id);
  }

  // 버스 도착 정보 로드
  Future<void> _loadBusArrivals() async {
    if (_selectedStop == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final arrivalsData = await ApiService.getStationInfo(_selectedStop!.id);
      if (!mounted) return;

      setState(() {
        _busArrivals = arrivalsData;
      });
    } catch (e) {
      debugPrint('Error loading arrivals: $e');
      if (!mounted) return;

      setState(() {
        _errorMessage = '버스 도착 정보를 불러오지 못했습니다.';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('버스 도착 정보를 불러오지 못했습니다: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
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
        // 새로고침 버튼
        if (_currentIndex == 0) // 주변 정류장 탭일 때
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadNearbyStations();
              if (_selectedStop != null) {
                _loadBusArrivals();
              }
            },
          ),
        if (_currentIndex == 2) // 즐겨찾기 탭일 때
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadFavoriteStops();
            },
          ),
      ],
    );
  }

  Widget _buildBody() {
    return _currentIndex == 0
        ? _buildNearbyTab()
        : _currentIndex == 1
            ? _buildRouteMapTab()
            : _currentIndex == 2
                ? _buildFavoritesTab()
                : _buildProfileTab();
  }

  Widget _buildNearbyTab() {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16.0),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              // 검색 바
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
                        // 정류장이 반환된 경우
                        setState(() {
                          _selectedStop = result;

                          // 즐겨찾기 추가/제거 처리
                          if (result.isFavorite && !_isStopFavorite(result)) {
                            _favoriteStops.add(result);
                            _saveFavoriteStops();
                          }

                          _loadBusArrivals();
                        });
                      } else if (result is List) {
                        // 즐겨찾기 목록이 반환된 경우
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
        // 주변 정류장 섹션 헤더
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  '주변 정류장',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
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
        // 주변 정류장 목록
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
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
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
                          Icon(
                            Icons.location_off,
                            size: 48,
                            color: Colors.grey[400],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '주변 정류장을 찾을 수 없습니다',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey[600],
                            ),
                          ),
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
                    ))
                  : SliverToBoxAdapter(
                      child: SizedBox(
                        height: 160,
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
                                        // 정류장 번호 및 이름
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.location_on,
                                              color:
                                                  _selectedStop?.id == stop.id
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
                                                  fontSize: 12,
                                                ),
                                              ),
                                            const Spacer(),
                                            // 즐겨찾기 아이콘
                                            InkWell(
                                              onTap: () {
                                                _toggleFavorite(stop);
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.all(4.0),
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
                                        // 정류장 이름
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
                                        // 거리 및 노선 정보
                                        Row(
                                          children: [
                                            if (stop.distance != null)
                                              Text(
                                                _formatDistance(stop.distance!),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: Colors.grey[600],
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            const SizedBox(width: 8),
                                            if (stop.routeList != null &&
                                                stop.routeList!.isNotEmpty)
                                              Expanded(
                                                child: Text(
                                                  stop.routeList!,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[600],
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
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
        // 즐겨찾는 정류장
        if (_favoriteStops.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: SliverToBoxAdapter(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '즐겨찾는 정류장',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _currentIndex = 2; // 즐겨찾기 탭으로 이동
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
                height: 140,
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
                                // 정류장 번호 및 이름
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
                                          fontSize: 12,
                                        ),
                                      ),
                                    const Spacer(),
                                    // 즐겨찾기 아이콘
                                    InkWell(
                                      onTap: () {
                                        _toggleFavorite(stop);
                                      },
                                      borderRadius: BorderRadius.circular(16),
                                      child: const Padding(
                                        padding: EdgeInsets.all(4.0),
                                        child: Icon(
                                          Icons.star,
                                          color: Colors.amber,
                                          size: 20,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                // 정류장 이름
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
                                // 노선 정보
                                if (stop.routeList != null &&
                                    stop.routeList!.isNotEmpty)
                                  Text(
                                    stop.routeList!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
          ), // 선택된 정류장 도착 정보 섹션
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
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
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

        // 버스 도착 정보 목록
        if (_selectedStop != null)
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: _isLoading
                ? const SliverToBoxAdapter(
                    child: Center(child: CircularProgressIndicator()),
                  )
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
                            child: Center(child: Text('도착 예정 버스가 없습니다')),
                          )
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Text(
                  //   '${busArrival.routeNo}번 버스',
                  //   style: const TextStyle(
                  //     fontSize: 20,
                  //     fontWeight: FontWeight.bold,
                  //   ),
                  // ),
                  // const SizedBox(width: 8), // 여백 추가
                  // Expanded(
                  //   child: Text(
                  //     '${_selectedStop?.name}',
                  //     style: TextStyle(
                  //       fontSize: 16,
                  //       color: Colors.grey[800],
                  //     ),
                  //     overflow: TextOverflow.ellipsis,
                  //     maxLines: 1,
                  //   ),
                  // ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),

              const SizedBox(height: 16),
              // 버스 도착 정보 상세
              BusCard(
                busArrival: busArrival,
                onTap: () {},
                stationName: _selectedStop?.name,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRouteMapTab() {
    return const Center(
      child: Text('노선도 화면 (개발 예정)'),
    );
  }

  Widget _buildFavoritesTab() {
    return FavoritesScreen(
      favoriteStops: _favoriteStops,
      onStopSelected: (stop) {
        setState(() {
          _selectedStop = stop;
          // 바닥 탐색 바 인덱스 변경하지 않음
          _loadBusArrivals();
        });
      },
      onFavoriteToggle: _toggleFavorite,
    );
  }

  Widget _buildProfileTab() {
    return const Center(
      child: Text('내정보 화면 (개발 예정)'),
    );
  }

// 거리 포맷팅 메서드
  String _formatDistance(String distanceStr) {
    try {
      final distance = double.parse(distanceStr);
      if (distance < 1000) {
        return '${distance.toStringAsFixed(0)}m';
      } else {
        return '${(distance / 1000).toStringAsFixed(1)}km';
      }
    } catch (e) {
      return distanceStr;
    }
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
        NavigationDestination(
          icon: Icon(Icons.location_on),
          label: '주변',
        ),
        NavigationDestination(
          icon: Icon(Icons.map),
          label: '노선도',
        ),
        NavigationDestination(
          icon: Icon(Icons.star),
          label: '즐겨찾기',
        ),
        NavigationDestination(
          icon: Icon(Icons.person),
          label: '내정보',
        ),
      ],
    );
  }
}
