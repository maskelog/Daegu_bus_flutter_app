import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import '../services/api_service.dart';
import '../services/bus_api_service.dart';
import '../models/bus_stop.dart';
import '../models/route_station.dart';
import '../models/bus_arrival.dart';
import '../models/bus_info.dart';
import 'map_widgets.dart';
import '../utils/debouncer.dart';

const String _kakaoJsApiKeyFromDefine = String.fromEnvironment(
  'KAKAO_JS_API_KEY',
  defaultValue: '',
);
const String _kakaoNativeAppKeyFromDefine = String.fromEnvironment(
  'KAKAO_NATIVE_APP_KEY',
  defaultValue: '',
);

bool _looksLikeKakaoJsApiKey(String value) {
  final key = value.trim();
  if (key.isEmpty) return false;
  if (key.toLowerCase().contains('your_')) return false;
  if (key.length < 20) return false;
  return true;
}

class _TimedCacheEntry<T> {
  final T value;
  final DateTime timestamp;

  _TimedCacheEntry(this.value, this.timestamp);

  bool isExpired(Duration ttl) {
    return DateTime.now().difference(timestamp) > ttl;
  }
}

class MapScreen extends StatefulWidget {
  final String? routeId;
  final List<RouteStation>? routeStations;
  final List<BusStop>? initialNearbyStations; // 홈화면에서 전달받은 주변 정류장

