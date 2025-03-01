import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';
import '../services/api_service.dart';
import '../widgets/station_item.dart';
import '../widgets/compact_bus_card.dart';

class SearchScreen extends StatefulWidget {
  final List<BusStop>? favoriteStops; // 홈 화면에서 전달받는 즐겨찾기 목록

  const SearchScreen({
    super.key,
    this.favoriteStops,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<BusStop> _searchResults = [];
  List<BusStop> _favoriteStops = [];
  Map<String, List<BusArrival>> _stationArrivals = {};
  bool _isLoading = false;
  bool _hasSearched = false;
  String? _errorMessage;
  BusStop? _selectedStation;

  @override
  void initState() {
    super.initState();
    if (widget.favoriteStops != null) {
      _favoriteStops = List.from(widget.favoriteStops!);
    } else {
      _loadFavoriteStops();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // 즐겨찾기 불러오기
  Future<void> _loadFavoriteStops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      final favorites = prefs.getStringList('favorites') ?? [];

      setState(() {
        _favoriteStops = favorites.map((json) {
          final data = jsonDecode(json);
          return BusStop(
            id: data['id'],
            name: data['name'],
            isFavorite: true,
            wincId: data['wincId'],
            routeList: data['routeList'],
            ngisXPos: data['ngisXPos'],
            ngisYPos: data['ngisYPos'],
          );
        }).toList();
      });
    } catch (e) {
      debugPrint('Error loading favorites: $e');
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

        // 검색 결과에서도 즐겨찾기 상태 업데이트
        final index = _searchResults.indexWhere((s) => s.id == stop.id);
        if (index != -1) {
          _searchResults[index] =
              _searchResults[index].copyWith(isFavorite: false);
        }
      } else {
        _favoriteStops.add(stop.copyWith(isFavorite: true));

        // 검색 결과에서도 즐겨찾기 상태 업데이트
        final index = _searchResults.indexWhere((s) => s.id == stop.id);
        if (index != -1) {
          _searchResults[index] =
              _searchResults[index].copyWith(isFavorite: true);
        }
      }
      _saveFavoriteStops();
    });
  }

  // 정류장이 즐겨찾기에 있는지 확인
  bool _isStopFavorite(BusStop stop) {
    return _favoriteStops.any((s) => s.id == stop.id);
  }

  Future<void> _searchStations(String query) async {
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _hasSearched = false;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasSearched = true;
      _errorMessage = null;
    });

    try {
      final results = await ApiService.searchStations(query);

      if (mounted) {
        setState(() {
          // 검색 결과에 즐겨찾기 상태 설정
          _searchResults = results.map((stop) {
            return stop.copyWith(isFavorite: _isStopFavorite(stop));
          }).toList();
          _isLoading = false;

          // 이전에 조회했던 정류장 정보 초기화
          _stationArrivals = {};
          _selectedStation = null;
        });
      }
    } catch (e) {
      debugPrint('Error searching stations: $e');

      if (mounted) {
        setState(() {
          _errorMessage = '정류장 검색 중 오류가 발생했습니다.\n$e';
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('정류장 검색 중 오류가 발생했습니다')),
        );
      }
    }
  }

  Future<void> _loadStationArrivals(BusStop station) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedStation = station;
    });

    try {
      final arrivals = await ApiService.getStationInfo(station.id);

      if (mounted) {
        setState(() {
          _stationArrivals[station.id] = arrivals;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading arrivals: $e');

      if (mounted) {
        setState(() {
          _errorMessage = '버스 도착 정보를 불러오지 못했습니다';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('정류장 검색'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // 홈 화면으로 돌아갈 때 즐겨찾기 목록 전달
            Navigator.of(context).pop(_favoriteStops);
          },
        ),
      ),
      body: Column(
        children: [
          // 검색 입력 필드
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '정류장 이름을 입력하세요',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          _searchStations('');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
              ),
              onChanged: _searchStations,
              onSubmitted: _searchStations,
            ),
          ),

          // 검색 결과 또는 안내 메시지
          Expanded(
            child: _buildSearchContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.red[700]),
          ),
        ),
      );
    }

    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '정류장 이름을 입력하여 검색하세요',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '예: 대구역, 동대구역, 현풍시외버스터미널',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '\'${_searchController.text}\' 검색 결과가 없습니다',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '다른 정류장 이름으로 검색해보세요',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final station = _searchResults[index];
                final isSelected = _selectedStation?.id == station.id;
                final hasArrivalInfo = _stationArrivals.containsKey(station.id);

                return Column(
                  children: [
                    StationItem(
                      station: station,
                      isSelected: isSelected,
                      onTap: () {
                        if (isSelected) {
                          setState(() {
                            _selectedStation = null;
                          });
                        } else {
                          if (!hasArrivalInfo) {
                            _loadStationArrivals(station);
                          } else {
                            setState(() {
                              _selectedStation = station;
                            });
                          }
                        }
                      },
                      onFavoriteToggle: () => _toggleFavorite(station),
                    ),

                    // 선택된 정류장의 버스 도착 정보 표시
                    if (isSelected &&
                        hasArrivalInfo &&
                        _stationArrivals[station.id]!.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 16, top: 8, bottom: 16),
                        child: Column(
                          children: [
                            // 선택 버튼 추가
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                ElevatedButton(
                                  onPressed: () {
                                    final updatedStation = station.copyWith(
                                        isFavorite: _isStopFavorite(station));
                                    Navigator.of(context).pop(updatedStation);
                                  },
                                  child: const Text('이 정류장 선택하기'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // 버스 도착 정보 목록
                            Column(
                              children: _stationArrivals[station.id]!
                                  .take(3) // 최대 3개까지만 표시
                                  .map((arrival) => CompactBusCard(
                                        busArrival: arrival,
                                        onTap: () {},
                                      ))
                                  .toList(),
                            ),

                            // 더 많은 버스가 있을 경우
                            if (_stationArrivals[station.id]!.length > 3)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: TextButton(
                                  onPressed: () {
                                    final updatedStation = station.copyWith(
                                        isFavorite: _isStopFavorite(station));
                                    Navigator.of(context).pop(updatedStation);
                                  },
                                  child: Text(
                                    '+ ${_stationArrivals[station.id]!.length - 3}개 더 보기',
                                    style: TextStyle(color: Colors.blue[700]),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                    if (index < _searchResults.length - 1) const Divider(),
                  ],
                );
              },
              childCount: _searchResults.length,
            ),
          ),
        ),
      ],
    );
  }
}
