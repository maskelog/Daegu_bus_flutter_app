import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';
import '../services/api_service.dart';
import '../widgets/station_item.dart';
import '../widgets/unified_bus_detail_widget.dart';

class SearchScreen extends StatefulWidget {
  final List<BusStop>? favoriteStops;

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
  final Map<String, List<BusArrival>> _stationArrivals = {};
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

  Future<void> _loadFavoriteStops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      final favorites = prefs.getStringList('favorites') ?? [];
      setState(() {
        _favoriteStops = favorites.map((json) {
          final data = jsonDecode(json);
          return BusStop.fromJson(data);
        }).toList();
      });
    } catch (e) {
      debugPrint('Error loading favorites: $e');
    }
  }

  Future<void> _saveFavoriteStops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = _favoriteStops
          .map((stop) => jsonEncode(stop.toJson())) // toJson() 메서드 사용로 통일
          .toList();
      await prefs.setStringList('favorites', favorites);
      debugPrint('즐겨찾기 저장 완료: ${_favoriteStops.length}개 정류장');
    } catch (e) {
      debugPrint('Error saving favorites: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('즐겨찾기 저장에 실패했습니다')),
        );
      }
    }
  }

  void _toggleFavorite(BusStop stop) {
    setState(() {
      if (_isStopFavorite(stop)) {
        _favoriteStops.removeWhere((s) => s.id == stop.id);
        final index = _searchResults.indexWhere((s) => s.id == stop.id);
        if (index != -1) {
          _searchResults[index] =
              _searchResults[index].copyWith(isFavorite: false);
        }
        debugPrint('즐겨찾기에서 제거: ${stop.name}');
      } else {
        _favoriteStops.add(stop.copyWith(isFavorite: true));
        final index = _searchResults.indexWhere((s) => s.id == stop.id);
        if (index != -1) {
          _searchResults[index] =
              _searchResults[index].copyWith(isFavorite: true);
        }
        debugPrint('즐겨찾기에 추가: ${stop.name}');
      }
    });

    // 즉시 저장
    _saveFavoriteStops();

    // 사용자에게 피드백 제공
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_isStopFavorite(stop)
              ? '${stop.name} 정류장이 즐겨찾기에 추가되었습니다'
              : '${stop.name} 정류장이 즐겨찾기에서 제거되었습니다'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  bool _isStopFavorite(BusStop stop) {
    return _favoriteStops.any((s) => s.id == stop.id);
  }

  bool _isStopIdFavorite(String stopId) {
    return _favoriteStops.any((s) => s.id == stopId);
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

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    try {
      final results = await ApiService.searchStations(query); // 정적 호출로 변경
      final limitedResults = results.take(30).toList();

      // stationId 확인 및 가공
      for (var i = 0; i < limitedResults.length; i++) {
        var station = limitedResults[i];
        // stationId 확인
        if ((station.stationId == null || station.stationId!.isEmpty) &&
            (!station.id.startsWith('7') || station.id.length != 10)) {
          try {
            // 각 정류장마다 검색을 하면 성능 저하가 심함
            // 따라서 일반 정류장만 한 번에 20개까지만 변환 시도
            if (i < 20) {
              debugPrint('정류장 ID 변환 시도: ${station.name} (${station.id})');

              // getStationIdFromBsId 메서드 사용
              final String? convertedId =
                  await ApiService.getStationIdFromBsId(station.id);
              if (convertedId != null && convertedId.isNotEmpty) {
                limitedResults[i] = station.copyWith(
                  stationId: convertedId,
                  isFavorite: _isStopIdFavorite(station.id),
                );
                debugPrint('정류장 ID 변환 성공: ${station.id} -> $convertedId');
              }
            }
          } catch (e) {
            debugPrint('정류장 ID 변환 오류: $e');
          }
        }
      }

      if (mounted) {
        setState(() {
          _searchResults = limitedResults
              .map((station) =>
                  station.copyWith(isFavorite: _isStopIdFavorite(station.id)))
              .toList();
          _isLoading = false;
          _stationArrivals.clear();
          _selectedStation = null;
        });
      }
    } catch (e) {
      debugPrint('정류장 검색 오류: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '정류장 검색 중 오류가 발생했습니다';
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
      // 첫 번째 시도
      debugPrint('정류장 도착 정보 조회 시도: ${station.name} (ID: ${station.id})');
      var arrivals = await ApiService.getStationInfo(station.id);

      // 결과가 없는 경우 stationId로 재시도
      if (arrivals.isEmpty &&
          station.stationId != null &&
          station.stationId!.isNotEmpty) {
        debugPrint('ID로 조회 실패, stationId로 재시도: ${station.stationId}');
        arrivals = await ApiService.getStationInfo(station.stationId!);
      }

      if (mounted) {
        setState(() {
          _stationArrivals[station.id] = arrivals;
          _isLoading = false;

          if (arrivals.isEmpty) {
            debugPrint('정류장 도착 정보 없음: ${station.name}');
            // 결과가 없지만 오류는 아님
            _errorMessage = null;
          } else {
            debugPrint('정류장 도착 정보 로드 성공: ${arrivals.length}개 버스');
          }
        });
      }
    } catch (e) {
      debugPrint('정류장 도착 정보 로드 오류: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '버스 도착 정보를 불러오지 못했습니다. 다시 시도해주세요.';
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
            // 즐겨찾기 변경 사항을 호출자에게 알리기 위해 favoriteStops를 반환
            Navigator.of(context).pop(_favoriteStops);
          },
        ),
      ),
      body: Column(
        children: [
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
          Expanded(child: _buildSearchContent()),
        ],
      ),
    );
  }

  Widget _buildSearchContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
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
            Icon(Icons.search, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('정류장 이름을 입력하여 검색하세요',
                style: TextStyle(fontSize: 16, color: Colors.grey[600])),
            const SizedBox(height: 8),
            const Text('예: 대구역, 동대구역, 현풍시외버스터미널',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
          ],
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('\'${_searchController.text}\' 검색 결과가 없습니다',
                style: TextStyle(fontSize: 16, color: Colors.grey[600])),
            const SizedBox(height: 8),
            const Text('다른 정류장 이름으로 검색해보세요',
                style: TextStyle(fontSize: 14, color: Colors.grey)),
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
                        setState(() {
                          if (isSelected) {
                            _selectedStation = null;
                          } else {
                            _selectedStation = station;
                            if (!hasArrivalInfo) {
                              _loadStationArrivals(station);
                            }
                          }
                        });
                      },
                      onFavoriteToggle: () => _toggleFavorite(station),
                    ),
                    if (isSelected &&
                        hasArrivalInfo &&
                        _stationArrivals[station.id]!.isNotEmpty)
                      Padding(
                        padding:
                            const EdgeInsets.only(left: 16, top: 8, bottom: 16),
                        child: Column(
                          children: [
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
                            Column(
                              children: _stationArrivals[station.id]!
                                  .take(3)
                                  .map((arrival) => UnifiedBusDetailWidget(
                                        busArrival: arrival,
                                        stationId:
                                            station.stationId ?? station.id,
                                        stationName: station.name,
                                        isCompact: true,
                                        onTap: () => showUnifiedBusDetailModal(
                                          context,
                                          arrival,
                                          station.stationId ?? station.id,
                                          station.name,
                                        ),
                                      ))
                                  .toList(),
                            ),
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
