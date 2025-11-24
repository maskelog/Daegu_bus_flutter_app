import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';
import '../models/bus_info.dart';
import '../services/api_service.dart';
import '../widgets/station_item.dart';
import '../widgets/unified_bus_detail_widget.dart';
import '../utils/debouncer.dart';

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
  final Debouncer _searchDebouncer =
      Debouncer(delay: const Duration(milliseconds: 400));
  final FocusNode _searchFieldFocusNode = FocusNode();
  final ValueNotifier<List<BusStop>> _searchResultsNotifier = ValueNotifier([]);

  List<BusStop> _favoriteStops = [];
  final Map<String, List<BusArrival>> _stationArrivals = {};
  final Set<String> _loadingArrivals = {}; // 추가: 중복 호출 방지용
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
    _searchDebouncer.dispose();
    _searchFieldFocusNode.dispose();
    _searchResultsNotifier.dispose();
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
        final index =
            _searchResultsNotifier.value.indexWhere((s) => s.id == stop.id);
        if (index != -1) {
          _searchResultsNotifier.value[index] =
              _searchResultsNotifier.value[index].copyWith(isFavorite: false);
        }
        debugPrint('즐겨찾기에서 제거: ${stop.name}');
      } else {
        _favoriteStops.add(stop.copyWith(isFavorite: true));
        final index =
            _searchResultsNotifier.value.indexWhere((s) => s.id == stop.id);
        if (index != -1) {
          _searchResultsNotifier.value[index] =
              _searchResultsNotifier.value[index].copyWith(isFavorite: true);
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
      _searchResultsNotifier.value = [];
      setState(() {
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
        _searchResultsNotifier.value = limitedResults
            .map((station) =>
                station.copyWith(isFavorite: _isStopIdFavorite(station.id)))
            .toList();
        setState(() {
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
          if (arrivals.isEmpty) {
            debugPrint('정류장 도착 정보 없음: ${station.name}');
          } else {
            debugPrint('정류장 도착 정보 로드 성공: ${arrivals.length}개 버스');
          }
        });
      }
    } catch (e) {
      debugPrint('정류장 도착 정보 로드 오류: $e');
      if (mounted) {
        setState(() {
          _stationArrivals[station.id] = []; // 오류 발생 시 빈 리스트로 처리
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        title: Text(
          '정류장 검색',
          style: TextStyle(color: colorScheme.onSurface),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
          onPressed: () {
            // 즐겨찾기 변경 사항을 호출자에게 알리기 위해 favoriteStops를 반환
            Navigator.of(context).pop(_favoriteStops);
          },
        ),
        elevation: 0,
        surfaceTintColor: colorScheme.surfaceTint,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
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
                          color: colorScheme.primary.withValues(alpha: 0.8),
                          width: 2,
                        )
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.05),
                      blurRadius: FocusScope.of(context).hasFocus ? 4 : 2,
                      offset: const Offset(0, 1),
                    ),
                    if (FocusScope.of(context).hasFocus)
                      BoxShadow(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                  ],
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFieldFocusNode,
                  autofocus: true,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurface,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                  decoration: InputDecoration(
                    hintText: '정류장 이름을 입력하세요',
                    hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 16,
                          fontWeight: FontWeight.normal,
                        ),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.only(left: 20, right: 12),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.search_rounded,
                          key: ValueKey(FocusScope.of(context).hasFocus),
                          color: FocusScope.of(context).hasFocus
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          size: 24,
                        ),
                      ),
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Material(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  _searchController.clear();
                                  _searchStations('');
                                },
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerHigh,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Icon(
                                    Icons.clear_rounded,
                                    size: 18,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : null,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 16,
                    ),
                  ),
                  maxLines: 1,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) {
                    _searchDebouncer(() => _searchStations(value));
                  },
                  onSubmitted: (value) {
                    _searchDebouncer.callNow(() => _searchStations(value));
                    // 엔터키 눌렀을 때 키보드 숨기기
                    FocusScope.of(context).unfocus();
                  },
                ),
              ),
            ),
          ),
          Expanded(child: _buildSearchContent()),
        ],
      ),
    );
  }

  Widget _buildSearchContent() {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.error, fontSize: 15),
            ),
          ],
        ),
      );
    }
    if (!_hasSearched) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('정류장 이름을 입력하여 검색하세요',
                style: TextStyle(
                    fontSize: 15, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text('예: 대구역, 동대구역, 현풍시외버스터미널',
                style: TextStyle(
                    fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    if (_searchResultsNotifier.value.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off,
                size: 48, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text('\'${_searchController.text}\' 검색 결과가 없습니다',
                style: TextStyle(
                    fontSize: 15, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text('다른 정류장 이름으로 검색해보세요',
                style: TextStyle(
                    fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    return _buildSearchResults();
  }

  Widget _buildSearchResults() {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<List<BusStop>>(
      valueListenable: _searchResultsNotifier,
      builder: (context, searchResults, _) {
        // 검색 결과가 갱신될 때마다 각 정류장에 대해 도착 정보가 없으면 비동기로 불러온다
        for (final station in searchResults) {
          if (!_stationArrivals.containsKey(station.id) &&
              !_loadingArrivals.contains(station.id)) {
            _loadingArrivals.add(station.id);
            _loadStationArrivals(station).whenComplete(() {
              _loadingArrivals.remove(station.id);
            });
          }
        }
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final station = searchResults[index];
                    final isSelected = _selectedStation?.id == station.id;
                    final hasArrivalInfo =
                        _stationArrivals.containsKey(station.id);

                    return Column(
                      children: [
                        _StationItemWrapper(
                          station: station,
                          isSelected: isSelected,
                          arrivals: _stationArrivals[station.id],
                          onSelect: () {
                            Navigator.of(context).pop(station);
                          },
                          onFavoriteToggle: () => _toggleFavorite(station),
                        ),
                        if (isSelected &&
                            hasArrivalInfo &&
                            _stationArrivals[station.id]!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 16, top: 8, bottom: 16),
                            child: Column(
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
                          ),
                        if (index < searchResults.length - 1)
                          Divider(color: colorScheme.outline.withAlpha(20)),
                      ],
                    );
                  },
                  childCount: searchResults.length,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StationItemWrapper extends StatefulWidget {
  final BusStop station;
  final bool isSelected;
  final List<BusArrival>? arrivals;
  final VoidCallback onSelect;
  final VoidCallback onFavoriteToggle;

  const _StationItemWrapper({
    required this.station,
    required this.isSelected,
    required this.arrivals,
    required this.onSelect,
    required this.onFavoriteToggle,
  });

  @override
  State<_StationItemWrapper> createState() => _StationItemWrapperState();
}

class _StationItemWrapperState extends State<_StationItemWrapper> {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StationItem(
          station: widget.station,
          isSelected: widget.isSelected,
          onTap: widget.onSelect,
          onFavoriteToggle: () {
            setState(() {}); // 즐겨찾기 토글 시 해당 아이템만 리빌드
            widget.onFavoriteToggle();
          },
        ),
        Padding(
          padding:
              const EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 4),
          child: _buildArrivalsInfo(widget.arrivals, colorScheme),
        ),
      ],
    );
  }

  Widget _buildArrivalsInfo(
      List<BusArrival>? arrivals, ColorScheme colorScheme) {
    if (arrivals == null) {
      return Text('도착 정보 불러오는 중...',
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant));
    }
    if (arrivals.isEmpty) {
      return Text('도착 정보 없음',
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant));
    }

    final List<Map<String, dynamic>> allArrivals = [];
    for (final arrival in arrivals) {
      for (final bus in arrival.busInfoList) {
        allArrivals.add({'arrival': arrival, 'bus': bus});
      }
    }

    if (allArrivals.isEmpty) {
      return Text('도착 정보 없음',
          style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant));
    }

    return GridView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: allArrivals.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 4,
      ),
      itemBuilder: (context, index) {
        final item = allArrivals[index];
        final BusArrival arrival = item['arrival'];
        final BusInfo bus = item['bus'];

        final remainingTime = bus.getRemainingMinutes();
        String formattedTime;

        if (bus.isOutOfService) {
          formattedTime = '운행종료';
        } else if (bus.estimatedTime == '곧 도착' || remainingTime == 0) {
          formattedTime = '곧 도착';
        } else if (remainingTime == 1) {
          formattedTime = '약 1분 후';
        } else if (remainingTime > 1) {
          formattedTime = '약 $remainingTime분 후';
        } else {
          formattedTime =
              bus.estimatedTime.isNotEmpty ? bus.estimatedTime : '정보 없음';
        }

        return InkWell(
          onTap: () {
            // 클릭한 버스의 상세 정보를 모달로 표시
            showUnifiedBusDetailModal(
              context,
              arrival,
              widget.station.stationId ?? widget.station.id,
              widget.station.name,
            );
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
            child: Row(
              children: [
                Text(
                  arrival.routeNo,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                      fontSize: 14),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    formattedTime,
                    style: TextStyle(
                        color: colorScheme.onSurfaceVariant, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (bus.isLowFloor)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text('[저상]',
                        style: TextStyle(fontSize: 12, color: colorScheme.primary)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
