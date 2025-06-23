import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:daegu_bus_app/screens/alarm_screen.dart';
import 'package:daegu_bus_app/screens/route_map_screen.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/bus_stop.dart';
import '../models/bus_arrival.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../widgets/active_alarm_panel.dart';
import '../widgets/compact_bus_card.dart';
import 'search_screen.dart';
import 'favorites_screen.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../services/alarm_service.dart';
import 'package:daegu_bus_app/models/bus_info.dart';
import 'package:daegu_bus_app/services/alarm_manager.dart';
import 'package:daegu_bus_app/services/settings_service.dart';
import 'package:daegu_bus_app/utils/tts_switcher.dart';
import 'package:flutter/services.dart';
import 'package:daegu_bus_app/services/notification_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  final TextEditingController _searchController = TextEditingController();
  bool _isLoading = true;
  bool _isLoadingNearby = false;
  String? _errorMessage;
  Timer? _refreshTimer;
  Timer? _smartRefreshTimer;
  final List<BusStop> _favoriteStops = [];
  List<BusStop> _nearbyStops = [];
  BusStop? _selectedStop;
  List<BusArrival> _busArrivals = [];
  final Map<String, List<BusArrival>> _stationArrivals = {};

  @override
  void initState() {
    super.initState();
    // AlarmService 초기화
    final alarmService = Provider.of<AlarmService>(context, listen: false);
    alarmService.initialize();
    alarmService.addListener(_onAlarmChanged);
    _initializeData();
  }

  @override
  void dispose() {
    Provider.of<AlarmService>(context, listen: false)
        .removeListener(_onAlarmChanged);
    _searchController.dispose();
    _refreshTimer?.cancel();
    _smartRefreshTimer?.cancel();
    super.dispose();
  }

  void _onAlarmChanged() {
    if (mounted) {
      setState(() {
        // 알람 상태가 변경되면 UI를 다시 빌드합니다.
      });
    }
  }

  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
      _isLoadingNearby = true;
      _errorMessage = null;
    });

    try {
      // 병렬로 데이터 로딩
      await Future.wait([
        _loadFavoriteStops(),
        _loadNearbyStations(),
      ]);

      // 버스 도착 정보 로딩
      await _loadBusArrivals();

      // 주기적 새로고침 설정
      _setupPeriodicRefresh();
    } catch (e) {
      setState(() {
        _errorMessage = '데이터를 불러오는 중 오류가 발생했습니다: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
        _isLoadingNearby = false;
      });
    }
  }

  // 즐겨찾기 불러오기 최적화
  Future<void> _loadFavoriteStops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList('favorites') ?? [];

      if (!mounted) return;

      setState(() {
        _favoriteStops.clear();
        for (var json in favorites) {
          final data = jsonDecode(json);
          final stop = BusStop.fromJson(data);
          _favoriteStops.add(stop);
          debugPrint('Loaded favorite stop: ${stop.id}, ${stop.name}');
        }

        if (_favoriteStops.isNotEmpty && _selectedStop == null) {
          _selectedStop = _favoriteStops.first;
          debugPrint(
              'Selected stop: ${_selectedStop!.id}, ${_selectedStop!.name}');
        }
      });
    } catch (e) {
      debugPrint('Error loading favorites: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage = '즐겨찾기를 불러오는 중 오류가 발생했습니다.';
      });
    }
  }

  // 주변 정류장 로드 최적화
  Future<void> _loadNearbyStations() async {
    setState(() {
      _isLoadingNearby = true;
      _errorMessage = null; // Clear previous errors
    });

    try {
      // 1. 먼저 권한 상태 확인
      final status = await Permission.location.status;
      log('📍 Location permission status: $status');

      if (!status.isGranted) {
        log('📍 Location permission not granted. Requesting...');
        // 권한 요청
        final requestedStatus = await Permission.location.request();
        log('📍 Location permission request result: $requestedStatus');

        if (!requestedStatus.isGranted) {
          // 여전히 권한이 없다면 사용자에게 안내하고 종료
          setState(() {
            _isLoadingNearby = false;
            _nearbyStops = []; // Ensure list is empty
            // _errorMessage = '위치 권한이 필요합니다.'; // Error message handled by UI below
          });
          // Show snackbar for permanent denial
          if (requestedStatus.isPermanentlyDenied && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('위치 권한이 영구적으로 거부되었습니다. 앱 설정에서 권한을 허용해주세요.'),
                action:
                    SnackBarAction(label: '설정 열기', onPressed: openAppSettings),
              ),
            );
          }
          return; // Exit if permission denied
        }
      }

      // 2. 위치 서비스 활성화 확인 (추가)
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        log('📍 Location services disabled.');
        setState(() {
          _isLoadingNearby = false;
          _nearbyStops = [];
          _errorMessage = '위치 서비스가 비활성화되어 있습니다. GPS를 켜주세요.';
        });
        // Optionally prompt user to enable location services
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('위치 서비스(GPS)를 활성화해주세요.')),
          );
        }
        return;
      }

      // 3. 권한과 서비스가 준비되면 주변 정류장 로드 시도
      log('📍 Permissions granted and services enabled. Fetching nearby stations...');
      if (!mounted) return;

      final nearbyStations =
          await LocationService.getNearbyStations(500, context: context);
      log('📍 Found ${nearbyStations.length} nearby stations.');

      if (!mounted) return;

      setState(() {
        _nearbyStops = nearbyStations;
        if (_nearbyStops.isNotEmpty && _selectedStop == null) {
          _selectedStop = _nearbyStops.first;
          // Automatically load arrivals for the first nearby stop if none selected
          _loadBusArrivals();
        }
      });
    } catch (e, stackTrace) {
      // Catch specific exceptions if possible
      log('❌ Error loading nearby stations: $e\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _errorMessage = '주변 정류장을 불러오는 중 오류 발생: ${e.toString()}';
        _nearbyStops = []; // Clear stops on error
      });
    } finally {
      // Ensure loading indicator is always turned off
      if (mounted) {
        setState(() {
          _isLoadingNearby = false;
        });
      }
    }
  }

  // 즐겨찾기 저장
  Future<void> _saveFavoriteStops() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<String> favorites =
          _favoriteStops.map((stop) => jsonEncode(stop.toJson())).toList();
      await prefs.setStringList('favorites', favorites);
    } catch (e) {
      debugPrint('Error saving favorites: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('즐겨찾기 저장에 실패했습니다')),
      );
    }
  }

  // 즐겨찾기 추가/제거
  void _toggleFavorite(BusStop stop) {
    setState(() {
      if (_isStopFavorite(stop)) {
        _favoriteStops.removeWhere((s) => s.id == stop.id);
        if (_selectedStop?.id == stop.id) {
          _selectedStop =
              _favoriteStops.isNotEmpty ? _favoriteStops.first : null;
          if (_selectedStop != null) {
            _loadBusArrivals();
          } else {
            _busArrivals = [];
          }
        }
      } else {
        _favoriteStops.add(stop.copyWith(isFavorite: true));
      }
      _saveFavoriteStops();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isStopFavorite(stop)
              ? '${stop.name} 정류장이 즐겨찾기에 추가되었습니다'
              : '${stop.name} 정류장이 즐겨찾기에서 제거되었습니다',
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  bool _isStopFavorite(BusStop stop) {
    return _favoriteStops.any((s) => s.id == stop.id);
  }

  // 버스 도착 정보 로드
  Future<void> _loadBusArrivals() async {
    if (_nearbyStops.isEmpty && _favoriteStops.isEmpty) return;

    debugPrint('🔍 버스 도착 정보 로드 시작');

    if (_selectedStop == null) {
      debugPrint('❌ 선택된 정류장이 없음');
      return;
    }

    final String busStationId = _selectedStop!.stationId ?? _selectedStop!.id;
    debugPrint(
        '📌 선택된 정류장: ${_selectedStop!.name} (id: ${_selectedStop!.id}, stationId: $busStationId)');

    try {
      // 1. 캐시된 데이터가 있으면 즉시 표시 (빠른 반응)
      final cachedData = _stationArrivals[_selectedStop!.id];
      if (cachedData != null && cachedData.isNotEmpty) {
        debugPrint('⚡ 캐시된 데이터 즉시 표시: ${cachedData.length}개 버스');
        setState(() {
          _busArrivals = cachedData;
          _isLoading = false;
          _errorMessage = null;
        });
      } else {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      // 2. 백그라운드에서 최신 데이터 로드 (선택된 정류장 우선)
      _loadSelectedStationData(busStationId);

      // 3. 다른 정류장들은 백그라운드에서 병렬 처리
      _loadOtherStationsInBackground();
    } catch (e) {
      debugPrint('❌ 버스 도착 정보 로딩 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '버스 도착 정보를 불러오지 못했습니다: $e';
        });
      }
    }
  }

  Future<void> _loadSelectedStationData(String busStationId) async {
    try {
      debugPrint('🚌 선택된 정류장의 최신 정보 로드 중: $busStationId');
      final stopArrivals = await ApiService.getStationInfo(busStationId);
      debugPrint('✅ 최신 정보 로드 완료: ${stopArrivals.length}개 버스 발견');

      if (mounted && _selectedStop != null) {
        setState(() {
          _stationArrivals[_selectedStop!.id] = stopArrivals;
          _busArrivals = stopArrivals;
          _isLoading = false;
          debugPrint('🔄 UI 업데이트: ${_busArrivals.length}개 버스 도착 정보 설정');
        });
      }
    } catch (e) {
      debugPrint('❌ 선택된 정류장 데이터 로딩 오류: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = '버스 도착 정보를 불러오지 못했습니다: $e';
        });
      }
    }
  }

  void _loadOtherStationsInBackground() {
    Future.microtask(() async {
      final allStops = [..._nearbyStops, ..._favoriteStops];
      final otherStops = allStops
          .where(
              (stop) => _selectedStop == null || stop.id != _selectedStop!.id)
          .toList();

      // 배치 크기로 나누어 처리 (한 번에 5개씩)
      const batchSize = 5;
      for (int i = 0; i < otherStops.length; i += batchSize) {
        final batch = otherStops.skip(i).take(batchSize);

        // 배치 내에서는 병렬 처리
        await Future.wait(batch.map((stop) async {
          try {
            final stationId = stop.stationId ?? stop.id;
            if (stationId.isNotEmpty) {
              final arrivals = await ApiService.getStationInfo(stationId);
              if (mounted) {
                setState(() {
                  _stationArrivals[stop.id] = arrivals;
                });
              }
            }
          } catch (e) {
            debugPrint('${stop.id} 백그라운드 로딩 오류: $e');
            if (mounted) {
              setState(() {
                _stationArrivals[stop.id] = <BusArrival>[];
              });
            }
          }
        }));

        // 배치 간 짧은 지연으로 UI 블로킹 방지
        await Future.delayed(const Duration(milliseconds: 50));
      }

      // 최종 상태 확인
      if (mounted && _selectedStop != null) {
        debugPrint('📊 최종 버스 도착 정보: ${_busArrivals.length}개');
        debugPrint('📋 전체 정류장 캐시: ${_stationArrivals.keys.length}개 정류장');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const ActiveAlarmPanel(),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildBody() {
    if (_currentIndex == 0) return _buildNearbyTab();
    if (_currentIndex == 1) return _buildRouteMapTab();
    if (_currentIndex == 2) return _buildFavoritesTab();
    return _buildAlarmTab();
  }

  Widget _buildNearbyTab() {
    return RefreshIndicator(
      onRefresh: _initializeData,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () async {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const SearchScreen()),
                    );
                    if (result != null && result is BusStop) {
                      setState(() => _selectedStop = result);
                      _loadBusArrivals();
                    }
                  },
                ),
              ),
            ),
          ),
          _buildStopSelectionList('주변 정류장', _nearbyStops, _isLoadingNearby),
          _buildStopSelectionList('즐겨찾는 정류장', _favoriteStops, false),
          if (_selectedStop != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        _isStopFavorite(_selectedStop!)
                            ? Icons.star
                            : Icons.star_border,
                        color: _isStopFavorite(_selectedStop!)
                            ? Colors.amber
                            : Colors.grey,
                      ),
                      onPressed: () => _toggleFavorite(_selectedStop!),
                      tooltip: _isStopFavorite(_selectedStop!)
                          ? '즐겨찾기 제거'
                          : '즐겨찾기 추가',
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_selectedStop!.name} 도착 정보',
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (_isLoading)
            const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()))
          else if (_errorMessage != null)
            SliverFillRemaining(child: Center(child: Text(_errorMessage!)))
          else if (_busArrivals.isEmpty)
            const SliverFillRemaining(
                child: Center(child: Text('도착 예정 버스가 없습니다.')))
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final arrival = _busArrivals[index];
                  return CompactBusCard(
                    busArrival: arrival,
                    stationId: _selectedStop!.id,
                    stationName: _selectedStop!.name,
                    onTap: () => _showBusDetailModal(arrival),
                  );
                },
                childCount: _busArrivals.length,
              ),
            ),
        ],
      ),
    );
  }

  SliverToBoxAdapter _buildStopSelectionList(
      String title, List<BusStop> stops, bool isLoading) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          if (isLoading)
            const Center(child: CircularProgressIndicator())
          else if (stops.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text('$title이 없습니다.'),
            )
          else
            SizedBox(
              height: 90,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: stops.length,
                itemBuilder: (context, index) {
                  final stop = stops[index];
                  final showDistance = title == '주변 정류장';
                  return StopCard(
                    stop: stop,
                    isSelected: _selectedStop?.id == stop.id,
                    onTap: () {
                      setState(() => _selectedStop = stop);
                      _loadBusArrivals();
                    },
                    showDistance: showDistance,
                    distanceText:
                        showDistance ? _formatDistance(stop.distance) : null,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRouteMapTab() {
    return const RouteMapScreen();
  }

  Widget _buildFavoritesTab() {
    return FavoritesScreen(
      favoriteStops: _favoriteStops,
      onStopSelected: (stop) {
        setState(() {
          _currentIndex = 0; // 홈 탭으로 이동
          _selectedStop = stop;
        });
        _loadBusArrivals();
      },
      onFavoriteToggle: _toggleFavorite,
    );
  }

  Widget _buildAlarmTab() {
    return const AlarmScreen();
  }

  String _formatDistance(double? distance) {
    if (distance == null) return '';
    return distance < 1000
        ? '${distance.round()}m'
        : '${(distance / 1000).toStringAsFixed(1)}km';
  }

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      items: const <BottomNavigationBarItem>[
        BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: '홈',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.map_outlined),
          activeIcon: Icon(Icons.map),
          label: '노선도',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.favorite_outline),
          activeIcon: Icon(Icons.favorite),
          label: '즐겨찾기',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.alarm_outlined),
          activeIcon: Icon(Icons.alarm),
          label: '알람',
        ),
      ],
      currentIndex: _currentIndex,
      selectedItemColor: Theme.of(context).primaryColor,
      unselectedItemColor: Colors.grey,
      onTap: (index) => setState(() => _currentIndex = index),
      type: BottomNavigationBarType.fixed,
    );
  }

  Future<void> _startNativeTracking(
      String busNo, String stationName, String routeId) async {
    try {
      const platform = MethodChannel('com.example.daegu_bus_app/notification');
      await platform.invokeMethod('startBusTrackingService', {
        'busNo': busNo,
        'stationName': stationName,
        'routeId': routeId,
      });
      log('🔔 ✅ 네이티브 추적 시작 요청 완료');
    } catch (e) {
      log('❌ [ERROR] 네이티브 추적 시작 실패: $e');
      rethrow;
    }
  }

  Future<void> _stopSpecificNativeTracking(
      String busNo, String stationName, String routeId) async {
    try {
      const platform = MethodChannel('com.example.daegu_bus_app/notification');
      await platform.invokeMethod('stopSpecificTracking', {
        'busNo': busNo,
        'routeId': routeId,
        'stationName': stationName,
      });
      log('🔔 ✅ 네이티브 특정 추적 중지 요청 완료');
    } catch (e) {
      log('❌ [ERROR] 네이티브 특정 추적 중지 실패: $e');
    }
  }

  Future<void> _handleBoardingAlarm(
      BusArrival busArrival, BuildContext modalContext) async {
    if (_selectedStop == null || busArrival.busInfoList.isEmpty) return;

    final alarmService = Provider.of<AlarmService>(context, listen: false);
    final firstBus = busArrival.busInfoList.first;
    final routeId = busArrival.routeId;
    final stationId = _selectedStop!.id;
    final wincId = _selectedStop!.wincId ?? '';
    final busNo = busArrival.routeNo;
    final stationName = _selectedStop!.name;
    final remainingMinutes = firstBus.getRemainingMinutes();

    final hasAlarm = alarmService.hasAlarm(busNo, stationName, routeId);

    Navigator.pop(modalContext);

    try {
      if (hasAlarm) {
        await _stopSpecificNativeTracking(busNo, stationName, routeId);
        await AlarmManager.cancelAlarm(
            busNo: busNo, stationName: stationName, routeId: routeId);
        await alarmService.cancelAlarmByRoute(busNo, stationName, routeId);
        await TtsSwitcher.stopTtsTracking(busNo);
        await alarmService.refreshAlarms();

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('승차 알람이 취소되었습니다.')),
        );
      } else {
        if (remainingMinutes <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('이미 도착했거나 운행이 종료된 버스입니다.')),
          );
          return;
        }

        for (var alarm in [...alarmService.activeAlarms]) {
          if (alarm.stationName == stationName) {
            await alarmService.cancelAlarmByRoute(
                alarm.busNo, alarm.stationName, alarm.routeId);
            await TtsSwitcher.stopTtsTracking(alarm.busNo);
          }
        }

        await AlarmManager.addAlarm(
            busNo: busNo,
            stationName: stationName,
            routeId: routeId,
            wincId: wincId);
        await _startNativeTracking(busNo, stationName, routeId);

        bool success = await alarmService.setOneTimeAlarm(
          busNo,
          stationName,
          remainingMinutes,
          routeId: routeId,
          useTTS: true,
          isImmediateAlarm: true,
          currentStation: firstBus.currentStation,
        );

        if (success) {
          await alarmService.startBusMonitoringService(
            stationId: stationId,
            stationName: stationName,
            routeId: routeId,
            busNo: busNo,
          );

          final settings = Provider.of<SettingsService>(context, listen: false);
          if (settings.useTts) {
            TtsSwitcher.startTtsTracking(
              routeId: routeId,
              stationId: stationId,
              busNo: busNo,
              stationName: stationName,
              remainingMinutes: remainingMinutes,
            );
          }
          await alarmService.refreshAlarms();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('승차 알람이 설정되었습니다.')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('승차 알람 설정에 실패했습니다.')),
          );
        }
      }
    } catch (e) {
      log('알람 처리 중 오류: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('알람 처리 중 오류가 발생했습니다: $e')),
      );
    }
  }

  void _showBusDetailModal(BusArrival busArrival) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        final firstBus = busArrival.busInfoList.isNotEmpty
            ? busArrival.busInfoList[0]
            : null;
        final secondBus = busArrival.busInfoList.length > 1
            ? busArrival.busInfoList[1]
            : null;

        return StatefulBuilder(
            builder: (BuildContext context, StateSetter setModalState) {
          final alarmService = Provider.of<AlarmService>(context);
          final hasAlarm = _selectedStop != null &&
              alarmService.hasAlarm(
                  busArrival.routeNo, _selectedStop!.name, busArrival.routeId);

          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${busArrival.routeNo}번 버스 상세 정보',
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(modalContext),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (firstBus != null)
                  _buildBusDetailRow(firstBus, isFirst: true),
                if (secondBus != null) ...[
                  const Divider(height: 24, thickness: 1),
                  _buildBusDetailRow(secondBus, isFirst: false),
                ],
                const SizedBox(height: 24),
                if (firstBus != null && !firstBus.isOutOfService)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: Icon(hasAlarm
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_active_outlined),
                      label: Text(hasAlarm ? '승차 알람 해제' : '승차 알람 설정'),
                      onPressed: () =>
                          _handleBoardingAlarm(busArrival, modalContext),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: hasAlarm
                            ? Colors.redAccent
                            : Theme.of(context).primaryColor,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        });
      },
    );
  }

  Widget _buildBusDetailRow(BusInfo busInfo, {required bool isFirst}) {
    final remainingMinutes = busInfo.getRemainingMinutes();
    String arrivalTimeText;
    Color arrivalTextColor;

    if (busInfo.isOutOfService) {
      arrivalTimeText = '운행종료';
      arrivalTextColor = Colors.grey;
    } else if (remainingMinutes <= 0) {
      arrivalTimeText = '곧 도착';
      arrivalTextColor = Colors.red;
    } else {
      arrivalTimeText = '$remainingMinutes분';
      arrivalTextColor =
          remainingMinutes <= 3 ? Colors.red : Theme.of(context).primaryColor;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isFirst ? '이번 버스' : '다음 버스',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    busInfo.currentStation,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    busInfo.remainingStops,
                    style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Text(
              arrivalTimeText,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: arrivalTextColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _setupPeriodicRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_selectedStop != null) {
        _loadBusArrivals();
      }
    });
  }
}

class StopCard extends StatelessWidget {
  final BusStop stop;
  final bool isSelected;
  final VoidCallback onTap;
  final bool showDistance;
  final String? distanceText;

  const StopCard({
    super.key,
    required this.stop,
    required this.isSelected,
    required this.onTap,
    this.showDistance = false,
    this.distanceText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 8),
      child: Card(
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(
            color: isSelected ? Colors.blue.shade300 : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  stop.name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.blue.shade700 : Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (showDistance &&
                    distanceText != null &&
                    distanceText!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      distanceText!,
                      style: TextStyle(color: Colors.grey[600], fontSize: 11),
                    ),
                  ),
                const SizedBox(height: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
