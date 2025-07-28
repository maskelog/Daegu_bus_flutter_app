import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../models/bus_stop.dart';
import '../services/location_service.dart';

class StationLoadingWidget extends StatefulWidget {
  final Function(List<BusStop>) onNearbyStopsLoaded;
  final Function(List<BusStop>) onFavoriteStopsLoaded;
  final Function(BusStop?) onSelectedStopChanged;
  final BusStop? selectedStop;
  final List<BusStop> favoriteStops;

  const StationLoadingWidget({
    super.key,
    required this.onNearbyStopsLoaded,
    required this.onFavoriteStopsLoaded,
    required this.onSelectedStopChanged,
    required this.selectedStop,
    required this.favoriteStops,
  });

  @override
  State<StationLoadingWidget> createState() => _StationLoadingWidgetState();
}

class _StationLoadingWidgetState extends State<StationLoadingWidget> {
  bool _isLoadingNearby = false;
  bool _isLoadingFavorites = false;
  String? _errorMessage;
  List<BusStop> _nearbyStops = [];

  @override
  void initState() {
    super.initState();
    _initializeStations();
  }

  Future<void> _initializeStations() async {
    await Future.wait([
      _loadFavoriteStops(),
      _loadNearbyStations(),
    ]);
  }

  Future<void> _loadFavoriteStops() async {
    setState(() {
      _isLoadingFavorites = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList('favorites') ?? [];

      if (!mounted) return;

      final favoriteStops = <BusStop>[];
      for (var json in favorites) {
        final data = jsonDecode(json);
        final stop = BusStop.fromJson(data);
        favoriteStops.add(stop);
      }

      widget.onFavoriteStopsLoaded(favoriteStops);

      // 즐겨찾기가 있고 선택된 정류장이 없으면 첫 번째 즐겨찾기 선택
      if (favoriteStops.isNotEmpty && widget.selectedStop == null) {
        widget.onSelectedStopChanged(favoriteStops.first);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorMessage = '즐겨찾기를 불러오는 중 오류가 발생했습니다.');
    } finally {
      if (mounted) {
        setState(() => _isLoadingFavorites = false);
      }
    }
  }

  Future<void> _loadNearbyStations() async {
    setState(() {
      _isLoadingNearby = true;
      _errorMessage = null;
    });

    try {
      final status = await Permission.location.status;
      if (!status.isGranted) {
        final requestedStatus = await Permission.location.request();
        if (!requestedStatus.isGranted) {
          setState(() {
            _isLoadingNearby = false;
            _nearbyStops = [];
          });
          if (requestedStatus.isPermanentlyDenied && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('위치 권한이 영구적으로 거부되었습니다. 앱 설정에서 허용해주세요.'),
                action:
                    SnackBarAction(label: '설정 열기', onPressed: openAppSettings),
              ),
            );
          }
          return;
        }
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() {
          _isLoadingNearby = false;
          _nearbyStops = [];
          _errorMessage = '위치 서비스가 비활성화되어 있습니다. GPS를 켜주세요.';
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 서비스(GPS)를 활성화해주세요.')),
          );
        }
        return;
      }

      if (!mounted) return;
      final nearbyStations =
          await LocationService.getNearbyStations(500, context: context);

      if (!mounted) return;
      setState(() {
        _nearbyStops = nearbyStations;
      });

      widget.onNearbyStopsLoaded(nearbyStations);

      // 주변 정류장이 있고 선택된 정류장이 없으면 첫 번째 주변 정류장 선택
      if (nearbyStations.isNotEmpty && widget.selectedStop == null) {
        widget.onSelectedStopChanged(nearbyStations.first);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '주변 정류장을 불러오는 중 오류 발생: ${e.toString()}';
          _nearbyStops = [];
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingNearby = false);
      }
    }
  }

  String _formatDistance(double? distance) {
    if (distance == null) return '';
    return distance < 1000
        ? '${distance.round()}m'
        : '${(distance / 1000).toStringAsFixed(1)}km';
  }

  List<BusStop> _getFilteredNearbyStops() {
    final favoriteStopIds = widget.favoriteStops.map((stop) => stop.id).toSet();
    return _nearbyStops
        .where((stop) => !favoriteStopIds.contains(stop.id))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStopSelectionButtons(
          '주변 정류장',
          _getFilteredNearbyStops(),
          isLoading: _isLoadingNearby,
          isNearby: true,
        ),
        _buildStopSelectionButtons(
          '즐겨찾는 정류장',
          widget.favoriteStops,
          isLoading: _isLoadingFavorites,
          isNearby: false,
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _errorMessage!,
              style: TextStyle(color: colorScheme.error),
            ),
          ),
      ],
    );
  }

  Widget _buildStopSelectionButtons(
    String title,
    List<BusStop> stops, {
    bool isLoading = false,
    bool isNearby = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 16, vertical: 4), // vertical 패딩 축소
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
              fontSize: 16, // 폰트 크기 축소
            ),
          ),
          const SizedBox(height: 4), // 간격 축소
          if (isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4), // 패딩 축소
              child: Center(child: CircularProgressIndicator()),
            )
          else if (stops.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4), // 패딩 축소
              child: Text(
                isNearby ? '주변 정류장이 없습니다.' : '즐겨찾는 정류장이 없습니다.',
                style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 13), // 폰트 크기 축소
              ),
            )
          else if (isNearby)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start, // 왼쪽 정렬 강제
                  crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬 강제
                  children: stops.map((stop) {
                    final isSelected = widget.selectedStop?.id == stop.id;
                    final label =
                        '${stop.name} - ${_formatDistance(stop.distance)}';
                    return Padding(
                      padding: const EdgeInsets.only(right: 6), // 간격 축소
                      child: ChoiceChip(
                        label: Text(
                          label,
                          style: TextStyle(
                            color: isSelected
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12, // 폰트 크기 축소
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (_) {
                          widget.onSelectedStopChanged(stop);
                        },
                        selectedColor: colorScheme.primary,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        side: BorderSide(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant,
                          width: isSelected ? 2 : 1,
                        ),
                        labelPadding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2), // 패딩 축소
                        padding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 1), // 패딩 축소
                        showCheckmark: false, // 체크 아이콘 제거
                      ),
                    );
                  }).toList(),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start, // 왼쪽 정렬 강제
                  crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬 강제
                  children: stops.map((stop) {
                    final isSelected = widget.selectedStop?.id == stop.id;
                    return Padding(
                      padding: const EdgeInsets.only(right: 6), // 간격 축소
                      child: ChoiceChip(
                        label: Text(
                          stop.name,
                          style: TextStyle(
                            color: isSelected
                                ? colorScheme.onPrimary
                                : colorScheme.onSurface,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 12, // 폰트 크기 축소
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (_) {
                          widget.onSelectedStopChanged(stop);
                        },
                        selectedColor: colorScheme.primary,
                        backgroundColor: colorScheme.surfaceContainerHighest,
                        side: BorderSide(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outlineVariant,
                          width: isSelected ? 2 : 1,
                        ),
                        labelPadding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2), // 패딩 축소
                        padding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 1), // 패딩 축소
                        showCheckmark: false, // 체크 아이콘 제거
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> refresh() async {
    await _initializeStations();
  }
}
