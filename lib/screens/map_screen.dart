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
  final double bottomInset; // 하단 광고+네비게이션 높이 (버튼/축적도 겹침 방지)

  const MapScreen({
    super.key,
    this.routeId,
    this.routeStations,
    this.initialNearbyStations,
    this.bottomInset = 0.0,
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
  Timer? _kakaoInitFallbackTimer;
  bool _kakaoSdkLoaded = false;
  final Debouncer _mapSearchDebouncer = Debouncer(delay: const Duration(milliseconds: 350));
  final Map<String, Future<List<BusStop>>> _nearbyInFlight = {};
  final Map<String, _TimedCacheEntry<List<BusStop>>> _nearbyCache = {};
  final Map<String, Future<List<BusArrival>>> _stationInfoInFlight = {};
  final Map<String, _TimedCacheEntry<List<BusArrival>>> _stationInfoCache = {};
  final Map<String, String?> _stationIdCache = {};
  final Map<String, DateTime> _stationInfoLastRequestedAt = {};
  int _nearbyRequestSequence = 0;
  int _manualNearbyRequestSequence = 0;
  int _manualNearbyRequestPendingId = 0;
  int _stationInfoRequestSequence = 0;
  bool _isLoading = true;
  bool _mapReady = false;
  bool _locationMarkerPlaced = false;
  String? _errorMessage;
  String? _htmlContent;
  String? _lastMapTraceId;
  double? _lastClickedLat;
  double? _lastClickedLng;
  double? _lastCenterLat;
  double? _lastCenterLng;
  double? _lastMpp; // Meters Per Pixel
  static const List<double> _defaultMapFallbackRadii = [
    500.0,
    1000.0,
    2000.0,
    4000.0,
    8000.0,
    20000.0,
  ];

  @override
  void initState() {
    super.initState();
    debugPrint('[mapInit] MapScreen initState');
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    final initTrace = 'map_init_${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('[$initTrace] 지도 화면 초기화 시작');
    try {
      // HTML 템플릿 로드
      await _loadHtmlTemplate();
      debugPrint('[$initTrace] HTML 템플릿 로드 완료');

      // 현재 위치 가져오기
      _currentPosition = await _getCurrentPosition();
      debugPrint(
        '[$initTrace] 현재 위치 획득: ${_currentPosition?.latitude}, ${_currentPosition?.longitude}',
      );

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
      debugPrint('[$initTrace] WebView 초기화 호출 완료');

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[$initTrace] 지도 화면 초기화 실패: $e');
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
      debugPrint(
        '[kakaoKey] Kakao JS API 키 치환 완료 (${kakaoApiKey.length}자)',
      );
    } catch (e) {
      debugPrint('HTML 템플릿 로드 오류: $e');
      throw Exception('HTML 템플릿을 로드할 수 없습니다: $e');
    }
  }

  String? _resolveKakaoApiKey() {
    final fromDotEnv = dotenv.env['KAKAO_JS_API_KEY']?.trim();
    if (fromDotEnv != null && fromDotEnv.isNotEmpty) {
      if (_looksLikeKakaoJsApiKey(fromDotEnv)) {
        debugPrint('[kakaoKey] source=dotenv');
        return fromDotEnv;
      }
    }

    final fromDartDefine = _kakaoJsApiKeyFromDefine.trim();
    if (_looksLikeKakaoJsApiKey(fromDartDefine)) {
      debugPrint('[kakaoKey] source=--dart-define');
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
              bottomInset: widget.bottomInset,
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
    final webTrace = 'webview_${DateTime.now().millisecondsSinceEpoch}';
    debugPrint('[$webTrace] WebView 초기화 시작');
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setOnConsoleMessage((JavaScriptConsoleMessage msg) {
        debugPrint('WebView console: ${msg.message}');
      })
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            debugPrint('[$webTrace] 페이지 로드 시작: $url');
          },
          onPageFinished: (String url) {
            debugPrint('[$webTrace] 페이지 로드 완료: $url');
            _onMapReady();
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('[$webTrace] WebView 오류: code=${error.errorCode}, type=${error.errorType}, description=${error.description}');
          },
        ),
      )
      ..addJavaScriptChannel(
        'mapEvent',
        onMessageReceived: (JavaScriptMessage message) {
          debugPrint('지도 이벤트 수신(trace=${_lastMapTraceId ?? 'N/A'}): ${message.message}');
          _handleMapEvent(message.message);
        },
      );

    debugPrint('[$webTrace] HTML 콘텐츠 로드 중...');
    _webViewController.loadHtmlString(_htmlContent!);
  }

  void _onMapReady() {
    debugPrint('지도 준비 완료 이벤트 수신');
    setState(() {
      _mapReady = true;
    });

    // 하단 인셋 적용 (축적도/저작권이 광고+네브바 뒤에 가려지지 않도록)
    if (widget.bottomInset > 0) {
      _webViewController.runJavaScript('adjustMapInset(${widget.bottomInset});');
    }

    // Kakao SDK onload(mapLoaded)가 오면 _onKakaoSdkLoaded()에서 initMap을 호출한다.
    // 5초 안에 mapLoaded가 수신되지 않으면 fallback으로 직접 호출 (네트워크 지연 대비).
    _kakaoInitFallbackTimer?.cancel();
    _kakaoInitFallbackTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_kakaoSdkLoaded) {
        debugPrint('[kakaoFallback] mapLoaded 미수신 → fallback initMap 실행');
        _onKakaoSdkLoaded();
      }
    });

    // 노선 ID가 있으면 실시간 버스 위치 추적 시작
    if (widget.routeId != null) {
      _startBusPositionTracking();
    }
  }

  // Kakao SDK 로드 완료(mapLoaded) 또는 fallback 타이머에서 호출
  void _onKakaoSdkLoaded() {
    if (_kakaoSdkLoaded) return;
    _kakaoSdkLoaded = true;
    _kakaoInitFallbackTimer?.cancel();

    _initializeKakaoMap();

    _searchThrottleTimer?.cancel();
    _searchThrottleTimer = Timer(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      debugPrint('지연 후 마커 추가 시작');
      _addMarkers();
      _scheduleNearbySearch(visibleOnly: false, isAuto: true);
    });
  }

  void _initializeKakaoMap() {
    if (!_mapReady) return;

    final lat = _currentPosition?.latitude ?? 35.8714;
    final lng = _currentPosition?.longitude ?? 128.6014;

    _webViewController.runJavaScript('initMap($lat, $lng, 3);');
  }

  void _scheduleNearbySearch({
    double? lat,
    double? lng,
    bool visibleOnly = false,
    bool isAuto = true,
  }) {
    // 1. 요청받은 좌표 우선
    // 2. 지도 중심좌표(드래그 등)
    // 3. 현재 GPS 좌표
    final searchLat = lat ?? _lastCenterLat ?? _currentPosition?.latitude;
    final searchLng = lng ?? _lastCenterLng ?? _currentPosition?.longitude;

    if (searchLat == null || searchLng == null) return;

    _mapSearchDebouncer.call(() {
      // 화면 너비의 약 절반 정도를 검색 반경으로 설정 (최소 1000m, 최대 15000m)
      double calculatedRadius = 1500.0;
      if (_lastMpp != null) {
        // 일반적인 스마트폰 화면 가로가 약 400~500dp, 픽셀로는 1200px 내외
        // 화면의 절반 정도를 커버하려면 약 600px * mpp
        calculatedRadius = (_lastMpp! * 600).clamp(1000.0, 15000.0);
      }

      _searchNearbyStationsFromCoords(
        searchLat,
        searchLng,
        isAuto: isAuto,
        allowFallback: true, // 항상 폴백 허용하여 검색 성공률 높임
        showMessage: !isAuto, // 자동 검색 시에는 메시지 숨김
        initialRadius: calculatedRadius,
        shouldMoveCamera: !isAuto, // 자동 드래그 검색 시에는 카메라 고정
      );
    });
  }

  void _addMarkers() {
    if (!_mapReady) {
      debugPrint('지도가 준비되지 않아서 마커를 추가할 수 없습니다');
      return;
    }

    // 위치 마커는 최초 1회만 추가 (드래그/줌 시 깜빡임 방지)
    if (!_locationMarkerPlaced) {
      _webViewController.runJavaScript('clearMarkers();');
      if (_currentPosition != null) {
        _webViewController.runJavaScript(
          'addCurrentLocationMarker(${_currentPosition!.latitude}, ${_currentPosition!.longitude});',
        );
      }
      _locationMarkerPlaced = true;
    }

    // 정류장 마커 목록 구성
    final List<Map<String, dynamic>> stationList = [];

    // 노선 정류장 (route 타입, 우선)
    final routeKeys = <String>{};
    for (final station in _routeStations) {
      if (station.latitude != null && station.longitude != null) {
        stationList.add({
          'lat': station.latitude!,
          'lng': station.longitude!,
          'name': station.stationName,
          'type': 'route',
          'seq': station.sequenceNo,
        });
        routeKeys.add('${station.latitude!.toStringAsFixed(5)},${station.longitude!.toStringAsFixed(5)}');
      }
    }

    // 주변 정류장 (nearby, 노선 정류장과 중복 제거)
    for (final station in _nearbyStations) {
      if (station.latitude != null && station.longitude != null) {
        final key = '${station.latitude!.toStringAsFixed(5)},${station.longitude!.toStringAsFixed(5)}';
        if (!routeKeys.contains(key)) {
          stationList.add({
            'lat': station.latitude!,
            'lng': station.longitude!,
            'name': station.name,
            'type': 'nearby',
            'seq': 0,
          });
          routeKeys.add(key);
        }
      }
    }

    // 배치 + 증분 업데이트: JS 1회 호출로 전체 처리
    _webViewController.runJavaScript('setStationMarkers(${_toJsString(jsonEncode(stationList))});');
    debugPrint('마커 업데이트: 노선 ${_routeStations.length}개 + 주변 ${_nearbyStations.length}개 → 총 ${stationList.length}개');
  }

  String _toJsString(Object? value) => jsonEncode(value ?? '');

  String _buildTraceId(String prefix, int requestId) {
    return '${prefix}_${requestId}_${DateTime.now().millisecondsSinceEpoch}';
  }

  String _stationCoordinateCacheKey(double latitude, double longitude, double radiusMeters) {
    // ~200m 격자 스냅: 인접 이동 시 캐시 히트율 향상 (1/500도 ≈ 222m)
    final snapLat = (latitude * 500).round() / 500.0;
    final snapLng = (longitude * 500).round() / 500.0;
    // 반경도 500m 단위로 스냅 (세밀한 변화에도 캐시 히트)
    final snapRadius = ((radiusMeters / 500).round() * 500).clamp(500, 15000);
    return '${snapLat.toStringAsFixed(3)}_${snapLng.toStringAsFixed(3)}_$snapRadius';
  }

  double? _toCoordinate(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();

    final normalized = value.toString().trim().replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  String _typeLabel(Object? value) {
    return value == null ? 'null' : value.runtimeType.toString();
  }

  bool _isFiniteCoordinate(double? value) {
    return value != null && value.isFinite;
  }

  void _updateAnchorPosition(double lat, double lng, String traceId) {
    _lastClickedLat = lat;
    _lastClickedLng = lng;
    debugPrint(
      '[$traceId] 지도 클릭 기준 좌표 저장: lat=$lat, lng=$lng (anchor=${_lastClickedLat},${_lastClickedLng})',
    );
  }

  Future<List<BusStop>> _getNearbyStationsFromCache(
    double latitude,
    double longitude,
    double radiusMeters,
    {String? traceId}
  ) async {
    final effectiveTraceId = traceId ?? _buildTraceId('cache', _nearbyRequestSequence + 1);
    final cacheKey = _stationCoordinateCacheKey(latitude, longitude, radiusMeters);
    debugPrint('[$effectiveTraceId] findNearby cache check key=$cacheKey lat=$latitude lng=$longitude radius=$radiusMeters');

    final cached = _nearbyCache[cacheKey];
    if (cached != null && !cached.isExpired(_nearbyCacheTtl)) {
      debugPrint('[$effectiveTraceId] findNearby cache hit key=$cacheKey size=${cached.value.length}');
      return cached.value;
    }

    final existing = _nearbyInFlight[cacheKey];
    if (existing != null) {
      debugPrint('[$effectiveTraceId] findNearby cache in-flight join key=$cacheKey');
      return existing;
    }

    final future = ApiService.findNearbyStations(
      latitude,
      longitude,
      radiusMeters: radiusMeters,
      traceId: effectiveTraceId,
    ).then((stations) {
      debugPrint(
        '[$effectiveTraceId] findNearby native returned ${stations.length}개 (radius=$radiusMeters)',
      );
      _nearbyCache[cacheKey] = _TimedCacheEntry(stations, DateTime.now());
      return stations;
    }).catchError((Object error, StackTrace stackTrace) {
      debugPrint('[$effectiveTraceId] findNearby native call failed: $error');
      debugPrint('[$effectiveTraceId] findNearby stack: $stackTrace');
      throw error;
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
    String? traceId,
  }) async {
    final searchRadii = <double>{initialRadius};
    if (allowFallback) {
      for (final fallbackRadius in _defaultMapFallbackRadii) {
        // initialRadius보다 큰 반경만 폴백으로 추가 (작은 반경이 먼저 선택되는 버그 방지)
        if (fallbackRadius > initialRadius) {
          searchRadii.add(fallbackRadius);
        }
      }
    }
    final resolvedRadii = searchRadii.toList()
      ..sort((a, b) => a.compareTo(b));
    final effectiveTraceId = traceId ?? _buildTraceId('fallback', _nearbyRequestSequence + 1);

    debugPrint(
      '[$effectiveTraceId] findNearby fallback radii 계획: ${resolvedRadii.join(", ")}',
    );
    for (var i = 0; i < resolvedRadii.length; i++) {
      final radius = resolvedRadii[i];
      debugPrint(
        '[$effectiveTraceId] findNearby fallback ${i + 1}/${searchRadii.length}: radius=$radius',
      );
      final stations = await _getNearbyStationsFromCache(
        latitude,
        longitude,
        radius,
        traceId: effectiveTraceId,
      );
      debugPrint('[$effectiveTraceId] findNearby fallback radius=$radius result=${stations.length}');
      if (stations.isNotEmpty) return stations;
    }
    debugPrint('[$effectiveTraceId] findNearby fallback all failed');
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
      final preview = message.length > 240 ? '${message.substring(0, 240)}…' : message;
      debugPrint('WebView 원본 메시지: $preview');

      final decoded = jsonDecode(message);
      if (decoded is! Map<String, dynamic>) {
        debugPrint('지도 이벤트 형식 오류: payload는 Map이 아닙니다. type=${decoded.runtimeType}');
        return;
      }

      final data = decoded;
      final type = data['type']?.toString();
      final eventData = (data['data'] is Map)
          ? Map<String, dynamic>.from(data['data'] as Map)
          : const <String, dynamic>{};
      _lastMapTraceId = type?.toString();

      debugPrint('웹뷰 메시지 수신: $type, 데이터: $eventData');

      switch (type) {
        case 'mapReady':
        case 'mapLoaded':
          debugPrint('지도 준비 완료');
          if (_mapReady) _onKakaoSdkLoaded();
          break;
        case 'zoomChanged':
          final lvl = eventData['level'];
          final mpp = eventData['metersPerPixel'];
          final dpr = eventData['dpr'];
          debugPrint(
              '줌 변경: level=$lvl, m/px=${mpp?.toStringAsFixed(3)}, dpr=$dpr');
          if (mpp is num) _lastMpp = mpp.toDouble();
          break;
        case 'mapMetrics':
          final lvl = eventData['level'];
          final mpp = eventData['metersPerPixel'];
          final lat = _toCoordinate(eventData['centerLat']);
          final lng = _toCoordinate(eventData['centerLng']);
          final dpr = eventData['dpr'];
          debugPrint(
              '맵 메트릭스: level=$lvl, m/px=${mpp?.toStringAsFixed(3)}, center=($lat,$lng), dpr=$dpr');
          
          if (mpp is num) _lastMpp = mpp.toDouble();

          if (_isFiniteCoordinate(lat) && _isFiniteCoordinate(lng)) {
             _lastCenterLat = lat;
             _lastCenterLng = lng;
             
             // 지도 드래그/이동 멈춤 시 자동 검색 (500ms 디바운스 적용됨)
             _scheduleNearbySearch(
               lat: lat,
               lng: lng,
               visibleOnly: true, // 너무 넓지 않게
               isAuto: true,
             );
          }
          break;
        case 'mapError':
          final error = eventData['error'];
          debugPrint('지도 오류: $error');
          setState(() {
            _errorMessage = '지도 로드 오류: $error';
          });
          break;
        case 'mapClick':
          final rawTraceId = eventData['traceId'];
          final source = eventData['source']?.toString() ?? 'unknown';
          final traceId = rawTraceId is String && rawTraceId.trim().isNotEmpty
              ? rawTraceId
              : null;
          final eventLabel = traceId ?? _buildTraceId('manualClick', _nearbyRequestSequence + 1);
          _lastMapTraceId = eventLabel;
          debugPrint('[$eventLabel] mapClick 처리 시작 source=$source trace=$eventLabel');
          final rawLat = eventData['latitude'];
          final rawLng = eventData['longitude'];
          final lat = _toCoordinate(rawLat);
          final lng = _toCoordinate(rawLng);
          debugPrint(
            'mapClick raw payload trace=$eventLabel source=$source rawLat=$rawLat(${rawLat?.runtimeType}), rawLng=$rawLng(${rawLng?.runtimeType}), mapReady=$_mapReady, currentPosition=$_currentPosition',
          );
          final normalizedLat = lat != null ? double.tryParse(lat.toStringAsFixed(6)) : null;
          final normalizedLng = lng != null ? double.tryParse(lng.toStringAsFixed(6)) : null;
          debugPrint(
            'mapClick trace=$eventLabel rawLat=$rawLat(${_typeLabel(rawLat)}), rawLng=$rawLng(${_typeLabel(rawLng)}), '
            'parsed=($normalizedLat, $normalizedLng)',
          );
          if (!_isFiniteCoordinate(lat) || !_isFiniteCoordinate(lng) ||
              normalizedLat == null || normalizedLng == null) {
            debugPrint('지도 클릭 좌표 파싱 실패 trace=$eventLabel data=$data');
            if (_currentPosition != null) {
              debugPrint('지도 클릭 좌표 파싱 실패 후 현재 위치로 fallback trace=$eventLabel');
              _searchNearbyStationsFromCoords(
                _currentPosition!.latitude,
                _currentPosition!.longitude,
                isAuto: false,
                showMessage: true,
                allowFallback: true,
                initialRadius: 1000.0,
                traceId: '${eventLabel}_fallback_current',
              );
            }
            break;
          }
          _updateAnchorPosition(normalizedLat!, normalizedLng!, eventLabel);
          debugPrint(
            '지도 클릭: $lat, $lng → 클릭 위치 기준 주변 정류장 검색(trace=$eventLabel, source=$source)',
          );
          if (!_mapReady) {
            debugPrint('지도 클릭 수신 후 지도 미준비 상태, trace=$eventLabel');
          }
          debugPrint(
            '지도 클릭 검색 실행 trace=$eventLabel, allowFallback=true, initialRadius=500.0',
          );
          _searchNearbyStationsFromCoords(
            normalizedLat,
            normalizedLng,
            isAuto: false,
            showMessage: true,
            allowFallback: true,
            initialRadius: 1000.0,
            traceId: eventLabel,
          );
          break;
        case 'stationClick':
          final stationData = eventData;
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
    } catch (e, st) {
      debugPrint('지도 이벤트 처리 오류: $e');
      debugPrint('지도 이벤트 처리 오류(스택): $st');
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

  Future<void> _searchNearbyStationsFromCoords(
    double lat,
    double lng, {
    bool isAuto = true,
    bool allowFallback = true,
    bool showMessage = false,
    double initialRadius = 500.0,
    String? traceId,
    bool shouldMoveCamera = true,
  }) async {
    final requestId = ++_nearbyRequestSequence;
    final normalizedLat = double.tryParse(lat.toStringAsFixed(6)) ?? lat;
    final normalizedLng = double.tryParse(lng.toStringAsFixed(6)) ?? lng;
    final eventTraceId = traceId ?? _buildTraceId('search', requestId);
    if (!isAuto) {
      _manualNearbyRequestSequence = requestId;
      _manualNearbyRequestPendingId = requestId;
    }

    debugPrint(
      '[$eventTraceId] 좌표 기반 정류장 검색 시작: $normalizedLat, $normalizedLng (auto=$isAuto, fallback=$allowFallback, radius=$initialRadius, request=$requestId, pendingManual=$_manualNearbyRequestPendingId, shouldMoveCamera=$shouldMoveCamera)',
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
        traceId: eventTraceId,
      );

      if (!mounted) {
        debugPrint(
          '[$eventTraceId] 좌표 기반 정류장 검색 스킵: requestId mismatch 또는 unmounted '
          '(mounted=$mounted, isAuto=$isAuto, currentRequest=$_nearbyRequestSequence, manualRequest=$_manualNearbyRequestSequence, finishedRequest=$requestId)',
        );
        return;
      }
      if (isAuto && _manualNearbyRequestPendingId > 0) {
        debugPrint(
          '[$eventTraceId] 좌표 기반 정류장 검색 스킵: 수동 검색이 진행 중임 (pendingManual=$_manualNearbyRequestPendingId) '
          '(currentRequest=$requestId, isAuto=$isAuto)',
        );
        return;
      }
      if (isAuto && _manualNearbyRequestSequence > requestId) {
        debugPrint(
          '[$eventTraceId] 좌표 기반 정류장 검색 스킵: 수동 요청($_manualNearbyRequestSequence)이 더 최신임 '
          '(currentRequest=$requestId)',
        );
        return;
      }
      if (!isAuto && requestId != _manualNearbyRequestSequence) {
        debugPrint(
          '[$eventTraceId] 좌표 기반 정류장 검색 스킵: 수동 요청 순서 불일치 '
          '(expected=$_manualNearbyRequestSequence, finished=$requestId)',
        );
        return;
      }
      debugPrint('[$eventTraceId] findNearby request#$requestId result count=${stations.length}');
      if (!stations.isNotEmpty && !isAuto && showMessage) {
        debugPrint('[$eventTraceId] 지도 클릭 수동 검색 결과 0개');
      }
      if (stations.isNotEmpty) {
        final preview = stations
            .take(6)
            .map((station) =>
                '${station.name}(${station.distance?.toStringAsFixed(0)}m)')
            .toList();
        debugPrint('[$eventTraceId] findNearby request#$requestId preview=${preview.join(' | ')}');
      }

      setState(() {
        _nearbyStations = stations;
      });

      if (_mapReady) {
        _addMarkers();
        if (shouldMoveCamera) {
          _webViewController.runJavaScript(
            'moveToLocation($normalizedLat, $normalizedLng, 3);',
          );
        }
      }

      if (!isAuto && mounted && showMessage) {
        if (stations.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('근처 ${stations.length}개 정류장을 찾았습니다.'),
              duration: const Duration(seconds: 2),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('해당 지역 근처에 대구 버스 정류장이 없습니다.'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: '내 위치로',
                textColor: Colors.white,
                onPressed: _moveToCurrentLocation,
              ),
            ),
          );
        }
      }
    } catch (e, st) {
      debugPrint('[$eventTraceId] 좌표 기반 정류장 검색 실패: $e');
      debugPrint('[$eventTraceId] 좌표 기반 정류장 검색 실패 스택: $st');
      if (mounted && !isAuto && showMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('근처 정류장 검색 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (!isAuto && _manualNearbyRequestPendingId == requestId) {
        _manualNearbyRequestPendingId = 0;
        debugPrint('[$eventTraceId] 수동 주변 정류장 검색 완료 처리: pendingId=$requestId 초기화');
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
    final seedLat = _lastClickedLat ?? _currentPosition?.latitude;
    final seedLng = _lastClickedLng ?? _currentPosition?.longitude;
    if (seedLat == null || seedLng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 위치를 가져올 수 없습니다.')),
      );
      return;
    }

    await _searchNearbyStationsFromCoords(
      seedLat,
      seedLng,
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
    _kakaoInitFallbackTimer?.cancel();
    _mapSearchDebouncer.dispose();
    super.dispose();
  }
}