  const MapScreen({
    super.key,
    this.routeId,
    this.routeStations,
    this.initialNearbyStations, // 새로운 매개변수 추가
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const Duration _nearbyCacheTtl = Duration(seconds: 90);
  static const Duration _stationInfoCacheTtl = Duration(seconds: 45);
  static const Duration _stationInfoRefreshGap = Duration(seconds: 8);

  late WebViewController _webViewController;
  Position? _currentPosition;
  List<BusStop> _nearbyStations = [];
  List<RouteStation> _routeStations = [];
  Timer? _busPositionTimer;
  Timer? _searchThrottleTimer;
  final Debouncer _mapSearchDebouncer = Debouncer(delay: const Duration(milliseconds: 350));
  final Map<String, Future<List<BusStop>>> _nearbyInFlight = {};
  final Map<String, _TimedCacheEntry<List<BusStop>>> _nearbyCache = {};
  final Map<String, Future<List<BusArrival>>> _stationInfoInFlight = {};
  final Map<String, _TimedCacheEntry<List<BusArrival>>> _stationInfoCache = {};
  final Map<String, String?> _stationIdCache = {};
  final Map<String, DateTime> _stationInfoLastRequestedAt = {};
  int _nearbyRequestSequence = 0;
  int _stationInfoRequestSequence = 0;
  bool _isLoading = true;
  bool _mapReady = false;
  String? _errorMessage;
  String? _htmlContent;

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    try {
      // HTML 템플릿 로드
      await _loadHtmlTemplate();

      // 현재 위치 가져오기
      _currentPosition = await _getCurrentPosition();

      // 노선 정류장이 전달된 경우 사용
      if (widget.routeStations != null) {
        _routeStations = widget.routeStations!;
      }

      // 홈화면에서 전달받은 주변 정류장이 있으면 사용
      debugPrint(
          '지도 화면 초기화 - initialNearbyStations: ${widget.initialNearbyStations?.length ?? 0}개');
      if (widget.initialNearbyStations != null &&
          widget.initialNearbyStations!.isNotEmpty) {
        _nearbyStations = widget.initialNearbyStations!;
        debugPrint('홈화면에서 전달받은 주변 정류장: ${_nearbyStations.length}개');
        for (final station in _nearbyStations) {
          debugPrint(
              '  - ${station.name} (${station.latitude}, ${station.longitude})');
        }
      } else {
        debugPrint('홈화면에서 주변 정류장 정보를 받지 못했습니다. 직접 검색을 시작합니다.');
        // 주변 정류장 검색
        await _loadNearbyStations();
      }

      // WebView 초기화
      _initializeWebView();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '지도 초기화 중 오류가 발생했습니다: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadHtmlTemplate() async {
    try {
      final String htmlTemplate =
          await rootBundle.loadString('assets/kakao_map.html');

      final String? kakaoApiKey = _resolveKakaoApiKey();

      if (kakaoApiKey == null || kakaoApiKey.isEmpty) {
        throw Exception('KAKAO_JS_API_KEY가 설정되지 않았습니다.');
      }

      if (!_looksLikeKakaoJsApiKey(kakaoApiKey)) {
        throw Exception('KAKAO_JS_API_KEY 형식이 유효하지 않습니다.');
      }

      _htmlContent = htmlTemplate.replaceAll('YOUR_KAKAO_API_KEY', kakaoApiKey);
    } catch (e) {
      debugPrint('HTML 템플릿 로드 오류: $e');
      throw Exception('HTML 템플릿을 로드할 수 없습니다: $e');
    }
  }

  String? _resolveKakaoApiKey() {
    final fromDotEnv = dotenv.env['KAKAO_JS_API_KEY']?.trim();
    if (fromDotEnv != null && fromDotEnv.isNotEmpty) {
      return _looksLikeKakaoJsApiKey(fromDotEnv) ? fromDotEnv : null;
    }

    final fromDartDefine = _kakaoJsApiKeyFromDefine.trim();
    if (_looksLikeKakaoJsApiKey(fromDartDefine)) {
      return fromDartDefine;
    }

    final fromNativeDotEnv = dotenv.env['KAKAO_NATIVE_APP_KEY']?.trim();
    if (_looksLikeKakaoJsApiKey(fromNativeDotEnv ?? '')) {
      debugPrint(
        '⚠️ KAKAO_JS_API_KEY가 없어 KAKAO_NATIVE_APP_KEY로 폴백합니다. '
        'JS 용 키가 있는 경우 KAKAO_JS_API_KEY로 교체하세요.',
      );
      return fromNativeDotEnv;
    }

    final fromNativeDefine = _kakaoNativeAppKeyFromDefine.trim();
    if (_looksLikeKakaoJsApiKey(fromNativeDefine)) {
      debugPrint(
        '⚠️ KAKAO_JS_API_KEY가 없어 KAKAO_NATIVE_APP_KEY(--dart-define)로 폴백합니다.',
      );
      return fromNativeDefine;
    }

    return null;
  }


  Future<Position> _getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('위치 서비스가 비활성화되어 있습니다.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('위치 권한이 거부되었습니다.');
      }
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception('위치 권한이 영구적으로 거부되었습니다.');
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<void> _loadNearbyStations() async {
    if (_currentPosition == null) {
      debugPrint('현재 위치가 없어서 주변 정류장을 로드할 수 없습니다');
      return;
    }

    await _searchNearbyStationsFromCoords(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      isAuto: true,
      allowFallback: false,
      showMessage: false,
      initialRadius: 2000.0,
    );
  }

  // 카카오맵 API 검색 기능 제거됨

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildBody(),
          // 오른쪽 하단에 버튼들 배치
          if (_currentPosition != null)
            MapFloatingButtons(
              onSearchNearby: _searchNearbyStations,
              onMoveToCurrent: _moveToCurrentLocation,
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return MapLoadingView(hasPosition: _currentPosition != null);
    }

    if (_errorMessage != null) {
      return MapErrorView(
        message: _errorMessage!,
        onRetry: () {
          setState(() {
            _isLoading = true;
            _errorMessage = null;
          });
          _initializeMap();
        },
      );
    }

    return _buildKakaoMap();
  }

  Widget _buildKakaoMap() {
    if (_htmlContent == null) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return WebViewWidget(
      controller: _webViewController,
    );
  }

  void _initializeWebView() {
    debugPrint('WebView 초기화 시작');
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('페이지 로드 시작: $url');
          },
          onPageFinished: (String url) {
            debugPrint('페이지 로드 완료: $url');
            _onMapReady();
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView 오류: ${error.description}');
          },
        ),
      )
      ..addJavaScriptChannel(
        'mapEvent',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('지도 이벤트 수신: ${message.message}');
          _handleMapEvent(message.message);
        },
      );

    debugPrint('HTML 콘텐츠 로드 중...');
    _webViewController.loadHtmlString(_htmlContent!);
  }

  void _onMapReady() {
    debugPrint('지도 준비 완료 이벤트 수신');
    setState(() {
      _mapReady = true;
    });

    // 지도 초기화
    _initializeKakaoMap();

    _searchThrottleTimer?.cancel();
    _searchThrottleTimer = Timer(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      debugPrint('지연 후 마커 추가 시작');
      _addMarkers();
      _scheduleNearbySearch(visibleOnly: false, isAuto: true);
    });

    // 노선 ID가 있으면 실시간 버스 위치 추적 시작
    if (widget.routeId != null) {
      _startBusPositionTracking();
    }
  }

  void _initializeKakaoMap() {
    if (!_mapReady) return;

    final lat = _currentPosition?.latitude ?? 35.8714;
    final lng = _currentPosition?.longitude ?? 128.6014;

    _webViewController.runJavaScript('initMap($lat, $lng, 3);');
  }

  void _scheduleNearbySearch({
    bool visibleOnly = false,
    bool isAuto = true,
  }) {
    final currentPosition = _currentPosition;
    if (currentPosition == null) return;

    _mapSearchDebouncer.call(() {
      _searchNearbyStationsFromCoords(
        currentPosition.latitude,
        currentPosition.longitude,
        isAuto: isAuto,
        allowFallback: !visibleOnly,
        showMessage: !visibleOnly && !isAuto,
        initialRadius: 500.0,
      );
    });
  }

  void _addMarkers() {
    if (!_mapReady) {
      debugPrint('지도가 준비되지 않아서 마커를 추가할 수 없습니다');
      return;
    }

    debugPrint('마커 추가 시작');
    debugPrint('노선 정류장: ${_routeStations.length}개');
    debugPrint('주변 정류장: ${_nearbyStations.length}개');

    // 기존 마커 제거
    _webViewController.runJavaScript('clearMarkers();');

    // 현재 위치 마커 추가 (원본 좌표 사용 - 불필요한 반올림 제거)
    if (_currentPosition != null) {
      final lat = _currentPosition!.latitude;
      final lng = _currentPosition!.longitude;

      debugPrint('현재 위치 마커 추가: $lat, $lng');
      _webViewController.runJavaScript('addCurrentLocationMarker($lat, $lng);');
    }

    // 노선 정류장 마커 추가 (우선순위 높음)
    for (final station in _routeStations) {
      if (station.latitude != null && station.longitude != null) {
        final lat = station.latitude!;
        final lng = station.longitude!;

        debugPrint('노선 정류장 마커 추가: ${station.stationName} ($lat, $lng)');
        _webViewController.runJavaScript(
            'addStationMarker($lat, $lng, ${_toJsString(station.stationName)}, ${_toJsString("route")}, ${station.sequenceNo});');
      }
    }

    // 주변 정류장 마커 추가 (중복 제거)
    final addedCoordinates = <String>{};

    for (final station in _nearbyStations) {
      if (station.latitude != null && station.longitude != null) {
        final coordKey =
            '${station.latitude!.toStringAsFixed(6)},${station.longitude!.toStringAsFixed(6)}';

        // 이미 추가된 좌표인지 확인 (노선 정류장과 중복 방지)
        bool isDuplicate = false;
        for (final routeStation in _routeStations) {
          if (routeStation.latitude != null && routeStation.longitude != null) {
            final routeCoordKey =
                '${routeStation.latitude!.toStringAsFixed(6)},${routeStation.longitude!.toStringAsFixed(6)}';
            if (coordKey == routeCoordKey) {
              isDuplicate = true;
              break;
            }
          }
        }

        if (!isDuplicate && !addedCoordinates.contains(coordKey)) {
          final lat = station.latitude!;
          final lng = station.longitude!;

          debugPrint('주변 정류장 마커 추가: ${station.name} ($lat, $lng)');
          _webViewController.runJavaScript(
              'addStationMarker($lat, $lng, ${_toJsString(station.name)}, ${_toJsString("nearby")}, 0);');
          addedCoordinates.add(coordKey);
        }
      }
    }

    debugPrint(
        '마커 추가 완료 - 총 ${_routeStations.length + addedCoordinates.length}개');
  }

  String _toJsString(Object? value) => jsonEncode(value ?? '');

  String _stationCoordinateCacheKey(double latitude, double longitude, double radiusMeters) {
    return '${latitude.toStringAsFixed(5)}_${longitude.toStringAsFixed(5)}_${radiusMeters.toInt()}';
  }

  double? _toCoordinate(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Future<List<BusStop>> _getNearbyStationsFromCache(
    double latitude,
    double longitude,
    double radiusMeters,
  ) async {
    final cacheKey = _stationCoordinateCacheKey(latitude, longitude, radiusMeters);

    final cached = _nearbyCache[cacheKey];
    if (cached != null && !cached.isExpired(_nearbyCacheTtl)) {
      return cached.value;
    }

    final existing = _nearbyInFlight[cacheKey];
    if (existing != null) {
      return existing;
    }

    final future = ApiService.findNearbyStations(
      latitude,
      longitude,
      radiusMeters: radiusMeters,
    ).then((stations) {
      _nearbyCache[cacheKey] = _TimedCacheEntry(stations, DateTime.now());
      return stations;
    }).whenComplete(() {
      _nearbyInFlight.remove(cacheKey);
    });

    _nearbyInFlight[cacheKey] = future;
    return future;
  }

  Future<List<BusStop>> _getNearbyStationsWithFallback(
    double latitude,
    double longitude, {
    bool allowFallback = false,
    double initialRadius = 500.0,
  }) async {
    final searchRadii = <double>[initialRadius];
    if (allowFallback) {
      if (!searchRadii.contains(1000.0)) searchRadii.add(1000.0);
      if (!searchRadii.contains(2000.0)) searchRadii.add(2000.0);
    }

    for (final radius in searchRadii) {
      final stations = await _getNearbyStationsFromCache(
        latitude,
        longitude,
        radius,
      );
      if (stations.isNotEmpty) return stations;
    }
    return const [];
  }

  Future<List<BusArrival>> _getStationInfoFromCache(String stationId) async {
    if (stationId.isEmpty) return [];

    final cache = _stationInfoCache[stationId];
    if (cache != null && !cache.isExpired(_stationInfoCacheTtl)) {
      return cache.value;
    }

    final existing = _stationInfoInFlight[stationId];
    if (existing != null) return existing;

    final lastRequestedAt = _stationInfoLastRequestedAt[stationId];
    if (lastRequestedAt != null &&
        DateTime.now().difference(lastRequestedAt) < _stationInfoRefreshGap) {
      return cache?.value ?? [];
    }

    _stationInfoLastRequestedAt[stationId] = DateTime.now();

    final future = ApiService.getStationInfo(stationId).then((arrivals) {
      _stationInfoCache[stationId] = _TimedCacheEntry(arrivals, DateTime.now());
      return arrivals;
    }).whenComplete(() {
      _stationInfoInFlight.remove(stationId);
    });

    _stationInfoInFlight[stationId] = future;
    return future;
  }

  void _sendStationBusInfoToMap({
    required String stationName,
    required String stationType,
    required String busInfo,
  }) {
    if (!_mapReady) return;
    _webViewController.runJavaScript(
      'updateStationBusInfo(${_toJsString(stationName)}, ${_toJsString(stationType)}, ${_toJsString(busInfo)});',
    );
  }

  void _handleMapEvent(String message) {
    try {
      debugPrint('WebView 원본 메시지: $message');
      final data = jsonDecode(message);
      final type = data['type'];

      debugPrint('WebView 메시지 수신: $type, 데이터: ${data['data']}');

      switch (type) {
        case 'mapReady':
          debugPrint('지도 준비 완료');
          break;
        case 'zoomChanged':
          final lvl = data['data']?['level'];
          final mpp = data['data']?['metersPerPixel'];
          final dpr = data['data']?['dpr'];
          debugPrint(
              '줌 변경: level=$lvl, m/px=${mpp?.toStringAsFixed(3)}, dpr=$dpr');
          break;
        case 'mapMetrics':
          final lvl = data['data']?['level'];
          final mpp = data['data']?['metersPerPixel'];
          final lat = data['data']?['centerLat'];
          final lng = data['data']?['centerLng'];
          final dpr = data['data']?['dpr'];
          debugPrint(
              '맵 메트릭스: level=$lvl, m/px=${mpp?.toStringAsFixed(3)}, center=($lat,$lng), dpr=$dpr');
          break;
        case 'mapError':
          final error = data['data']['error'];
          debugPrint('지도 오류: $error');
          setState(() {
            _errorMessage = '지도 로드 오류: $error';
          });
          break;
        case 'mapClick':
          final lat = data['data']['latitude'];
          final lng = data['data']['longitude'];
          debugPrint('지도 클릭: $lat, $lng');
          // 클릭한 위치 근처에 이미 정류장이 있는지 확인 (예: 100m 이내)
          final nearestStation = _findNearestStation(lat, lng);
          if (nearestStation != null) {
            debugPrint('클릭한 위치 근처에 이미 정류장이 있습니다: ${nearestStation.name}');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('클릭한 위치 근처에 \'${nearestStation.name}\' 정류장이 있습니다.'),
                duration: const Duration(seconds: 2),
              ),
            );
        } else {
          // 근처에 정류장이 없을 때만 API를 통해 검색
          debugPrint('근처에 정류장이 없어 새로 검색합니다.');
          _searchNearbyStationsFromCoords(
            lat,
            lng,
            isAuto: false,
            showMessage: true,
            allowFallback: true,
            initialRadius: 500.0,
          );
        }
        break;
        case 'stationClick':
          final stationData = data['data'];
          debugPrint('정류장 클릭 상세 데이터: $stationData');
          debugPrint(
              '정류장 클릭: ${stationData['name']} (타입: ${stationData['type']})');
          _showStationBusInfo(stationData);
          // 정류장 클릭 시 버스 도착 정보를 HTML로 전달
          _updateStationInfoInMap(stationData);
          break;
        default:
          debugPrint('알 수 없는 메시지 타입: $type');
          break;
      }
    } catch (e) {
      debugPrint('지도 이벤트 처리 오류: $e');
      debugPrint('원본 메시지: $message');
    }
  }

  void _showStationBusInfo(Map<String, dynamic> stationData) {
    final stationName = stationData['name'] as String;
    final stationType = stationData['type'] as String?;
    final latitude = _toCoordinate(stationData['latitude']);
    final longitude = _toCoordinate(stationData['longitude']);

    // 정류장 이름으로 BusStop 객체 찾기
    BusStop? selectedStation;

    // 카카오맵 기본 버스정류장인 경우
    if (stationType == 'kakao') {
      debugPrint('카카오맵 버스정류장 처리: $stationName at ($latitude, $longitude)');

      // 근처 실제 정류장 찾기 시도
      if (latitude != null && longitude != null) {
        final nearestStation = _findNearestStation(latitude, longitude);
        if (nearestStation != null) {
          debugPrint('근처 실제 정류장 발견: ${nearestStation.name}');
          selectedStation = nearestStation;
        } else {
          debugPrint('근처 실제 정류장 없음, 카카오맵 정류장으로 처리');
          // 카카오맵에서 제공한 좌표로 BusStop 객체 생성
          selectedStation = BusStop(
            id: 'kakao_${stationName.hashCode}',
            stationId: 'kakao_station', // 임시 ID
            name: stationName,
            latitude: latitude,
            longitude: longitude,
          );
        }
      }
    } else {
      // 기존 로직: 노선 정류장에서 찾기
      for (final station in _routeStations) {
        if (station.stationName == stationName) {
          selectedStation = BusStop(
            id: station.stationId,
            stationId: station.stationId,
            name: stationName,
            latitude: station.latitude,
            longitude: station.longitude,
          );
          break;
        }
      }

      // 주변 정류장에서 찾기 (더 정확한 매칭)
      if (selectedStation == null) {
        for (final station in _nearbyStations) {
          if (station.name == stationName ||
              (latitude != null &&
                  longitude != null &&
                  station.latitude != null &&
                  station.longitude != null &&
                  _calculateDistance(latitude, longitude, station.latitude!,
                          station.longitude!) <
                      0.01)) {
            selectedStation = station;
            break;
          }
        }
      }
    }

    if (selectedStation != null) {
      debugPrint(
          '정류장 정보 표시: ${selectedStation.name} (ID: ${selectedStation.stationId})');
      // _showBusInfoBottomSheet(selectedStation); // 삭제됨
    } else {
      debugPrint('정류장 정보를 찾을 수 없음: $stationName');

      // 카카오맵 정류장인 경우 특별 처리
      if (stationType == 'kakao') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '$stationName 정류장의 실시간 버스 정보를 찾을 수 없습니다.\n근처 다른 정류장을 이용해주세요.'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: '근처 검색',
              onPressed: () {
                if (latitude != null && longitude != null) {
                  _searchNearbyStationsFromCoords(
                    latitude,
                    longitude,
                    isAuto: false,
                    showMessage: true,
                    allowFallback: true,
                    initialRadius: 500.0,
                  );
                }
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$stationName 정류장 정보를 찾을 수 없습니다.'),
            action: SnackBarAction(
              label: '근처 정류장 검색',
              onPressed: () {
                if (latitude != null && longitude != null) {
                  _searchNearbyStationsFromCoords(
                    latitude,
                    longitude,
                    isAuto: false,
                    showMessage: true,
                    allowFallback: true,
                    initialRadius: 500.0,
                  );
                }
              },
            ),
          ),
        );
      }
    }
  }

  // 좌표 기반으로 가장 가까운 정류장 찾기
  BusStop? _findNearestStation(double lat, double lng) {
    BusStop? nearest;
    double minDistance = double.infinity;

    // 노선 정류장에서 찾기
    for (final station in _routeStations) {
      if (station.latitude != null && station.longitude != null) {
        final distance =
            _calculateDistance(lat, lng, station.latitude!, station.longitude!);
        if (distance < minDistance && distance < 0.1) {
          // 100m 이내
          minDistance = distance;
          nearest = BusStop(
            id: station.stationId,
            stationId: station.stationId,
            name: station.stationName,
            latitude: station.latitude,
            longitude: station.longitude,
          );
        }
      }
    }

    // 주변 정류장에서 찾기
    for (final station in _nearbyStations) {
      if (station.latitude != null && station.longitude != null) {
        final distance =
            _calculateDistance(lat, lng, station.latitude!, station.longitude!);
        if (distance < minDistance && distance < 0.1) {
          // 100m 이내
          minDistance = distance;
          nearest = station;
        }
      }
    }

    return nearest;
  }

  // 두 좌표 간 거리 계산 (km 단위)
  double _calculateDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const double earthRadius = 6371; // 지구 반지름 (km)
    final double dLat = (lat2 - lat1) * (pi / 180);
    final double dLng = (lng2 - lng1) * (pi / 180);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) *
            cos(lat2 * (pi / 180)) *
            sin(dLng / 2) *
            sin(dLng / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  // 좌표 기반 근처 정류장 검색
  Future<void> _searchNearbyStationsFromCoords(
    double lat,
    double lng, {
    bool isAuto = true,
    bool allowFallback = true,
    bool showMessage = false,
    double initialRadius = 500.0,
  }) async {
    final requestId = ++_nearbyRequestSequence;
    final normalizedLat = double.tryParse(lat.toStringAsFixed(6)) ?? lat;
    final normalizedLng = double.tryParse(lng.toStringAsFixed(6)) ?? lng;

    debugPrint(
      '좌표 기반 정류장 검색 시작: $normalizedLat, $normalizedLng (auto=$isAuto, fallback=$allowFallback, radius=$initialRadius, request=$requestId)',
    );

    try {
      if (!isAuto && showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 16),
                Text('근처 정류장을 검색하고 있습니다...'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }

      final stations = await _getNearbyStationsWithFallback(
        normalizedLat,
        normalizedLng,
        initialRadius: initialRadius,
        allowFallback: allowFallback,
      );

      if (!mounted || requestId != _nearbyRequestSequence) return;

      if (stations.isNotEmpty) {
        setState(() {
          _nearbyStations = stations;
        });

        if (_mapReady) {
          _addMarkers();
          _webViewController.runJavaScript(
            'moveToLocation($normalizedLat, $normalizedLng, 3);',
          );
        }

        if (!isAuto && showMessage && mounted) {
          final message = stations.isNotEmpty
              ? '근처 ${stations.length}개 정류장을 찾았습니다.'
              : '근처 정류장을 찾을 수 없습니다.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else if (!isAuto && mounted && showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('근처 정류장을 찾을 수 없습니다.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted && !isAuto && showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('근처 정류장 검색 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // _showBusInfoBottomSheet 함수와 관련 위젯, 그리고 563라인의 _showBusInfoBottomSheet(selectedStation); 호출을 모두 삭제

  void _moveToCurrentLocation() {
    if (_mapReady && _currentPosition != null) {
      _webViewController.runJavaScript(
          'moveToLocation(${_currentPosition!.latitude}, ${_currentPosition!.longitude}, 3);');
    }
  }

  // 정류장 클릭 시 버스 도착 정보를 HTML로 전달
  Future<void> _updateStationInfoInMap(Map<String, dynamic> stationData) async {
    final requestId = ++_stationInfoRequestSequence;
    final stationName = stationData['name']?.toString() ?? '';
    final stationType = stationData['type']?.toString() ?? 'nearby';
    final latitude = _toCoordinate(stationData['latitude']);
    final longitude = _toCoordinate(stationData['longitude']);

    try {
      BusStop? selectedStation;

      if (stationType == 'route') {
        RouteStation? routeStation;
        for (final station in _routeStations) {
          if (station.stationName == stationName) {
            routeStation = station;
            break;
          }
        }

        if (routeStation != null) {
          selectedStation = BusStop(
            id: routeStation.stationId,
            stationId: routeStation.stationId,
            name: routeStation.stationName,
            latitude: routeStation.latitude,
            longitude: routeStation.longitude,
          );
        }
      } else if (stationType == 'nearby') {
        for (final station in _nearbyStations) {
          if (station.name == stationName) {
            selectedStation = station;
            break;
          }
        }
      }

      selectedStation ??= _findNearestStationByNameOrDistance(
        stationName: stationName,
        latitude: latitude,
        longitude: longitude,
        preferNearby: stationType != 'route',
      );

      var stationId = selectedStation?.getEffectiveStationId() ??
          _stationIdCache[stationName];

      if (!_isValidStationId(stationId)) {
        stationId = null;
      }

      if (stationId == null) {
        debugPrint('정류장 ID 직접 매칭 실패, 이름 검색 재시도: $stationName');
        final searchResults = await ApiService.searchStations(stationName);
        if (searchResults.isNotEmpty) {
          BusStop? chosen;
          if (latitude != null && longitude != null) {
            for (final station in searchResults) {
              final stationLat = station.latitude;
              final stationLng = station.longitude;
              if (stationLat == null || stationLng == null) {
                continue;
              }
              if (_calculateDistance(
                    latitude,
                    longitude,
                    stationLat,
                    stationLng,
                  ) <
                  0.01) {
                chosen = station;
                break;
              }
            }
          }

          chosen ??= searchResults.firstWhere(
            (station) => station.name == stationName,
            orElse: () => searchResults.first,
          );

          final resolvedStationId = chosen.getEffectiveStationId();
          if (_isValidStationId(resolvedStationId)) {
            stationId = resolvedStationId;
            selectedStation = chosen;
            _stationIdCache[stationName] = stationId;
          }
        }
      }

      if (!_isValidStationId(stationId)) {
        _sendStationBusInfoToMap(
          stationName: stationName,
          stationType: stationType,
          busInfo: '정류장 정보를 찾을 수 없습니다',
        );
        return;
      }

      final arrivals = await _getStationInfoFromCache(stationId!);
      if (!mounted || requestId != _stationInfoRequestSequence) return;

      final busInfoText =
          arrivals.isNotEmpty ? _formatBusInfoForMap(arrivals) : '도착 예정 버스 없음';
      _sendStationBusInfoToMap(
        stationName: stationName,
        stationType: stationType,
        busInfo: busInfoText,
      );
    } catch (e) {
      debugPrint('정류장 버스 정보 업데이트 오류: $e');
      if (mounted && requestId == _stationInfoRequestSequence) {
        _sendStationBusInfoToMap(
          stationName: stationName,
          stationType: stationType,
          busInfo: '버스 정보 조회 실패: $e',
        );
      }
    }
  }

  BusStop? _findNearestStationByNameOrDistance({
    required String stationName,
    double? latitude,
    double? longitude,
    bool preferNearby = true,
  }) {
    if (stationName.isEmpty) return null;

    if (preferNearby) {
      for (final station in _nearbyStations) {
        if (station.name == stationName) {
          return station;
        }
      }
    }

    if (latitude != null && longitude != null) {
      final nearest = _findNearestStation(latitude, longitude);
      if (nearest != null) {
        return nearest;
      }
    }

    for (final station in _routeStations) {
      if (station.stationName == stationName) {
        return BusStop(
          id: station.stationId,
          stationId: station.stationId,
          name: station.stationName,
          latitude: station.latitude,
          longitude: station.longitude,
        );
      }
    }

    return null;
  }

  bool _isValidStationId(String? stationId) {
    if (stationId == null || stationId.isEmpty) return false;
    return !stationId.startsWith('temp_') &&
        stationId != 'temp_station' &&
        !stationId.startsWith('kakao_');
  }

  // 버스 도착 정보를 지도용 Grid Layout HTML로 포맷 (노선별 중복 제거)

  String _formatBusInfoForMap(List<BusArrival> arrivals) {
    if (arrivals.isEmpty) {
      return '<span>도착 예정 버스 없음</span>';
    }

    // 노선 번호별로 가장 빠른 도착 정보만 필터링
    final Map<String, BusInfo> bestArrivals = {};
    for (final arrival in arrivals) {
      if (arrival.busInfoList.isNotEmpty) {
        final currentBest = bestArrivals[arrival.routeNo];
        final newCandidate = arrival.busInfoList.first;

        if (currentBest == null ||
            _parseTimeToMinutes(newCandidate.estimatedTime) <
                _parseTimeToMinutes(currentBest.estimatedTime)) {
          bestArrivals[arrival.routeNo] = newCandidate;
        }
      }
    }

    if (bestArrivals.isEmpty) {
      return '<span>도착 예정 버스 없음</span>';
    }

    // HTML 생성을 위해 정보 가공
    final busInfoList = bestArrivals.entries.map((entry) {
      final routeNo = entry.key;
      final busInfo = entry.value;
      String timeInfo =
          busInfo.isOutOfService ? '운행 종료' : busInfo.estimatedTime;
      return '$routeNo - $timeInfo';
    }).toList();

    // 정렬 (한글, 숫자, 영어 순으로)
    busInfoList.sort();

    final buffer = StringBuffer();
    for (final info in busInfoList) {
      // 각 정보를 div로 감싸서 CSS가 스타일을 적용하도록 함
      buffer.write('<div>$info</div>');
    }

    return buffer.toString();
  }

  // 시간 문자열을 분 단위로 변환하는 헬퍼 함수
  int _parseTimeToMinutes(String timeStr) {
    if (timeStr.isEmpty ||
        timeStr == '운행종료' ||
        timeStr == '운행 종료' ||
        timeStr == '-') {
      return 999; // 매우 큰 값으로 설정하여 우선순위 낮춤
    }

    // "곧 도착", "출발예정" 등의 특수 케이스
    if (timeStr.contains('곧') || timeStr.contains('출발예정')) {
      return 0;
    }

    // 숫자만 추출 (예: "3분 후" -> 3)
    final regex = RegExp(r'(\d+)');
    final match = regex.firstMatch(timeStr);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '999') ?? 999;
    }

    return 999; // 파싱 실패 시 큰 값 반환
  }

  // 주변 정류장 검색 기능
  Future<void> _searchNearbyStations() async {
    if (_currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 위치를 가져올 수 없습니다.')),
      );
      return;
    }

    await _searchNearbyStationsFromCoords(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      isAuto: false,
      allowFallback: false,
      showMessage: true,
      initialRadius: 2000.0,
    );
  }


  void _startBusPositionTracking() {
    if (widget.routeId == null) return;

    // 90초마다 버스 위치 업데이트 (부하 더욱 감소)
    _busPositionTimer = Timer.periodic(const Duration(seconds: 90), (timer) {
      _updateBusPositions();
    });

    // 초기 버스 위치 로드
    _updateBusPositions();
  }

  Future<void> _updateBusPositions() async {
    if (widget.routeId == null || !_mapReady) return;

    try {
      final busApiService = BusApiService();
      final positionData =
          await busApiService.getBusPositionInfo(widget.routeId!);

      if (positionData != null) {
        _addBusMarkers(positionData);
      }
    } catch (e) {
      debugPrint('버스 위치 업데이트 오류: $e');
    }
  }

  void _addBusMarkers(Map<String, dynamic> positionData) {
    if (!_mapReady) return;

    // 기존 버스 마커 제거
    _webViewController.runJavaScript('clearBusMarkers();');

    // 새로운 버스 마커 추가
    if (positionData.containsKey('buses') && positionData['buses'] is List) {
      final buses = positionData['buses'] as List;

      for (final bus in buses) {
        if (bus is Map<String, dynamic> &&
            bus.containsKey('latitude') &&
            bus.containsKey('longitude')) {
          final lat = double.tryParse(bus['latitude'].toString());
          final lng = double.tryParse(bus['longitude'].toString());
          final busNumber = bus['busNumber'] ?? widget.routeId;

          if (lat != null && lng != null) {
            _webViewController.runJavaScript(
              'addBusMarker($lat, $lng, ${_toJsString(busNumber)}, ${_toJsString(widget.routeId)});',
            );
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _busPositionTimer?.cancel();
    _searchThrottleTimer?.cancel();
    _mapSearchDebouncer.dispose();
    super.dispose();
  }
}
