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

  @override
  void dispose() {
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  // 노선 검색
  void _searchRoutes(String query) {
    print('검색 쿼리: $query'); // 디버그 로그 추가

    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();

    _searchDebounce = Timer(const Duration(milliseconds: 500), () {
      print('실제 검색 쿼리: $query'); // 추가 디버그 로그

      final RegExp searchPattern = RegExp(r'^[가-힣0-9A-Za-z\s\-\(\)_]+$');

      if (query.length < 2 || !searchPattern.hasMatch(query)) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
          _errorMessage = query.isEmpty ? null : '2자 이상의 한글, 숫자, 영문으로 검색해주세요';
        });
        return;
      }

      setState(() {
        _isSearching = true;
        _errorMessage = null;
      });

      ApiService.searchBusRoutes(query).then((routes) {
        print('검색 결과: ${routes.length}개'); // 결과 로깅

        if (mounted) {
          setState(() {
            _searchResults = routes;
            _isSearching = false;
            _errorMessage =
                routes.isEmpty ? '\'$query\'에 대한 검색 결과가 없습니다' : null;
          });

          if (routes.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('\'$query\'에 대한 검색 결과가 없습니다'),
                backgroundColor: Colors.orange[400],
              ),
            );
          }
        }
      }).catchError((e) {
        print('검색 중 오류 발생: $e'); // 오류 로깅

        if (mounted) {
          setState(() {
            _errorMessage = '노선 검색 중 오류가 발생했습니다';
            _isSearching = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('노선 검색 중 오류가 발생했습니다: $e'),
              backgroundColor: Colors.red[400],
            ),
          );
        }
      });
    });
  }

  // 노선도 로드
  Future<void> _loadRouteMap(BusRoute route) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedRoute = route;
    });

    try {
      final stations = await ApiService.getRouteStations(route.id);
      if (mounted) {
        setState(() {
          _routeStations = stations;
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
    return Column(
      children: [
        // 검색 바
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
                hintText: '버스 노선번호 검색 (예: 304, 급행1)',
                prefixIcon: Icon(Icons.search, color: Colors.blue[700]),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
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

        // 검색 결과 또는 노선도 표시
        Expanded(
          child: _buildContent(),
        ),
      ],
    );
  }

  Widget _buildContent() {
    // 로딩 중
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 에러 메시지
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: TextStyle(color: Colors.red[700]),
            ),
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

    // 검색 중
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

    // 노선이 선택된 경우 노선도 표시
    if (_selectedRoute != null) {
      return _buildRouteStationList();
    }

    // 검색 결과 표시
    if (_searchResults.isNotEmpty) {
      return ListView.builder(
        itemCount: _searchResults.length,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final route = _searchResults[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
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
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${route.startPoint} → ${route.endPoint}',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          if (route.routeDescription.isNotEmpty)
                            Text(
                              route.routeDescription,
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
                    const Icon(Icons.arrow_forward_ios, size: 16),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    // 초기 상태 또는 검색 결과 없음
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
            '예) 304, 급행1, 남구1 등',
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
            Text(
              '노선 정보가 없습니다',
              style: TextStyle(color: Colors.grey[700]),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _selectedRoute = null;
                });
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('노선 검색으로 돌아가기'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 노선 정보 헤더
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.blue[50],
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _selectedRoute!.routeNo,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_selectedRoute!.startPoint} → ${_selectedRoute!.endPoint}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '정류장 ${_routeStations.length}개',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    _selectedRoute = null;
                  });
                },
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

        // 노선도 목록
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
                      // 노선 연결선
                      SizedBox(
                        width: 24,
                        height: 60,
                        child: CustomPaint(
                          painter: RouteLinePainter(
                            isStart: isStart,
                            isEnd: isEnd,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // 정류장 정보
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            // TODO: 정류장 상세정보 또는 도착정보로 이동 기능 추가
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
                                    if (station.stationId.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.grey[200],
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          station.stationId,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.grey[700],
                                          ),
                                        ),
                                      ),
                                    const SizedBox(width: 8),
                                    if (isStart)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.green[100],
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '기점',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.green[700],
                                          ),
                                        ),
                                      ),
                                    if (isEnd)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.red[100],
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '종점',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.red[700],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  station.stationName,
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
}

// 노선 연결선 그리기 위한 CustomPainter
class RouteLinePainter extends CustomPainter {
  final bool isStart;
  final bool isEnd;

  RouteLinePainter({
    required this.isStart,
    required this.isEnd,
  });

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

    // 정류장 점
    canvas.drawCircle(center, 6, circlePaint);

    // 연결선
    if (!isStart) {
      canvas.drawLine(
        Offset(center.dx, 0),
        center,
        paint,
      );
    }

    if (!isEnd) {
      canvas.drawLine(
        center,
        Offset(center.dx, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
