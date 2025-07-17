import 'package:flutter/material.dart';
import 'dart:async';
import '../models/bus_route.dart';
import '../models/route_station.dart';
import '../services/api_service.dart';
import '../widgets/compact_bus_card.dart';
import '../models/bus_arrival.dart';
import 'settings_screen.dart';

class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen({super.key});

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<BusRoute> _searchResults = [];
  BusRoute? _selectedRoute;
  List<RouteStation> _routeStations = [];
  bool _isLoading = false;
  bool _isSearching = false;
  String? _errorMessage;
  Timer? _searchDebounce;
  List<BusArrival> _selectedStationArrivals = [];

  // 노선 ID별 정류장 정보를 캐싱하는 맵
  final Map<String, List<RouteStation>> _routeStationsCache = {};

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _searchRoutes(String query) {
    debugPrint('검색 쿼리: $query');

    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();

    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      debugPrint('실제 검색 쿼리: $query');
      debugPrint('검색어 길이: ${query.length}');

      final RegExp searchPattern = RegExp(r'^[가-힣0-9A-Za-z\s\-\(\)_]+$');
      bool matchesPattern = searchPattern.hasMatch(query);
      debugPrint('패턴 일치 여부: $matchesPattern');

      final List<String> specialKeywords = [
        '급행', '수성', '남구', '북구', '동구',
        '서구', '달서', '달성', '군위',
        // 추가 키워드: 노선 이름에 포함된 지역명
        '10', '1', '1-1', '3', '4', '5', '6', '7', '8'
      ];
      bool isSpecialKeyword =
          specialKeywords.any((keyword) => query.contains(keyword));
      bool isNumeric = RegExp(r'^[0-9]+$').hasMatch(query);

      if ((query.length < 2 && !isNumeric && !isSpecialKeyword) ||
          !matchesPattern) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
          _errorMessage = query.isEmpty
              ? null
              : '검색어는 한글, 숫자, 영문으로 입력해주세요\n(특수 키워드 또는 숫자는 1자 이상)';
        });
        return;
      }

      setState(() {
        _isSearching = true;
        _errorMessage = null;
      });

      ApiService.searchBusRoutes(query).then((routes) {
        debugPrint('검색 결과: ${routes.length}개');

        if (mounted) {
          setState(() {
            _searchResults = routes;
            _isSearching = false;
            _errorMessage =
                routes.isEmpty ? '\'$query\'에 대한 검색 결과가 없습니다' : null;
          });

          if (routes.isEmpty) {
            String suggestion = '';
            if (query.contains('급행') && query.length == 2) {
              suggestion = '\n"급행1", "급행2" 등과 같이 구체적인 노선번호를 입력해보세요.';
            } else if (query.length == 1) {
              suggestion = '\n더 구체적인 노선번호를 입력해보세요.';
            }

            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('\'$query\'에 대한 검색 결과가 없습니다.$suggestion'),
                backgroundColor:
                    Theme.of(context).colorScheme.tertiaryContainer,
                duration: const Duration(seconds: 3),
              ),
            );
          } else {
            // 검색 결과가 있으면 각 노선의 정류장 정보 미리 가져오기
            _preloadRouteStations(routes);
          }
        }
      }).catchError((e) {
        debugPrint('검색 중 오류 발생: $e');
        if (mounted) {
          setState(() {
            _errorMessage = '노선 검색 중 오류가 발생했습니다';
            _isSearching = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('노선 검색 중 오류가 발생했습니다: $e'),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    });
  }

  // 노선들의 정류장 정보를 미리 가져오는 메소드
  void _preloadRouteStations(List<BusRoute> routes) {
    for (final route in routes) {
      // 이미 캐시에 있는 경우 스킵
      if (_routeStationsCache.containsKey(route.id)) continue;

      ApiService.getRouteStations(route.id).then((stationsData) {
        if (mounted && stationsData.isNotEmpty) {
          // 데이터를 RouteStation 객체로 변환
          final List<RouteStation> stations = stationsData
              .map((station) => RouteStation.fromJson(station))
              .toList();

          // 순서대로 정렬
          stations.sort((a, b) => a.sequenceNo.compareTo(b.sequenceNo));

          setState(() {
            _routeStationsCache[route.id] = stations;

            // 검색 결과에 보여지는 노선을 업데이트하기 위함
            if (_searchResults.isNotEmpty) {
              setState(() {});
            }
          });
        }
      }).catchError((e) {
        debugPrint('${route.routeNo} 노선 정류장 로드 중 오류: $e');
      });
    }
  }

  Future<void> _loadRouteMap(BusRoute route) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedRoute = route;
      _selectedStationArrivals = [];
    });

    try {
      // 캐시에 있으면 캐시에서 가져오기
      if (_routeStationsCache.containsKey(route.id)) {
        setState(() {
          _routeStations = _routeStationsCache[route.id]!;
          _isLoading = false;
        });
        return;
      }

      final dynamic stationsData = await ApiService.getRouteStations(route.id);
      final List<RouteStation> stations = (stationsData as List)
          .map((station) => RouteStation.fromJson(station))
          .toList();
      if (mounted) {
        stations.sort((a, b) => a.sequenceNo.compareTo(b.sequenceNo));
        setState(() {
          _routeStations = stations;
          _routeStationsCache[route.id] = stations; // 캐시에 저장
          _isLoading = false;
          debugPrint('노선 ${route.routeNo} 정류장 수: ${stations.length}');
          debugPrint(
              '기점: ${stations.isNotEmpty ? stations.first.stationName : '없음'}');
          debugPrint(
              '종점: ${stations.isNotEmpty ? stations.last.stationName : '없음'}');
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '노선도를 불러오는 중 오류가 발생했습니다';
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('노선도를 불러오는 중 오류가 발생했습니다: $e')),
        );
      }
    }
  }

  // 정류장 클릭 시 모든 도착 정보 가져오기
  Future<void> _showStationArrival(RouteStation station) async {
    try {
      final arrivals = await ApiService.getStationInfo(station.stationId);
      if (mounted) {
        setState(() {
          _selectedStationArrivals = arrivals; // 모든 도착 정보 저장
          debugPrint(
              '정류장 ${station.stationName} 도착 정보: ${arrivals.length}개 노선');
        });
      }
    } catch (e) {
      debugPrint('정류장 도착 정보 조회 오류: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('도착 정보 조회 실패: $e')),
        );
      }
    }
  }

  // 노선의 기점-종점 정보를 가져오는 메소드
  String _getRouteEndpoints(BusRoute route) {
    // 이미 캐시에 해당 노선의 정류장 정보가 있는 경우 사용
    if (_routeStationsCache.containsKey(route.id) &&
        _routeStationsCache[route.id]!.isNotEmpty) {
      final stations = _routeStationsCache[route.id]!;
      return '${stations.first.stationName} → ${stations.last.stationName}';
    }

    // 선택된 노선이고 정류장 정보가 있는 경우
    if (_selectedRoute?.id == route.id && _routeStations.isNotEmpty) {
      return '${_routeStations.first.stationName} → ${_routeStations.last.stationName}';
    }

    // API에서 받아온 시작점/종점 정보가 있는 경우 (낙후된 방법)
    if (route.startPoint.isNotEmpty && route.endPoint.isNotEmpty) {
      return '${route.startPoint} → ${route.endPoint}';
    }

    // 노선 정보 로딩 중임을 표시
    return '노선 정보 로딩 중...';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Column(
        children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  // 검색 필드 - Material 3 스타일
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
                          onChanged: _searchRoutes,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                          ),
                          decoration: InputDecoration(
                            hintText: '버스 노선번호 검색 (예: 503, 급행1)',
                            hintStyle: theme.textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 16,
                              fontWeight: FontWeight.normal,
                              height: 1.2,
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
                                          _searchRoutes('');
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
                            filled: false,
                            fillColor: Colors.transparent,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 0,
                              vertical: 14,
                            ),
                          ),
                          maxLines: 1,
                          textInputAction: TextInputAction.search,
                          textAlignVertical: TextAlignVertical.center,
                          onSubmitted: (value) {
                            // 엔터키 눌렀을 때 키보드 숨기기
                            FocusScope.of(context).unfocus();
                          },
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
          Expanded(child: _buildContent()),
          if (_selectedStationArrivals.isNotEmpty) // 모든 도착 정보 표시
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '도착 정보',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _selectedStationArrivals.length,
                        itemBuilder: (context, index) {
                          final arrival = _selectedStationArrivals[index];
                          final matchingStation = _routeStations.firstWhere(
                            (s) =>
                                s.stationId ==
                                arrival.routeId, // 노선 ID로 비교하는 것이 맞는지 확인 필요
                            orElse: () => RouteStation(
                                stationId: '',
                                stationName: '알 수 없음',
                                sequenceNo: 0,
                                latitude: 0.0,
                                longitude: 0.0),
                          );
                          return CompactBusCard(
                            busArrival: arrival,
                            onTap: () {},
                            stationName: matchingStation.stationName,
                            stationId: matchingStation.stationId,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_isLoading) {
      return Center(
          child: CircularProgressIndicator(color: colorScheme.primary));
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: colorScheme.error)),
            if (_selectedRoute != null) ...[
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => _loadRouteMap(_selectedRoute!),
                child: const Text('다시 시도'),
              ),
            ],
          ],
        ),
      );
    }

    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text('노선을 검색하는 중...',
                style: TextStyle(color: colorScheme.onSurface)),
          ],
        ),
      );
    }

    if (_selectedRoute != null) {
      return _buildRouteStationList();
    }

    if (_searchResults.isNotEmpty) {
      return ListView.builder(
        itemCount: _searchResults.length,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final route = _searchResults[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: colorScheme.surface,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () => _loadRouteMap(route),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        route.routeNo,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getRouteEndpoints(route),
                            style: TextStyle(
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurface),
                          ),
                          if (route.routeDescription != null &&
                              route.routeDescription!.isNotEmpty)
                            Text(
                              route.routeDescription!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios,
                        size: 16, color: colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.directions_bus,
              size: 64, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 24),
          Text(
            _searchController.text.isEmpty ? '버스 노선번호를 검색하세요' : '검색 결과가 없습니다',
            style: TextStyle(fontSize: 16, color: colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            '예) 503, 급행1, 남구1 등',
            style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteStationList() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_routeStations.isEmpty) {
      debugPrint('노선 정보가 없습니다. 선택된 노선: ${_selectedRoute?.routeNo}');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.route, size: 64, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('노선 정보가 없습니다', style: TextStyle(color: colorScheme.onSurface)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => setState(() => _selectedRoute = null),
              icon: const Icon(Icons.arrow_back),
              label: const Text('노선 검색으로 돌아가기'),
            ),
          ],
        ),
      );
    }

    debugPrint(
        '노선 ${_selectedRoute!.routeNo} 정류장 ${_routeStations.length}개 표시');

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: colorScheme.primaryContainer.withValues(alpha: 0.3),
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedRoute!.routeNo,
                  style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _routeStations.isNotEmpty
                          ? '${_routeStations.first.stationName} → ${_routeStations.last.stationName}'
                          : '기점/종점 정보 없음',
                      style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '정류장 ${_routeStations.length}개',
                      style: TextStyle(
                          fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () => setState(() {
                  _selectedRoute = null;
                  _selectedStationArrivals = [];
                }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.surface,
                  foregroundColor: colorScheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text('뒤로'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _routeStations.length,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemBuilder: (context, index) {
              final station = _routeStations[index];
              final bool isStart = index == 0;
              final bool isEnd = index == _routeStations.length - 1;

              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24,
                        height: 60,
                        child: CustomPaint(
                          painter: RouteLinePainter(
                              isStart: isStart,
                              isEnd: isEnd,
                              colorScheme: colorScheme),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () => _showStationArrival(station),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isStart
                                  ? colorScheme.primaryContainer
                                      .withValues(alpha: 0.3)
                                  : isEnd
                                      ? colorScheme.errorContainer
                                          .withValues(alpha: 0.3)
                                      : colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isStart
                                    ? colorScheme.primary
                                    : isEnd
                                        ? colorScheme.error
                                        : colorScheme.outline,
                                width: isStart || isEnd ? 2 : 1,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        station.stationId,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color:
                                                colorScheme.onSurfaceVariant),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (isStart)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.primaryContainer,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '기점',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: colorScheme
                                                  .onPrimaryContainer,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    if (isEnd)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: colorScheme.errorContainer,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '종점',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color:
                                                  colorScheme.onErrorContainer,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  station.stationName,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: isStart || isEnd
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isStart
                                        ? colorScheme.onPrimaryContainer
                                        : isEnd
                                            ? colorScheme.onErrorContainer
                                            : colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class RouteLinePainter extends CustomPainter {
  final bool isStart;
  final bool isEnd;
  final ColorScheme colorScheme;

  RouteLinePainter(
      {required this.isStart, required this.isEnd, required this.colorScheme});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colorScheme.primary
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final circlePaint = Paint()
      ..color = colorScheme.primary
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);

    canvas.drawCircle(center, 6, circlePaint);

    if (!isStart) {
      canvas.drawLine(Offset(center.dx, 0), center, paint);
    }

    if (!isEnd) {
      canvas.drawLine(center, Offset(center.dx, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
