import 'package:flutter/material.dart';
import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';
import '../services/api_service.dart';
import '../widgets/compact_bus_card.dart';
import '../widgets/station_item.dart';
import '../widgets/bus_arrival_list.dart';

class FavoritesScreen extends StatefulWidget {
  final List<BusStop> favoriteStops;
  final Function(BusStop) onStopSelected;
  final Function(BusStop) onFavoriteToggle;

  const FavoritesScreen({
    super.key,
    required this.favoriteStops,
    required this.onStopSelected,
    required this.onFavoriteToggle,
  });

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  final Map<String, List<BusArrival>> _stationArrivals = {};
  final Map<String, bool> _isLoadingMap = {};
  final Map<String, String?> _errorMap = {};
  BusStop? _selectedStop;

  @override
  void initState() {
    super.initState();
    if (widget.favoriteStops.isNotEmpty) {
      _loadAllFavoriteArrivals();
    }
  }

  // 모든 즐겨찾기 정류장의 도착 정보 로드
  Future<void> _loadAllFavoriteArrivals() async {
    for (final stop in widget.favoriteStops) {
      _loadStationArrivals(stop);
    }
  }

  // 특정 정류장의 도착 정보 로드
  Future<void> _loadStationArrivals(BusStop station) async {
    setState(() {
      _isLoadingMap[station.id] = true;
      _errorMap[station.id] = null;
    });

    try {
      final arrivals = await ApiService.getStationInfo(station.id);
      if (!mounted) return;

      setState(() {
        _stationArrivals[station.id] = arrivals;
        _isLoadingMap[station.id] = false;
      });
    } catch (e) {
      debugPrint('Error loading arrivals for station ${station.id}: $e');
      if (!mounted) return;

      setState(() {
        _errorMap[station.id] = '도착 정보를 불러오지 못했습니다';
        _isLoadingMap[station.id] = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.favoriteStops.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star_border,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              '즐겨찾는 정류장이 없습니다',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '정류장 검색 후 별표 아이콘을 눌러 추가하세요',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.favoriteStops.length,
      itemBuilder: (context, index) {
        final station = widget.favoriteStops[index];
        final isSelected = _selectedStop?.id == station.id;
        final stationArrivals = _stationArrivals[station.id] ?? [];
        final isLoading = _isLoadingMap[station.id] ?? false;
        final error = _errorMap[station.id];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 정류장 정보
            StationItem(
              station: station,
              isSelected: isSelected,
              onTap: () {
                setState(() {
                  if (_selectedStop?.id == station.id) {
                    _selectedStop = null; // 선택 해제
                  } else {
                    _selectedStop = station;
                    if (stationArrivals.isEmpty && !isLoading) {
                      _loadStationArrivals(station);
                    }
                  }
                });
                widget.onStopSelected(station);
              },
              onFavoriteToggle: () => widget.onFavoriteToggle(station),
            ),

            // 선택된 정류장의 버스 도착 정보 - 스크롤 가능하게 수정
            if (isSelected)
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 8, bottom: 16),
                child: SizedBox(
                  height: 300, // 고정 높이 설정 - 스크롤 가능하게
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isLoading)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      else if (error != null)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              children: [
                                Icon(Icons.error_outline,
                                    size: 32, color: Colors.red[300]),
                                const SizedBox(height: 8),
                                Text(
                                  error,
                                  style: TextStyle(color: Colors.red[700]),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      _loadStationArrivals(station),
                                  child: const Text('다시 시도'),
                                ),
                              ],
                            ),
                          ),
                        )
                      else if (stationArrivals.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: Text('도착 예정 버스가 없습니다'),
                          ),
                        )
                      else
                        Expanded(
                          child: Scrollbar(
                            thickness: 6.0,
                            radius: const Radius.circular(10),
                            child: ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              padding: EdgeInsets.zero,
                              itemCount: stationArrivals.length,
                              itemBuilder: (context, idx) {
                                final busArrival = stationArrivals[idx];
                                return CompactBusCard(
                                  busArrival: busArrival,
                                  onTap: () {
                                    // 버스 상세 정보 또는 알람 설정
                                    _showBusDetailModal(
                                        context, station, busArrival);
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            if (index < widget.favoriteStops.length - 1)
              const Divider(height: 24),
          ],
        );
      },
    );
  }

  void _showBusDetailModal(
      BuildContext context, BusStop station, BusArrival busArrival) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.4, // 화면의 60%로 제한
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더 (모달 닫기 버튼 포함)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${busArrival.routeNo}번 버스',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              Text(
                '${station.name} → ${busArrival.destination}',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 16),

              // 버스 도착 정보 목록 (스크롤 가능하게)
              Expanded(
                child: BusArrivalList(
                  arrivals: busArrival.buses.length > 1
                      ? busArrival.buses
                          .map((bus) => BusArrival(
                              routeNo: busArrival.routeNo,
                              destination: busArrival.destination,
                              routeId: busArrival.routeId,
                              buses: [bus]))
                          .toList()
                      : [busArrival],
                  station: station,
                  onTap: (arrival) {
                    // 필요한 경우 추가 동작 정의
                  },
                  onAlarmSet: (arrival) {
                    // 알람 설정 로직
                  },
                ),
              ),

              const SizedBox(height: 16),

              // 알람 설정 버튼
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // 알람 설정 로직
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.notifications_active),
                  label: const Text('도착 알림 설정'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
