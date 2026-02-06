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
  late WebViewController _webViewController;
  Position? _currentPosition;
  List<BusStop> _nearbyStations = [];
  List<RouteStation> _routeStations = [];
  Timer? _busPositionTimer;
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
      String htmlTemplate =
          await rootBundle.loadString('assets/kakao_map.html');

      // 환경변수에서 카카오 API 키 가져오기
      final kakaoApiKey = dotenv.env['KAKAO_JS_API_KEY'];

      if (kakaoApiKey == null || kakaoApiKey.isEmpty) {
        throw Exception('KAKAO_JS_API_KEY가 .env 파일에 설정되지 않았습니다.');
      }

      // 카카오 API 키를 실제 키로 교체
      _htmlContent = htmlTemplate.replaceAll('YOUR_KAKAO_API_KEY', kakaoApiKey);

      debugPrint('카카오맵 API 키 로드 완료 (길이: ${kakaoApiKey.length})');
    } catch (e) {
      debugPrint('HTML 템플릿 로드 오류: $e');
      throw Exception('HTML 템플릿을 로드할 수 없습니다: $e');
    }
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

    try {
      debugPrint(
          '주변 정류장 검색 시작: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');

      // 주변 정류장 검색 (반경 2km로 증가)
      final stations = await ApiService.findNearbyStations(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        radiusMeters: 2000.0,
      );

      debugPrint('주변 정류장 검색 완료: ${stations.length}개 발견');

      for (final station in stations) {
        debugPrint(
            '정류장: ${station.name} (${station.latitude}, ${station.longitude})');
      }

      setState(() {
        _nearbyStations = stations;
      });

      debugPrint('주변 정류장 상태 업데이트 완료');

      // 로컬 DB에서 정류장을 찾지 못한 경우
      if (stations.isEmpty) {
        debugPrint('로컬 DB에서 정류장을 찾지 못했습니다.');
      }
    } catch (e) {
      debugPrint('주변 정류장 로드 오류: $e');
    }
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

    // 잠시 후 마커 추가 (지도 초기화 완료 대기)
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      debugPrint('지연 후 마커 추가 시작');
      _addMarkers();

      // 주변 정류장이 없으면 자동으로 검색
      if (_nearbyStations.isEmpty) {
        debugPrint('주변 정류장이 없어서 자동 검색을 시작합니다');
        _searchNearbyStations();
      }
    });

    // 3초 후에도 주변 정류장이 없으면 추가 검색
    Future.delayed(const Duration(milliseconds: 3000), () {
      if (!mounted) return;
      if (_nearbyStations.isEmpty) {
        debugPrint('3초 후에도 주변 정류장이 없어서 추가 검색을 시도합니다');
        _searchNearbyStations();
      }
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

    // 지도 초기화 후 자동으로 주변 정류장 검색 시작 (더 빠르게)
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      if (_nearbyStations.isEmpty) {
        debugPrint('지도 초기화 후 자동 주변 정류장 검색 시작');
        _searchNearbyStations();
      }
    });

    // 추가로 3초 후에도 검색 (지도 완전 로드 후)
    Future.delayed(const Duration(milliseconds: 3000), () {
      if (!mounted) return;
      if (_nearbyStations.isEmpty) {
        debugPrint('지도 완전 로드 후 추가 주변 정류장 검색');
        _searchNearbyStations();
      }
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
            'addStationMarker($lat, $lng, "${station.stationName}", "route", ${station.sequenceNo});');
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
              'addStationMarker($lat, $lng, "${station.name}", "nearby", 0);');
          addedCoordinates.add(coordKey);
        }
      }
    }

    debugPrint(
        '마커 추가 완료 - 총 ${_routeStations.length + addedCoordinates.length}개');
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
            _searchNearbyStationsFromCoords(lat, lng);
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
    final latitude = stationData['latitude'] as double?;
    final longitude = stationData['longitude'] as double?;

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
                  _searchNearbyStationsFromCoords(latitude, longitude);
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
                  _searchNearbyStationsFromCoords(latitude, longitude);
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
  Future<void> _searchNearbyStationsFromCoords(double lat, double lng) async {
    debugPrint('좌표 기반 정류장 검색: $lat, $lng');

    try {
      // 로딩 표시
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

      // 좌표 기반으로 주변 정류장 검색 (반경 500m)
      final stations = await ApiService.findNearbyStations(
        lat,
        lng,
        radiusMeters: 500.0,
      );

      if (stations.isNotEmpty) {
        setState(() {
          _nearbyStations = stations;
        });

        // 지도에 마커 업데이트
        if (_mapReady) {
          _addMarkers();
        }

        // 지도를 클릭한 위치로 이동
        if (_mapReady) {
          _webViewController.runJavaScript('moveToLocation($lat, $lng, 3);');
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('근처 ${stations.length}개 정류장을 찾았습니다.'),
              action: SnackBarAction(
                label: '확인',
                onPressed: () {},
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } else {
        // 검색 반경을 늘려서 다시 시도
        debugPrint('500m 반경에서 정류장을 찾지 못했습니다. 1km 반경으로 재검색합니다.');

        final extendedStations = await ApiService.findNearbyStations(
          lat,
          lng,
          radiusMeters: 1000.0,
        );

        if (extendedStations.isNotEmpty) {
          setState(() {
            _nearbyStations = extendedStations;
          });

          // 지도에 마커 업데이트
          if (_mapReady) {
            _addMarkers();
          }

          // 지도를 클릭한 위치로 이동
          if (_mapReady) {
            _webViewController.runJavaScript('moveToLocation($lat, $lng, 3);');
          }

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    Text('1km 반경에서 ${extendedStations.length}개 정류장을 찾았습니다.'),
                action: SnackBarAction(
                  label: '확인',
                  onPressed: () {},
                ),
                duration: const Duration(seconds: 3),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('근처에 정류장을 찾을 수 없습니다.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
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
    try {
      final stationName = stationData['name'] as String;
      final stationType = stationData['type'] as String?;

      // 정류장 정보 찾기
      BusStop? selectedStation;

      if (stationType == 'nearby') {
        // 주변 정류장에서 찾기
        selectedStation = _nearbyStations.firstWhere(
          (station) => station.name == stationName,
          orElse: () => BusStop(
            id: 'temp_${stationName.hashCode}',
            stationId: 'temp_station',
            name: stationName,
            latitude: stationData['latitude'],
            longitude: stationData['longitude'],
          ),
        );
      } else if (stationType == 'route') {
        // 노선 정류장에서 찾기
        final routeStation = _routeStations
            .where(
              (station) => station.stationName == stationName,
            )
            .firstOrNull;

        if (routeStation != null) {
          selectedStation = BusStop(
            id: routeStation.stationId,
            stationId: routeStation.stationId,
            name: routeStation.stationName,
            latitude: routeStation.latitude,
            longitude: routeStation.longitude,
          );
        } else {
          selectedStation = BusStop(
            id: 'temp_${stationName.hashCode}',
            stationId: 'temp_station',
            name: stationName,
            latitude: stationData['latitude'],
            longitude: stationData['longitude'],
          );
        }
      } else {
        // 카카오 정류장 처리 - 정류장 이름으로 검색
        debugPrint('카카오 정류장 처리: $stationName');

        try {
          // 정류장 이름으로 검색하여 실제 정류장 ID 찾기
          final searchResults = await ApiService.searchStations(stationName);
          debugPrint('정류장 검색 결과: ${searchResults.length}개');

          if (searchResults.isNotEmpty) {
            // 가장 유사한 정류장 선택
            final bestMatch = searchResults.first;
            selectedStation = BusStop(
              id: bestMatch.id,
              stationId: bestMatch.stationId,
              name: bestMatch.name,
              latitude: bestMatch.latitude,
              longitude: bestMatch.longitude,
            );
            debugPrint(
                '검색된 정류장 사용: ${bestMatch.name} (${bestMatch.stationId})');
          } else {
            // 검색 결과가 없으면 더미 정류장 생성
            final latitude = stationData['latitude'] as double?;
            final longitude = stationData['longitude'] as double?;
            selectedStation = BusStop(
              id: 'kakao_${stationName.hashCode}',
              stationId: 'temp_station',
              name: stationName,
              latitude: latitude,
              longitude: longitude,
            );
            debugPrint('더미 정류장 생성: $stationName');
          }
        } catch (e) {
          debugPrint('정류장 검색 오류: $e');
          final latitude = stationData['latitude'] as double?;
          final longitude = stationData['longitude'] as double?;
          selectedStation = BusStop(
            id: 'kakao_${stationName.hashCode}',
            stationId: 'temp_station',
            name: stationName,
            latitude: latitude,
            longitude: longitude,
          );
        }
      }

      // 버스 도착 정보 조회 - 정류장 이름으로 검색 후 실제 ID로 조회
      debugPrint('정류장 버스 정보 조회 시작: $stationName');

      try {
        String? actualStationId;

        // 1. 먼저 selectedStation에서 유효한 ID가 있는지 확인
        final stationId = selectedStation.stationId ?? selectedStation.id;
        if (stationId.isNotEmpty &&
            !stationId.startsWith('temp_') &&
            stationId != 'temp_station') {
          actualStationId = stationId;
          debugPrint('기존 정류장 ID 사용: $actualStationId');
        }

        // 2. 유효한 ID가 없으면 정류장 이름으로 검색
        if (actualStationId == null) {
          debugPrint('정류장 이름으로 검색 시작: $stationName');
          final searchResults = await ApiService.searchStations(stationName);
          debugPrint('정류장 검색 결과: ${searchResults.length}개');

          if (searchResults.isNotEmpty) {
            // 정확히 일치하는 정류장 찾기
            final exactMatch = searchResults.firstWhere(
              (station) => station.name == stationName,
              orElse: () => searchResults.first,
            );
            actualStationId = exactMatch.getEffectiveStationId();
            debugPrint('검색된 정류장 ID: $actualStationId (${exactMatch.name})');
          }
        }

        if (actualStationId == null || actualStationId.isEmpty) {
          debugPrint('유효한 정류장 ID를 찾을 수 없음');
          if (_mapReady) {
            _webViewController.runJavaScript(
                'updateStationBusInfo("$stationName", "$stationType", "정류장 정보를 찾을 수 없습니다");');
          }
          return;
        }

        // 3. 실제 정류장 ID로 버스 정보 조회
        debugPrint('실제 정류장 ID로 버스 정보 조회: $actualStationId');
        const platform = MethodChannel('com.example.daegu_bus_app/bus_api');
        final String jsonResult =
            await platform.invokeMethod('getStationInfo', {
          'stationId': actualStationId,
        });

        debugPrint('네이티브 응답 원본: $jsonResult');

        if (jsonResult.isNotEmpty && jsonResult != '[]') {
          final List<dynamic> decoded = jsonDecode(jsonResult);
          // final busApiService = BusApiService(); // 사용되지 않음

          // 네이티브 코드에서 반환하는 JSON 구조에 맞게 파싱
          final List<BusArrival> arrivals = [];

          for (final routeData in decoded) {
            if (routeData is! Map<String, dynamic>) continue;

            final String routeNo = routeData['routeNo'] ?? '';
            final List<dynamic>? arrList = routeData['arrList'];

            debugPrint('노선 $routeNo 파싱 중, arrList: $arrList');

            if (arrList == null || arrList.isEmpty) {
              debugPrint('노선 $routeNo의 arrList가 비어있음');
              continue;
            }

            final List<BusInfo> busInfoList = [];

            for (final arrivalData in arrList) {
              if (arrivalData is! Map<String, dynamic>) continue;

              // final String routeId = arrivalData['routeId'] ?? ''; // 사용되지 않음
              final String bsNm = arrivalData['bsNm'] ?? '정보 없음';
              final String arrState = arrivalData['arrState'] ?? '정보 없음';
              final int bsGap = arrivalData['bsGap'] ?? 0;
              final String busTCd2 = arrivalData['busTCd2'] ?? 'N';
              // final String busTCd3 = arrivalData['busTCd3'] ?? 'N'; // 사용되지 않음
              final String vhcNo2 = arrivalData['vhcNo2'] ?? '';

              // 저상버스 여부 확인 (busTCd2가 "1"이면 저상버스)
              final bool isLowFloor = busTCd2 == '1';

              // 운행 종료 여부 확인
              final bool isOutOfService = arrState == '운행종료' ||
                  arrState == '운행 종료' ||
                  arrState == '-';

              // 도착 예정 시간 처리
              String estimatedTime = arrState;
              if (estimatedTime.contains('출발예정')) {
                estimatedTime = estimatedTime.replaceAll('출발예정', '').trim();
                if (estimatedTime.isEmpty) {
                  estimatedTime = '출발예정';
                }
              }

              final busInfo = BusInfo(
                busNumber: vhcNo2.isNotEmpty ? vhcNo2 : routeNo,
                isLowFloor: isLowFloor,
                currentStation: bsNm,
                remainingStops: bsGap.toString(),
                estimatedTime: estimatedTime,
                isOutOfService: isOutOfService,
              );

              busInfoList.add(busInfo);
            }

            if (busInfoList.isNotEmpty) {
              final arrival = BusArrival(
                routeId: routeData['routeId'] ?? '',
                routeNo: routeNo,
                direction: '',
                busInfoList: busInfoList,
              );
              arrivals.add(arrival);
            }
          }

          debugPrint('정류장 버스 정보 조회 완료: ${arrivals.length}개 버스');

          // 버스 정보를 HTML로 전달
          final busInfoText = _formatBusInfoForMap(arrivals);
          final escapedBusInfo =
              busInfoText.replaceAll("'", "\\'").replaceAll('\n', '\\n');

          debugPrint('HTML로 전달할 버스 정보: $busInfoText');

          if (_mapReady) {
            final latitude = selectedStation.latitude;
            final longitude = selectedStation.longitude;

            if (_mapReady && latitude != null && longitude != null) {
              _webViewController.runJavaScript(
                  'updateStationBusInfo("$stationName", "$stationType", \'$escapedBusInfo\', $latitude, $longitude);');
            }
          }
        } else {
          debugPrint('버스 정보 없음 또는 빈 응답');
          if (_mapReady) {
            _webViewController.runJavaScript(
                'updateStationBusInfo("$stationName", "$stationType", "도착 예정 버스 없음");');
          }
        }
      } catch (platformError) {
        debugPrint('버스 정보 조회 오류: $platformError');
        if (_mapReady) {
          _webViewController.runJavaScript(
              'updateStationBusInfo("$stationName", "$stationType", "버스 정보 조회 실패: $platformError");');
        }
      }
    } catch (e) {
      debugPrint('정류장 버스 정보 업데이트 오류: $e');
    }
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

    try {
      // 로딩 표시
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
              Text('주변 정류장을 검색하고 있습니다...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      // 주변 정류장 검색 (반경 2km로 증가)
      final stations = await ApiService.findNearbyStations(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        radiusMeters: 2000.0,
      );

      setState(() {
        _nearbyStations = stations;
      });

      // 지도에 마커 업데이트
      if (_mapReady) {
        _addMarkers();
      }

      // 결과 알림
      if (mounted) {
        if (stations.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('주변 ${stations.length}개 정류장을 찾았습니다.'),
              action: SnackBarAction(
                label: '확인',
                onPressed: () {},
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        } else {
          // 로컬 DB에서 정류장을 찾지 못한 경우
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('근처에 정류장을 찾지 못했습니다.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('주변 정류장 검색 중 오류가 발생했습니다: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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
                'addBusMarker($lat, $lng, "$busNumber", "${widget.routeId}");');
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _busPositionTimer?.cancel();
    super.dispose();
  }
}
