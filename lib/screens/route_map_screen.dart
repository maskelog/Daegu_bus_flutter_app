import 'package:flutter/material.dart';
import '../models/bus_arrival.dart';
import '../models/bus_route.dart';
import '../models/route_station.dart';
import '../services/api_service.dart';
import 'map_screen.dart';

class RouteMapScreen extends StatefulWidget {
  final BusRoute? initialRoute;

  const RouteMapScreen({super.key, this.initialRoute});

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

class _RouteMapScreenState extends State<RouteMapScreen> {
  bool _isLoading = false;
  String? _errorMessage;
  BusRoute? _selectedRoute;
  List<RouteStation> _routeStations = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialRoute != null) {
      _selectedRoute = widget.initialRoute;
      _isLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _selectRoute(widget.initialRoute!);
      });
    }
  }

  Future<void> _selectRoute(BusRoute route) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _selectedRoute = route;
      _routeStations = [];
    });

    // 정류장 목록과 상세 정보를 병렬 요청하되, 먼저 도착하는 쪽부터 UI 반영
    final stationsFuture = ApiService.getRouteStations(route.id).then((data) {
      if (!mounted) return;
      final stations = data
          .map((s) => RouteStation.fromJson(s))
          .toList()
        ..sort((a, b) => a.sequenceNo.compareTo(b.sequenceNo));
      setState(() {
        _routeStations = stations;
      });
    }).catchError((e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '정류장 목록을 불러오지 못했습니다: $e';
      });
    });

    final detailsFuture =
        ApiService.getBusRouteDetails(route.id).then((detailed) {
      if (!mounted || detailed == null) return;
      setState(() {
        _selectedRoute = _mergeRoute(route, detailed);
      });
    }).catchError((_) {/* 상세 정보는 실패해도 초기 route 유지 */});

    await Future.wait([stationsFuture, detailsFuture]);
    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  BusRoute _mergeRoute(BusRoute base, BusRoute detailed) {
    return base.copyWith(
      routeNo: detailed.routeNo.isNotEmpty ? detailed.routeNo : base.routeNo,
      routeTp: detailed.routeTp.isNotEmpty ? detailed.routeTp : base.routeTp,
      startPoint: detailed.startPoint.isNotEmpty
          ? detailed.startPoint
          : base.startPoint,
      endPoint:
          detailed.endPoint.isNotEmpty ? detailed.endPoint : base.endPoint,
      routeDescription: (detailed.routeDescription?.isNotEmpty ?? false)
          ? detailed.routeDescription
          : base.routeDescription,
    );
  }

  Future<void> _showStationArrivals(RouteStation station) async {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      showDragHandle: true,
      builder: (_) => _StationArrivalsSheet(
        station: station,
        currentRouteNo: _selectedRoute?.routeNo,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: _selectedRoute != null
          ? AppBar(
              backgroundColor: colorScheme.surface,
              foregroundColor: colorScheme.onSurface,
              title: Text(
                '${_selectedRoute!.routeNo}번 버스',
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.bold,
                ),
              ),
              actions: [
                if (_routeStations.isNotEmpty)
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
              surfaceTintColor: colorScheme.surfaceTint,
            )
          : null,
      body: Column(
        children: [
          if (_isLoading && _selectedRoute == null)
            const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
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
          Expanded(
            child: _selectedRoute != null
                ? _buildRouteDetails()
                : const _EmptyState(
                    icon: Icons.route,
                    title: '버스 노선 검색',
                    subtitle: '상단 검색창에서 버스 번호를 입력하세요',
                  ),
          ),
        ],
      ),
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
          _buildRouteHeaderCard(route, theme, colorScheme),
          const SizedBox(height: 16),
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
                      return InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () => _showStationArrivals(station),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 6, horizontal: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: station.stationType ==
                                          StationType.start
                                      ? colorScheme.primary
                                      : station.stationType == StationType.end
                                          ? colorScheme.error
                                          : colorScheme.secondary,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    '${index + 1}',
                                    style: const TextStyle(
                                      color: Colors.white,
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
                                _stationTag('기점',
                                    colorScheme.primaryContainer,
                                    colorScheme.onPrimaryContainer)
                              else if (station.stationType == StationType.end)
                                _stationTag('종점',
                                    colorScheme.errorContainer,
                                    colorScheme.onErrorContainer),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      );
                    })
                  else if (_isLoading)
                    Text(
                      '정류장 정보를 불러오는 중입니다...',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    )
                  else
                    Text(
                      '정류장 정보가 없습니다.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildRouteHeaderCard(
      BusRoute route, ThemeData theme, ColorScheme colorScheme) {
    final typeName = '대구 ${route.getRouteTypeName()}버스';
    final hasStart = route.startPoint.trim().isNotEmpty &&
        route.startPoint != '출발지 정보 없음';
    final hasEnd =
        route.endPoint.trim().isNotEmpty && route.endPoint != '도착지 정보 없음';
    final corridor = (hasStart && hasEnd)
        ? '${route.startPoint} ↔ ${route.endPoint}'
        : null;

    final desc = _parseDescription(route.routeDescription);
    final firstLast =
        (desc.firstTm != null && desc.lastTm != null)
            ? '${desc.firstTm} ~ ${desc.lastTm}'
            : null;
    final intervalLabel = desc.interval != null
        ? '배차간격 ${desc.interval}'
        : null;
    final tripLabel = desc.tripCount != null ? '${desc.tripCount}회' : null;

    final line1 = [typeName, if (corridor != null) corridor].join(' | ');
    final line2Parts = [
      if (firstLast != null) firstLast,
      if (intervalLabel != null) intervalLabel,
      if (tripLabel != null) tripLabel,
    ];
    final line2 = line2Parts.join(' | ');

    return Card(
      color: colorScheme.surfaceContainerHighest,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              line1,
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (line2.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                line2,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (desc.company != null) ...[
              const SizedBox(height: 4),
              Text(
                desc.company!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  _RouteDescription _parseDescription(String? raw) {
    if (raw == null || raw.isEmpty) return const _RouteDescription();
    // 우선 " | " 구분자로 파싱 시도 (avgTm/comNm 내부의 쉼표 보존)
    List<String> parts = raw.contains(' | ') ? raw.split(' | ') : raw.split(', ');
    String? interval;
    String? company;
    String? firstTm;
    String? lastTm;
    String? tripCount;

    String? pending; // 이전 필드 이어 붙이기 (쉼표 분리된 경우 보정)
    String? pendingKey;
    void flush() {
      if (pending == null || pendingKey == null) return;
      final v = pending!.trim();
      if (v.isNotEmpty && v != '정보 없음') {
        switch (pendingKey) {
          case 'interval': interval = v; break;
          case 'company': company = v; break;
          case 'first': firstTm = v; break;
          case 'last': lastTm = v; break;
          case 'trip': tripCount = v; break;
        }
      }
      pending = null;
      pendingKey = null;
    }

    for (final part in parts) {
      final p = part.trim();
      String? key;
      String? value;
      if (p.startsWith('배차간격:')) {
        key = 'interval'; value = p.substring(5).trim();
      } else if (p.startsWith('업체:')) {
        key = 'company'; value = p.substring(3).trim();
      } else if (p.startsWith('첫차:')) {
        key = 'first'; value = p.substring(3).trim();
      } else if (p.startsWith('막차:')) {
        key = 'last'; value = p.substring(3).trim();
      } else if (p.startsWith('운행횟수:')) {
        key = 'trip'; value = p.substring(5).trim();
      }

      if (key != null) {
        flush();
        pending = value;
        pendingKey = key;
      } else if (pending != null) {
        // 쉼표로 잘린 값의 연결 (구형 포맷 호환)
        pending = '$pending, $p';
      }
    }
    flush();

    return _RouteDescription(
      interval: interval,
      company: company,
      firstTm: firstTm,
      lastTm: lastTm,
      tripCount: tripCount,
    );
  }

  Widget _stationTag(String label, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

}

class _RouteDescription {
  final String? interval;
  final String? company;
  final String? firstTm;
  final String? lastTm;
  final String? tripCount;

  const _RouteDescription({
    this.interval,
    this.company,
    this.firstTm,
    this.lastTm,
    this.tripCount,
  });
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StationArrivalsSheet extends StatefulWidget {
  final RouteStation station;
  final String? currentRouteNo;

  const _StationArrivalsSheet({
    required this.station,
    this.currentRouteNo,
  });

  @override
  State<_StationArrivalsSheet> createState() => _StationArrivalsSheetState();
}

class _StationArrivalsSheetState extends State<_StationArrivalsSheet> {
  bool _isLoading = true;
  String? _errorMessage;
  List<BusArrival> _arrivals = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      var arrivals = await ApiService.getStationInfo(widget.station.stationId);
      if (arrivals.isEmpty) {
        final converted =
            await ApiService.getStationIdFromBsId(widget.station.stationId);
        if (converted != null && converted.isNotEmpty) {
          arrivals = await ApiService.getStationInfo(converted);
        }
      }
      if (!mounted) return;
      setState(() {
        _arrivals = arrivals;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '도착 정보를 불러오지 못했습니다.';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final sorted = [..._arrivals]..sort((a, b) {
        if (widget.currentRouteNo != null) {
          if (a.routeNo == widget.currentRouteNo) return -1;
          if (b.routeNo == widget.currentRouteNo) return 1;
        }
        return a.routeNo.compareTo(b.routeNo);
      });

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.station.stationName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '도착 예정 버스',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: colorScheme.error),
                ),
              )
            else if (sorted.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  '도착 예정 버스가 없습니다.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.5,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sorted.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    color: colorScheme.outlineVariant,
                  ),
                  itemBuilder: (_, i) {
                    final a = sorted[i];
                    final isCurrent = a.routeNo == widget.currentRouteNo;
                    return ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        '${a.routeNo}번',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isCurrent
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                      subtitle: a.direction.isNotEmpty
                          ? Text(a.direction,
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant,
                                fontSize: 12,
                              ))
                          : null,
                      trailing: Text(
                        a.getFirstArrivalTimeText(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isCurrent
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
