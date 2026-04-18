import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';
import '../models/bus_info.dart';
import '../models/bus_route.dart';
import '../services/api_service.dart';
import '../widgets/station_item.dart';
import '../widgets/unified_bus_detail_widget.dart';
import '../utils/debouncer.dart';
import '../widgets/home_search_bar.dart';
import 'route_map_screen.dart';

class SearchScreen extends StatefulWidget {
  final List<BusStop>? favoriteStops;
  final bool routesOnly;

  const SearchScreen({
    super.key,
    this.favoriteStops,
    this.routesOnly = false,
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
  final ValueNotifier<List<BusRoute>> _routeResultsNotifier = ValueNotifier([]);

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
    _routeResultsNotifier.dispose();
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

  Future<void> _searchAll(String query) async {
    if (query.isEmpty) {
      _searchResultsNotifier.value = [];
      _routeResultsNotifier.value = [];
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

    try {
      final stationFuture = widget.routesOnly
          ? Future.value(<BusStop>[])
          : ApiService.searchStations(query).catchError((e) {
              debugPrint('정류장 검색 오류: $e');
              return <BusStop>[];
            });
      final results = await Future.wait([
        stationFuture,
        ApiService.searchBusRoutes(query).catchError((e) {
          debugPrint('노선 검색 오류: $e');
          return <BusRoute>[];
        }),
      ]);

      final stations = (results[0] as List<BusStop>).take(30).toList();
      final routes = (results[1] as List<BusRoute>).take(20).toList();

      if (mounted) {
        _searchResultsNotifier.value = stations
            .map((station) =>
                station.copyWith(isFavorite: _isStopIdFavorite(station.id)))
            .toList();
        _routeResultsNotifier.value = routes;
        setState(() {
          _isLoading = false;
          _stationArrivals.clear();
          _selectedStation = null;
        });
      }
    } catch (e) {
      debugPrint('통합 검색 오류: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '검색 중 오류가 발생했습니다';
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('검색 중 오류가 발생했습니다')),
        );
      }
    }
  }

  Future<void> _loadStationArrivals(BusStop station) async {
    try {
      debugPrint('정류장 도착 정보 조회 시도: ${station.name} (ID: ${station.id})');
      var arrivals = await ApiService.getStationInfo(station.id);

      if (arrivals.isEmpty &&
          station.stationId != null &&
          station.stationId!.isNotEmpty) {
        debugPrint('ID로 조회 실패, stationId로 재시도: ${station.stationId}');
        arrivals = await ApiService.getStationInfo(station.stationId!);
      }

      // 여전히 비어 있고 stationId가 없으면 lazy 변환 후 재시도
      if (arrivals.isEmpty &&
          (station.stationId == null || station.stationId!.isEmpty) &&
          (!station.id.startsWith('7') || station.id.length != 10)) {
        try {
          final converted =
              await ApiService.getStationIdFromBsId(station.id);
          if (converted != null && converted.isNotEmpty) {
            arrivals = await ApiService.getStationInfo(converted);
            if (mounted) {
              final list = _searchResultsNotifier.value;
              final idx = list.indexWhere((s) => s.id == station.id);
              if (idx != -1) {
                final updated = [...list];
                updated[idx] = list[idx].copyWith(stationId: converted);
                _searchResultsNotifier.value = updated;
              }
            }
          }
        } catch (e) {
          debugPrint('정류장 ID lazy 변환 오류: $e');
        }
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
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
                    onPressed: () {
                      Navigator.of(context).pop(_favoriteStops);
                    },
                  ),
                  Expanded(
                    child: HomeSearchBarField(
                      controller: _searchController,
                      focusNode: _searchFieldFocusNode,
                      hintText: widget.routesOnly
                          ? '버스 노선 번호 검색'
                          : '정류장 이름 또는 버스 번호',
                      autofocus: true,
                      onChanged: (value) {
                        _searchDebouncer(() => _searchAll(value));
                        setState(() {});
                      },
                      onSubmitted: (value) {
                        _searchDebouncer.callNow(() => _searchAll(value));
                        FocusScope.of(context).unfocus();
                      },
                      onClear: _searchController.text.isNotEmpty
                          ? () {
                              _searchController.clear();
                              _searchAll('');
                              _searchFieldFocusNode.requestFocus();
                              setState(() {});
                            }
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(child: _buildSearchContent()),
          ],
        ),
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
            Text(
                widget.routesOnly
                    ? '버스 번호를 입력하세요'
                    : '정류장 또는 버스 번호를 입력하세요',
                style: TextStyle(
                    fontSize: 15, color: colorScheme.onSurfaceVariant)),
            const SizedBox(height: 6),
            Text(
                widget.routesOnly
                    ? '예: 304, 623, 급행1'
                    : '예: 대구역, 동대구역, 304, 623',
                style: TextStyle(
                    fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    if (_searchResultsNotifier.value.isEmpty &&
        _routeResultsNotifier.value.isEmpty) {
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
            Text('다른 검색어를 입력해보세요',
                style: TextStyle(
                    fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }
    return _buildSearchResults();
  }

  Widget _buildEmptySectionNotice(String message) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            message,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String label, int count) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
                letterSpacing: -0.2,
              ),
            ),
            TextSpan(
              text: ' ($count)',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _routeColor(BusRoute route, ColorScheme colorScheme, Brightness b) {
    switch (route.getRouteType()) {
      case BusRouteType.express:
        return b == Brightness.dark
            ? const Color(0xFFFF6B6B)
            : const Color(0xFFE53E3E);
      case BusRouteType.seat:
        return b == Brightness.dark
            ? const Color(0xFF4DABF7)
            : const Color(0xFF2B6CB0);
      default:
        return b == Brightness.dark
            ? const Color(0xFF51CF66)
            : const Color(0xFF38A169);
    }
  }

  String _routeTypeLabel(BusRoute route) {
    switch (route.getRouteType()) {
      case BusRouteType.express:
        return '급행';
      case BusRouteType.seat:
        return '좌석';
      default:
        return '일반';
    }
  }

  String _routeSubtitle(BusRoute route) {
    final hasStart = route.startPoint.trim().isNotEmpty;
    final hasEnd = route.endPoint.trim().isNotEmpty;
    if (hasStart && hasEnd) return '${route.startPoint} ↔ ${route.endPoint}';
    final desc = route.routeDescription?.trim() ?? '';
    if (desc.isNotEmpty && desc != route.routeNo) return desc;
    return '';
  }

  Widget _buildRouteTile(BusRoute route) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final badgeColor = _routeColor(route, colorScheme, theme.brightness);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => RouteMapScreen(initialRoute: route),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: badgeColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    route.routeNo,
                    maxLines: 1,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '${route.routeNo}번',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _routeTypeLabel(route),
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_routeSubtitle(route).isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      _routeSubtitle(route),
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                color: colorScheme.onSurfaceVariant, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    final colorScheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<List<BusRoute>>(
      valueListenable: _routeResultsNotifier,
      builder: (context, routes, _) {
        return ValueListenableBuilder<List<BusStop>>(
          valueListenable: _searchResultsNotifier,
          builder: (context, stations, __) {
            // 정류장 상위 10개만 도착정보 prefetch
            const prefetchLimit = 10;
            final prefetchCount =
                stations.length < prefetchLimit ? stations.length : prefetchLimit;
            for (var i = 0; i < prefetchCount; i++) {
              final station = stations[i];
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
                    delegate: SliverChildListDelegate([
                      if (routes.isNotEmpty) ...[
                        _buildSectionHeader('버스 노선', routes.length),
                        ...routes.map(_buildRouteTile).expand((w) => [
                              w,
                              Divider(
                                  color: colorScheme.outline.withAlpha(20),
                                  height: 1),
                            ]),
                      ] else if (stations.isNotEmpty && !widget.routesOnly)
                        _buildEmptySectionNotice('해당하는 버스 노선이 없습니다'),
                      if (!widget.routesOnly) ...[
                        if (stations.isNotEmpty)
                          _buildSectionHeader('정류장', stations.length)
                        else if (routes.isNotEmpty)
                          _buildEmptySectionNotice('해당하는 정류장이 없습니다'),
                      ],
                    ]),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final station = stations[index];
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
                                            stationId: station.stationId ??
                                                station.id,
                                            stationName: station.name,
                                            isCompact: true,
                                            onTap: () =>
                                                showUnifiedBusDetailModal(
                                              context,
                                              arrival,
                                              station.stationId ?? station.id,
                                              station.name,
                                            ),
                                          ))
                                      .toList(),
                                ),
                              ),
                            if (index < stations.length - 1)
                              Divider(color: colorScheme.outline.withAlpha(20)),
                          ],
                        );
                      },
                      childCount: stations.length,
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            );
          },
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
          formattedTime = '운행 종료';
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
