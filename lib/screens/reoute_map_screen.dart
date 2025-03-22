import 'package:flutter/material.dart';
import 'dart:async';
import '../models/bus_route.dart';
import '../models/route_station.dart';
import '../services/api_service.dart';
import '../widgets/compact_bus_card.dart';
import '../models/bus_arrival.dart';

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
                backgroundColor: Colors.orange[400],
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
              backgroundColor: Colors.red[400],
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

      ApiService.getRouteStations(route.id).then((stations) {
        if (mounted && stations.isNotEmpty) {
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

      final stations = await ApiService.getRouteStations(route.id);
      if (mounted) {
        stations.sort((a, b) => a.sequenceNo.compareTo(b.sequenceNo));
        setState(() {
          _routeStations = stations;
          _routeStationsCache[route.id] = stations; // 캐시에 저장
          _isLoading = false;
          debugPrint('노선 ${route.routeNo} 정류장 수: ${stations.length}');
          debugPrint('기점: ${stations.isNotEmpty ? stations.first.bsNm : '없음'}');
          debugPrint('종점: ${stations.isNotEmpty ? stations.last.bsNm : '없음'}');
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
      final arrivals = await ApiService.getStationInfo(station.bsId);
      if (mounted) {
        setState(() {
          _selectedStationArrivals = arrivals; // 모든 도착 정보 저장
          debugPrint('정류장 ${station.bsNm} 도착 정보: ${arrivals.length}개 노선');
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
      return '${stations.first.bsNm} → ${stations.last.bsNm}';
    }

    // 선택된 노선이고 정류장 정보가 있는 경우
    if (_selectedRoute?.id == route.id && _routeStations.isNotEmpty) {
      return '${_routeStations.first.bsNm} → ${_routeStations.last.bsNm}';
    }

    // API에서 받아온 시작점/종점 정보가 있는 경우 (낙후된 방법)
    if (route.startPoint != null && route.endPoint != null) {
      return '${route.startPoint} → ${route.endPoint}';
    }

    // 노선 정보 로딩 중임을 표시
    return '노선 정보 로딩 중...';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.grey[100],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _searchRoutes,
                decoration: InputDecoration(
                  hintText: '버스 노선번호 검색 (예: 503, 급행1)',
                  prefixIcon: Icon(Icons.search, color: Colors.blue[700]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            _searchRoutes('');
                          },
                        )
                      : null,
                ),
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
                            (s) => s.bsId == arrival.stationId,
                            orElse: () => RouteStation(
                                bsId: '',
                                bsNm: '알 수 없음',
                                sequenceNo: 0,
                                lat: 0.0,
                                lng: 0.0),
                          );
                          return CompactBusCard(
                            busArrival: arrival,
                            onTap: () {},
                            stationName: matchingStation.bsNm,
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
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(_errorMessage!, style: TextStyle(color: Colors.red[700])),
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
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('노선을 검색하는 중...'),
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
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        route.routeNo,
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[700]),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getRouteEndpoints(route),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          if (route.routeDescription != null &&
                              route.routeDescription!.isNotEmpty)
                            Text(
                              route.routeDescription!,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey[600]),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios, size: 16),
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
          Icon(Icons.directions_bus, size: 64, color: Colors.blue[200]),
          const SizedBox(height: 24),
          Text(
            _searchController.text.isEmpty ? '버스 노선번호를 검색하세요' : '검색 결과가 없습니다',
            style: TextStyle(fontSize: 16, color: Colors.grey[700]),
          ),
          const SizedBox(height: 8),
          Text(
            '예) 503, 급행1, 남구1 등',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteStationList() {
    if (_routeStations.isEmpty) {
      debugPrint('노선 정보가 없습니다. 선택된 노선: ${_selectedRoute?.routeNo}');
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.route, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text('노선 정보가 없습니다', style: TextStyle(color: Colors.grey[700])),
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
          color: Colors.blue[50],
          child: Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedRoute!.routeNo,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _routeStations.isNotEmpty
                          ? '${_routeStations.first.bsNm} → ${_routeStations.last.bsNm}'
                          : '기점/종점 정보 없음',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '정류장 ${_routeStations.length}개',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
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
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.blue,
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
                          painter:
                              RouteLinePainter(isStart: isStart, isEnd: isEnd),
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
                                  ? Colors.green[50]
                                  : isEnd
                                      ? Colors.red[50]
                                      : Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isStart
                                    ? Colors.green[200]!
                                    : isEnd
                                        ? Colors.red[200]!
                                        : Colors.grey[300]!,
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
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        station.bsId,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[700]),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (isStart)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.green[200],
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '기점',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.green[800],
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    if (isEnd)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red[200],
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '종점',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.red[800],
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  station.bsNm,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: isStart || isEnd
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isStart
                                        ? Colors.green[900]
                                        : isEnd
                                            ? Colors.red[900]
                                            : Colors.black87,
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

  RouteLinePainter({required this.isStart, required this.isEnd});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 4
      ..style = PaintingStyle.stroke;

    final circlePaint = Paint()
      ..color = Colors.blue
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
