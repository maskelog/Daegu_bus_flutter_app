import 'package:flutter/material.dart';
import 'dart:async';
import '../models/bus_route.dart';
import '../models/route_station.dart';
import '../services/api_service.dart';

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
        '급행',
        '수성',
        '남구',
        '북구',
        '동구',
        '서구',
        '달서',
        '달성'
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
          setState(() {
            _routeStationsCache[route.id] = stations;
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
        setState(() {
          _routeStations = stations;
          _routeStationsCache[route.id] = stations; // 캐시에 저장
          _isLoading = false;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('노선 지도'),
      ),
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
                            _getRoutePathText(route),
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
                      _getSelectedRoutePathText(),
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
                onPressed: () => setState(() => _selectedRoute = null),
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
                          onTap: () {
                            // TODO: 정류장 상세정보로 이동
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isStart || isEnd
                                  ? Colors.blue[50]
                                  : Colors.grey[50],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isStart || isEnd
                                    ? Colors.blue[200]!
                                    : Colors.grey[300]!,
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
                                        station.bsId, // stationId -> bsId
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
                                          color: Colors.green[100],
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '기점',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.green[700]),
                                        ),
                                      ),
                                    if (isEnd)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: Colors.red[100],
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '종점',
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.red[700]),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  station.bsNm, // stationName -> bsNm
                                  style: TextStyle(
                                    fontWeight: isStart || isEnd
                                        ? FontWeight.bold
                                        : FontWeight.normal,
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

  // 노선의 경로(기점→종점) 텍스트를 반환하는 메소드
  String _getRoutePathText(BusRoute route) {
    // 캐시에 해당 노선의 정류장 정보가 있는 경우
    if (_routeStationsCache.containsKey(route.id) &&
        _routeStationsCache[route.id]!.isNotEmpty) {
      final stations = _routeStationsCache[route.id]!;
      final firstStation = stations.first;
      final lastStation = stations.last;
      return '${firstStation.bsNm} → ${lastStation.bsNm}';
    }
    // 선택된 노선과 현재 노선이 동일하고 정류장 정보가 있으면
    else if (_selectedRoute?.id == route.id && _routeStations.isNotEmpty) {
      // 노선도에서 첫 번째와 마지막 정류장 정보를 사용
      final firstStation = _routeStations.first;
      final lastStation = _routeStations.last;
      return '${firstStation.bsNm} → ${lastStation.bsNm}';
    }
    // 그렇지 않으면 노선 객체의 정보 사용
    else if (route.startPoint != null && route.endPoint != null) {
      return '${route.startPoint} → ${route.endPoint}';
    }
    // 모든 정보가 없는 경우 - 로딩 표시
    else {
      return '${route.routeNo} 노선 정보 로딩 중...';
    }
  }

  // 노선도 화면에서 선택된 노선의 경로 텍스트를 반환
  String _getSelectedRoutePathText() {
    if (_routeStations.isNotEmpty) {
      final firstStation = _routeStations.first;
      final lastStation = _routeStations.last;
      return '${firstStation.bsNm} → ${lastStation.bsNm}';
    } else if (_selectedRoute!.startPoint != null &&
        _selectedRoute!.endPoint != null) {
      return '${_selectedRoute!.startPoint} → ${_selectedRoute!.endPoint}';
    } else {
      return '노선 정보를 불러오는 중입니다...';
    }
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
