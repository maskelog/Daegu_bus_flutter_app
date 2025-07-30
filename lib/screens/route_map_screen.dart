import 'package:flutter/material.dart';
import '../models/bus_route.dart';
import '../models/route_station.dart';
import '../services/api_service.dart';
import 'map_screen.dart';

class RouteMapScreen extends StatefulWidget {
  const RouteMapScreen({super.key});

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isLoading = false;
  String? _errorMessage;
  BusRoute? _selectedRoute;
  List<BusRoute> _searchResults = [];
  List<RouteStation> _routeStations = [];

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _searchRoute() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _selectedRoute = null;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedRoute = null;
    });

    try {
      final results = await ApiService.searchBusRoutes(query);
      setState(() {
        _searchResults = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '노선 검색 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectRoute(BusRoute route) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 노선 상세 정보와 정류장 목록을 동시에 가져오기
      final results = await Future.wait([
        ApiService.getBusRouteDetails(route.id),
        ApiService.getRouteStations(route.id),
      ]);

      final detailedRoute = results[0] as BusRoute?;
      final stationsData = results[1] as List<dynamic>;

      // 정류장 데이터를 RouteStation 객체로 변환
      final List<RouteStation> stations = stationsData
          .map((station) => RouteStation.fromJson(station))
          .toList();

      // 순서대로 정렬
      stations.sort((a, b) => a.sequenceNo.compareTo(b.sequenceNo));

      setState(() {
        _selectedRoute = detailedRoute ?? route;
        _routeStations = stations;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '노선 상세 정보를 불러오는 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        title: Text(
          _selectedRoute?.routeNo != null
              ? '${_selectedRoute!.routeNo} 노선도'
              : '노선도',
          style: TextStyle(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          if (_selectedRoute != null)
            IconButton(
              icon: const Icon(Icons.map),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MapScreen(
                      routeId: _selectedRoute!.id,
                      routeStations: _routeStations,
                    ),
                  ),
                );
              },
              tooltip: '지도에서 보기',
            ),
        ],
        elevation: 0,
      ),
      body: Column(
        children: [
          // 검색 영역
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: TextStyle(color: colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: '버스 번호를 입력하세요 (예: 304, 623)',
                      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
                      prefixIcon: Icon(Icons.search,
                          color: colorScheme.onSurfaceVariant),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear,
                                  color: colorScheme.onSurfaceVariant),
                              onPressed: () {
                                _searchController.clear();
                                setState(() {
                                  _searchResults = [];
                                  _selectedRoute = null;
                                  _errorMessage = null;
                                });
                              },
                            )
                          : null,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.outline),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.outline),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: colorScheme.primary),
                      ),
                      filled: true,
                      fillColor: colorScheme.surface,
                    ),
                    onSubmitted: (_) => _searchRoute(),
                    onChanged: (value) {
                      if (value.isEmpty) {
                        setState(() {
                          _searchResults = [];
                          _selectedRoute = null;
                          _errorMessage = null;
                        });
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _searchRoute,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    backgroundColor: colorScheme.primary,
                    foregroundColor: colorScheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    '검색',
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 오류 메시지
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: colorScheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: colorScheme.onErrorContainer),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // 로딩 인디케이터
          if (_isLoading)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Center(
                child: CircularProgressIndicator(
                  color: colorScheme.primary,
                ),
              ),
            ),

          // 검색 결과 또는 선택된 노선 정보
          Expanded(
            child: _selectedRoute != null
                ? _buildRouteDetails()
                : _buildSearchResults(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (_searchResults.isEmpty &&
        _searchController.text.isNotEmpty &&
        !_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '검색 결과가 없습니다',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '다른 버스 번호를 입력해보세요',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.route,
              size: 64,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              '버스 노선 검색',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '버스 번호를 입력하여 노선 정보를 확인하세요',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final route = _searchResults[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: colorScheme.surfaceContainerHighest,
          elevation: 2,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getRouteColor(route),
              child: Text(
                route.routeNo,
                style: TextStyle(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              '${route.routeNo}번 버스',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            subtitle: Text(
              route.routeDescription?.isNotEmpty == true
                  ? route.routeDescription!
                  : '노선명 없음',
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            trailing: Icon(
              Icons.arrow_forward_ios,
              color: colorScheme.onSurfaceVariant,
            ),
            onTap: () => _selectRoute(route),
          ),
        );
      },
    );
  }

  Widget _buildRouteDetails() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final route = _selectedRoute!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 노선 헤더
          Card(
            color: colorScheme.surfaceContainerHighest,
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: _getRouteColor(route),
                        child: Text(
                          route.routeNo,
                          style: TextStyle(
                            color: colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${route.routeNo}번 버스',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '노선 정보',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildInfoRow('노선 타입', _getRouteTypeText(route)),
                  _buildInfoRow(
                      '운행 구간', '${route.startPoint} ↔ ${route.endPoint}'),
                  if (route.routeDescription?.isNotEmpty == true)
                    ..._buildRouteDescriptionRows(route.routeDescription!),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 정류장 목록
          Card(
            color: colorScheme.surfaceContainerHighest,
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.location_on, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        '정류장 목록 (${_routeStations.length}개)',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_routeStations.isNotEmpty)
                    ..._routeStations.asMap().entries.map((entry) {
                      final index = entry.key;
                      final station = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: station.stationType == StationType.start
                                    ? colorScheme.primary
                                    : station.stationType == StationType.end
                                        ? colorScheme.error
                                        : colorScheme.secondary,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    color: colorScheme.onPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                station.stationName,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (station.stationType == StationType.start)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '기점',
                                  style: TextStyle(
                                    color: colorScheme.onPrimaryContainer,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              )
                            else if (station.stationType == StationType.end)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.errorContainer,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '종점',
                                  style: TextStyle(
                                    color: colorScheme.onErrorContainer,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    })
                  else
                    Text(
                      '정류장 정보를 불러오는 중입니다...',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 뒤로가기 버튼
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () {
                setState(() {
                  _selectedRoute = null;
                });
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                foregroundColor: colorScheme.primary,
                side: BorderSide(color: colorScheme.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                '다른 노선 검색',
                style: TextStyle(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRouteDescriptionRows(String description) {
    final List<Widget> rows = [];

    // "배차간격: 10분, 업체: 대구시내버스" 형식 파싱
    final parts = description.split(', ');
    String? interval;
    final List<String> companies = [];

    for (String part in parts) {
      if (part.contains('배차간격:')) {
        interval = part.replaceFirst('배차간격:', '').trim();
      } else if (part.contains('업체:')) {
        final company = part.replaceFirst('업체:', '').trim();
        if (company != '정보 없음' && company.isNotEmpty) {
          // 여러 업체가 쉼표로 구분되어 있을 수 있음
          final companyList = company
              .split(',')
              .map((c) => c.trim())
              .where((c) => c.isNotEmpty)
              .toList();
          companies.addAll(companyList);
        }
      }
    }

    // 배차간격 표시
    if (interval != null && interval != '정보 없음' && interval.isNotEmpty) {
      rows.add(_buildInfoRow('배차간격', interval));
    }

    // 운수업체 표시 (여러 업체가 있으면 모두 표시)
    if (companies.isNotEmpty) {
      if (companies.length == 1) {
        rows.add(_buildInfoRow('운수업체', companies.first));
      } else {
        rows.add(_buildInfoRow('운수업체', companies.join(', ')));
      }
    }

    return rows;
  }

  Color _getRouteColor(BusRoute route) {
    final brightness = Theme.of(context).brightness;

    switch (route.getRouteType()) {
      case BusRouteType.express:
        // 급행버스 - 빨간색 계열
        return brightness == Brightness.dark
            ? const Color(0xFFFF6B6B) // 다크모드에서 더 밝은 빨간색
            : const Color(0xFFE53E3E); // 라이트모드에서 진한 빨간색
      case BusRouteType.seat:
        // 좌석버스 - 파란색 계열
        return brightness == Brightness.dark
            ? const Color(0xFF4DABF7) // 다크모드에서 더 밝은 파란색
            : const Color(0xFF2B6CB0); // 라이트모드에서 진한 파란색
      case BusRouteType.regular:
      default:
        // 일반버스 - 초록색 계열
        return brightness == Brightness.dark
            ? const Color(0xFF51CF66) // 다크모드에서 더 밝은 초록색
            : const Color(0xFF38A169); // 라이트모드에서 진한 초록색
    }
  }

  String _getRouteTypeText(BusRoute route) {
    switch (route.getRouteType()) {
      case BusRouteType.express:
        return '급행버스';
      case BusRouteType.seat:
        return '좌석버스';
      case BusRouteType.regular:
      default:
        return '일반버스';
    }
  }
}
