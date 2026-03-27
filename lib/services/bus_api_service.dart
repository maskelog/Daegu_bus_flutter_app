import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/bus_arrival.dart';
import '../models/bus_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/api_result.dart';
import '../utils/bus_cache_manager.dart';
import '../utils/debouncer.dart';

class BusApiService {
  static const MethodChannel _channel =
      MethodChannel('com.devground.daegubus/bus_api');

  // 싱글톤 패턴 구현
  static final BusApiService _instance = BusApiService._internal();

  factory BusApiService() => _instance;

  BusApiService._internal() {
    _initializeCacheManager();
  }

  // 캐시 매니저 인스턴스
  final _cacheManager = BusCacheManager.instance;

  // API 호출 디바운서
  final _debouncer = DebounceManager.getDebouncer(
    'bus_api_service',
    delay: const Duration(milliseconds: 800),
  );
  final List<Completer<List<StationSearchResult>>> _pendingSearchCompleters = [];

  /// 캐시 매니저 초기화
  Future<void> _initializeCacheManager() async {
    try {
      await _cacheManager.initialize();
    } catch (e) {
      debugPrint('⚠️ 캐시 매니저 초기화 실패: $e');
    }
  }

  // 정류장 검색 메소드 (캐싱 및 디바운싱 적용)
  Future<BusApiResult<List<StationSearchResult>>> searchStationsWithResult(
      String searchText) async {
    if (searchText.trim().isEmpty) {
      return BusApiResult.error(BusApiError.invalidParameter,
          message: '검색어를 입력해주세요');
    }

    try {
      debugPrint('🔍 [검색 요청] "$searchText"');
      final apiStartTime = DateTime.now();

      final String jsonResult = await _channel.invokeMethod('searchStations', {
        'searchText': searchText.trim(),
      });

      final apiDuration =
          DateTime.now().difference(apiStartTime).inMilliseconds;
      debugPrint('🔍 [검색 응답] 소요시간: ${apiDuration}ms');

      if (jsonResult.isEmpty || jsonResult == '[]') {
        return BusApiResult.error(BusApiError.noData,
            message: '"$searchText"에 대한 검색 결과가 없습니다');
      }

      final List<dynamic> decoded = jsonDecode(jsonResult);
      final results = decoded
          .map((station) => StationSearchResult.fromJson(station))
          .toList();

      if (results.isEmpty) {
        return BusApiResult.error(BusApiError.noData, message: '검색 결과가 없습니다');
      }

      debugPrint('✅ [검색 성공] ${results.length}개 정류장 찾음');
      return BusApiResult.success(results);
    } on PlatformException catch (e) {
      debugPrint('❌ [검색 오류] ${e.message}');
      return BusApiResult.error(BusApiError.serverError, message: e.message);
    } catch (e) {
      debugPrint('❌ [검색 오류] $e');
      return BusApiResult.error(BusApiError.parsingError,
          message: e.toString());
    }
  }

  // 기존 메소드 호환성 유지 (디바운싱 적용)
  Future<List<StationSearchResult>> searchStations(String searchText) async {
    // ????? ??
    final completer = Completer<List<StationSearchResult>>();
    _pendingSearchCompleters.add(completer);

    _debouncer.call(() async {
      final pending = List<Completer<List<StationSearchResult>>>.from(
        _pendingSearchCompleters,
      );
      _pendingSearchCompleters.clear();

      try {
        final result = await searchStationsWithResult(searchText);
        final data = result.dataOrDefault([]);
        for (final pendingCompleter in pending) {
          if (!pendingCompleter.isCompleted) {
            pendingCompleter.complete(data);
          }
        }
      } catch (e) {
        for (final pendingCompleter in pending) {
          if (!pendingCompleter.isCompleted) {
            pendingCompleter.complete(<StationSearchResult>[]);
          }
        }
      }
    });

    return completer.future;
  }

// 정류장 도착 정보 조회 메소드 (캐싱 및 에러 처리 개선)
  Future<BusApiResult<List<BusArrival>>> getStationInfoWithResult(
      String stationId) async {
    try {
      // 캐시에서 먼저 확인
      final cachedData = await _cacheManager.getCachedBusArrivals(stationId);
      if (cachedData != null) {
        debugPrint('🎯 캐시에서 버스 정보 반환: ${cachedData.length}개 노선');
        return BusApiResult.success(cachedData);
      }

      debugPrint('🚌 [API 호출] 버스 정보 조회: stationId=$stationId');
      final apiStartTime = DateTime.now();

      final String jsonResult = await _channel.invokeMethod('getStationInfo', {
        'stationId': stationId,
      });

      final apiDuration =
          DateTime.now().difference(apiStartTime).inMilliseconds;
      debugPrint('🚌 [API 응답] 소요시간: ${apiDuration}ms');

      if (jsonResult.isEmpty || jsonResult == '[]') {
        return BusApiResult.error(BusApiError.noData,
            message: '도착 예정 버스 정보가 없습니다');
      }

      final List<dynamic> decoded = jsonDecode(jsonResult);
      final List<BusArrival> arrivals = await _parseBusArrivals(decoded);

      if (arrivals.isEmpty) {
        return BusApiResult.error(BusApiError.noData,
            message: '유효한 버스 정보가 없습니다');
      }

      // 유효한 데이터만 캐시에 저장
      await _cacheManager.cacheBusArrivals(stationId, arrivals);
      debugPrint('✅ [API 성공] ${arrivals.length}개 노선 정보 수신 및 캐시 저장 완료');

      return BusApiResult.success(arrivals);
    } on PlatformException catch (e) {
      debugPrint('❌ [Platform 오류] ${e.message}');
      return BusApiResult.error(BusApiError.serverError, message: e.message);
    } catch (e) {
      debugPrint('❌ [일반 오류] $e');
      return BusApiResult.error(BusApiError.parsingError,
          message: e.toString());
    }
  }

  // 기존 메소드 호환성 유지
  Future<List<BusArrival>> getStationInfo(String stationId) async {
    final result = await getStationInfoWithResult(stationId);
    return result.dataOrDefault([]);
  }

  // 버스 도착 정보 조회 메소드 개선
  Future<BusArrivalInfo?> getBusArrivalByRouteId(
      String stationId, String routeId) async {
    try {
      // 입력 유효성 검사
      if (stationId.isEmpty || routeId.isEmpty) {
        debugPrint('❌ [ERROR] 정류장 ID 또는 노선 ID가 비어있습니다');
        return null;
      }

      debugPrint(
          '🚌 [API 호출] 버스 정보 조회: routeId=$routeId, stationId=$stationId');
      final apiStartTime = DateTime.now();

      // API 응답 시간 및 성공 여부 기록 (분석용)
      bool apiSuccess = false;
      String? errorMsg;
      BusArrivalInfo? result;

      try {
        final dynamic response =
            await _channel.invokeMethod('getBusArrivalByRouteId', {
          'stationId': stationId,
          'routeId': routeId,
        });

        final apiDuration =
            DateTime.now().difference(apiStartTime).inMilliseconds;
        debugPrint('🚌 [API 응답] 소요시간: ${apiDuration}ms');

        // 응답 타입 로깅
        if (response == null) {
          debugPrint('❌ [ERROR] 응답이 null입니다');
          return null;
        }

        debugPrint('🚌 [API 응답] 타입: ${response.runtimeType}');

        // 응답 파싱 (여러 형식 처리)
        result = await _parseApiResponse(response, routeId);
        apiSuccess = result != null;

        // 파싱 결과 로깅
        if (result != null) {
          final busCount = result.bus.length;
          debugPrint('✅ [API 성공] $busCount개 버스 정보 수신');
          _saveSuccessfulResponse(response, apiDuration); // 성공한 응답 저장 (분석용)
        } else {
          debugPrint('⚠️ [API 오류] 데이터 파싱 실패');
          errorMsg = 'response parsing failed';
        }
      } catch (e) {
        apiSuccess = false;
        errorMsg = e.toString();
        debugPrint('❌ [API 오류] ${e.toString()}');
      }

      // API 호출 결과 저장 (나중에 분석용)
      final apiDuration =
          DateTime.now().difference(apiStartTime).inMilliseconds;
      await _saveApiCallResult(
        routeId: routeId,
        stationId: stationId,
        success: apiSuccess,
        duration: apiDuration,
        errorMsg: errorMsg,
      );

      // ✨ Native로 버스 정보 전송 (Flutter-Native 동기화)
      if (result != null && result.bus.isNotEmpty) {
        try {
          final firstBus = result.bus.first;
          final remainingMinutes = _extractRemainingMinutes(firstBus.estimatedTime);
          
          await _channel.invokeMethod('updateBusInfo', {
            'routeId': routeId,
            'busNo': result.name,
            'stationName': stationId, // stationName은 호출자가 제공해야 더 정확함
            'remainingMinutes': remainingMinutes,
            'currentStation': firstBus.currentStation,
            'estimatedTime': firstBus.estimatedTime,
            'isLowFloor': false, // BusInfoData에 isLowFloor 필드가 없으면 false
          });
          
          debugPrint('✅ Native로 버스 정보 전송 완료: ${result.name}, $remainingMinutes분');
        } catch (e) {
          debugPrint('⚠️ Native 버스 정보 전송 실패: $e');
          // 에러가 발생해도 result는 반환 (동기화는 선택사항)
        }
      }

      return result;
    } catch (e) {
      debugPrint('❌ [ERROR] getBusArrivalByRouteId 실행 중 오류: $e');
      return null;
    }
  }

  /// estimatedTime 문자열에서 숫자(분)를 추출하는 헬퍼 함수
  int _extractRemainingMinutes(String estimatedTime) {
    try {
      // 숫자만 추출 (예: "5분" -> 5, "곧 도착" -> 0)
      final match = RegExp(r'\d+').firstMatch(estimatedTime);
      if (match != null) {
        return int.parse(match.group(0)!);
      }
      // "곧 도착", "운행종료" 등의 경우
      if (estimatedTime.contains('곧') || estimatedTime.contains('도착')) {
        return 0;
      }
      return 0;
    } catch (e) {
      return 0;
    }
  }

  /// API 응답 파싱 분리 (복잡한 로직 모듈화)
  Future<BusArrivalInfo?> _parseApiResponse(
      dynamic response, String routeId) async {
    try {
      // String 응답 처리
      if (response is String) {
        debugPrint('🚌 [API 파싱] String 형식 응답 처리');

        // 빈 응답 처리
        if (response.isEmpty || response == 'null' || response == '[]') {
          debugPrint('⚠️ [API 파싱] 빈 응답: "$response"');
          return null;
        }

        // JSON 파싱 시도
        try {
          final dynamic decoded = jsonDecode(response);
          return _processJsonData(decoded, routeId);
        } catch (e) {
          debugPrint('❌ [API 파싱] JSON 파싱 오류: $e');
          return null;
        }
      }
      // Map 응답 처리
      else if (response is Map<String, dynamic>) {
        debugPrint('🚌 [API 파싱] Map 형식 응답 처리');
        return _processJsonData(response, routeId);
      }
      // List 응답 처리
      else if (response is List) {
        debugPrint('🚌 [API 파싱] List 형식 응답 처리');
        if (response.isEmpty) {
          debugPrint('⚠️ [API 파싱] 빈 리스트');
          return null;
        }

        if (response.first is Map<String, dynamic>) {
          return _processJsonData(response.first, routeId);
        } else {
          debugPrint(
              '❌ [API 파싱] 지원되지 않는 리스트 항목 타입: ${response.first.runtimeType}');
          return null;
        }
      }
      // 기타 타입 처리
      else {
        debugPrint('❌ [API 파싱] 지원되지 않는 응답 타입: ${response.runtimeType}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ [API 파싱] 파싱 중 오류: $e');
      return null;
    }
  }

  /// JSON 데이터 처리 (다양한 형식에 대응)
  BusArrivalInfo? _processJsonData(dynamic data, String routeId) {
    try {
      // 배열 형식 처리
      if (data is List && data.isNotEmpty) {
        debugPrint('🚌 [JSON 처리] 배열 형식, 첫 번째 항목 사용');
        return BusArrivalInfo.fromJson(data[0]);
      }

      // 자동 알람 응답 형식 처리
      if (data is Map<String, dynamic> && data.containsKey('routeNo')) {
        debugPrint('🚌 [JSON 처리] 자동 알람 응답 형식 감지');

        final Map<String, dynamic> formattedResponse = {
          'name': data['routeNo'] ?? '',
          'sub': '',
          'id': routeId,
          'forward': data['moveDir'] ?? '알 수 없음',
          'bus': []
        };

        // arrList 필드 처리
        if (data.containsKey('arrList') && data['arrList'] is List) {
          formattedResponse['bus'] = _formatBusListFromArrList(data['arrList']);
        }

        return BusArrivalInfo.fromJson(formattedResponse);
      }

      // 일반 객체 형식 처리
      if (data is Map<String, dynamic>) {
        return BusArrivalInfo.fromJson(data);
      }

      debugPrint('❌ [JSON 처리] 지원되지 않는 JSON 구조: ${data.runtimeType}');
      return null;
    } catch (e) {
      debugPrint('❌ [JSON 처리] 처리 중 오류: $e');
      return null;
    }
  }

  /// arrList 필드를 버스 정보 리스트로 변환
  List<Map<String, dynamic>> _formatBusListFromArrList(List<dynamic> arrList) {
    final List<Map<String, dynamic>> busList = [];

    for (var arr in arrList) {
      if (arr is Map<String, dynamic>) {
        final Map<String, dynamic> busInfo = {
          'busNumber': arr['vhcNo2'] ?? '',
          'currentStation': arr['bsNm'] ?? '정보 없음',
          'remainingStops': '${arr['bsGap'] ?? 0} 개소',
          'estimatedTime': arr['arrState'] ?? '${arr['bsGap'] ?? 0}분',
          'isLowFloor': arr['busTCd2'] == '1',
          'isOutOfService': arr['busTCd3'] == '1'
        };
        busList.add(busInfo);
      }
    }

    return busList;
  }

  /// API 호출 결과 저장 (분석용)
  Future<void> _saveApiCallResult({
    required String routeId,
    required String stationId,
    required bool success,
    required int duration,
    String? errorMsg,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().toIso8601String();

      // 최근 API 호출 결과 목록 가져오기
      final apiCallHistoryJson = prefs.getString('api_call_history') ?? '[]';
      final List<dynamic> apiCallHistory = jsonDecode(apiCallHistoryJson);

      // 최근 20개 결과만 유지
      if (apiCallHistory.length >= 20) {
        apiCallHistory.removeAt(0);
      }

      // 새 결과 추가
      apiCallHistory.add({
        'routeId': routeId,
        'stationId': stationId,
        'success': success,
        'timestamp': now,
        'duration': duration,
        'error': errorMsg,
      });

      // 결과 저장
      await prefs.setString('api_call_history', jsonEncode(apiCallHistory));
    } catch (e) {
      debugPrint('⚠️ API 호출 결과 저장 중 오류: $e');
    }
  }

  /// 성공한 API 응답 저장 (분석용)
  /// 버스 도착 정보 JSON 파싱 (개선된 버전)
  Future<List<BusArrival>> _parseBusArrivals(List<dynamic> decoded) async {
    final List<BusArrival> arrivals = [];

    for (final routeData in decoded) {
      if (routeData is! Map<String, dynamic>) continue;

      final String routeNo = routeData['routeNo'] ?? '';
      final List<dynamic>? arrList = routeData['arrList'];

      if (arrList == null || arrList.isEmpty) continue;

      final List<BusInfo> busInfoList = [];

      for (final arrivalData in arrList) {
        if (arrivalData is! Map<String, dynamic>) continue;

        final String bsNm = arrivalData['bsNm'] ?? '정보 없음';
        final String arrState = arrivalData['arrState'] ?? '정보 없음';
        final int bsGap = arrivalData['bsGap'] ?? 0;
        final String busTCd2 = arrivalData['busTCd2'] ?? 'N';
        final String busTCd3 = arrivalData['busTCd3'] ?? 'N';
        final String vhcNo2 = arrivalData['vhcNo2'] ?? '';

        // 저상버스 여부 확인 (busTCd2가 "1"이면 저상버스)
        final bool isLowFloor = busTCd2 == '1';

        // 운행 종료 여부 확인 (개선된 조건)
        final bool isOutOfService = arrState == '운행종료' ||
            arrState == '운행 종료' ||
            arrState == '-' ||
            busTCd3 == '1' ||
            arrState.contains('종료');

        // 도착 예정 시간 처리 (개선)
        String estimatedTime = arrState;
        if (estimatedTime.contains('출발예정')) {
          estimatedTime = estimatedTime.replaceAll('출발예정', '').trim();
          if (estimatedTime.isEmpty) {
            estimatedTime = '출발예정';
          }
        }

        // 유효하지 않은 데이터 필터링
        if (estimatedTime.isEmpty || estimatedTime == '정보 없음') {
          continue;
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

      // 유효한 버스 정보가 있는 경우에만 추가
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

    return arrivals;
  }

  void _saveSuccessfulResponse(dynamic response, int duration) {
    try {
      debugPrint('✅ API 응답 저장 (${duration}ms)');
      // TODO: 필요한 경우 성공한 응답 저장 로직 구현
    } catch (e) {
      debugPrint('⚠️ API 응답 저장 중 오류: $e');
    }
  }

  // 버스 노선 정보 조회 메소드
  Future<Map<String, dynamic>?> getBusRouteInfo(String routeId) async {
    try {
      final String jsonResult = await _channel.invokeMethod('getBusRouteInfo', {
        'routeId': routeId,
      });

      return jsonDecode(jsonResult);
    } on PlatformException catch (e) {
      debugPrint('버스 노선 정보 조회 오류: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('예상치 못한 오류: $e');
      return null;
    }
  }

  // 실시간 버스 위치 정보 조회 메소드
  Future<Map<String, dynamic>?> getBusPositionInfo(String routeId) async {
    try {
      final String jsonResult =
          await _channel.invokeMethod('getBusPositionInfo', {
        'routeId': routeId,
      });

      return jsonDecode(jsonResult);
    } on PlatformException catch (e) {
      debugPrint('실시간 버스 위치 정보 조회 오류: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('예상치 못한 오류: $e');
      return null;
    }
  }

  // BusArrivalInfo를 BusArrival로 변환하는 헬퍼 메소드
  BusArrival convertToBusArrival(BusArrivalInfo info, String stationId) {
    List<BusInfo> busInfoList = info.bus.map((busInfo) {
      // 버스 번호에서 저상버스 정보 추출
      bool isLowFloor = busInfo.busNumber.contains('저상');
      String busNumber =
          busInfo.busNumber.replaceAll(RegExp(r'\(저상\)|\(일반\)'), '');

      // 남은 정류소에서 숫자만 추출
      String remainingStations = busInfo.remainingStations;

      // 도착 예정 시간 처리
      String estimatedTime = busInfo.estimatedTime;

      // 운행 종료 여부 확인
      bool isOutOfService =
          estimatedTime == '운행종료' || estimatedTime == '운행 종료';

      return BusInfo(
        busNumber: busNumber,
        isLowFloor: isLowFloor,
        currentStation: busInfo.currentStation,
        remainingStops: remainingStations,
        estimatedTime: estimatedTime,
        isOutOfService: isOutOfService,
      );
    }).toList();

    return BusArrival(
      routeId: info.id,
      routeNo: info.name,
      direction: info.forward,
      busInfoList: busInfoList,
    );
  }
}

// 정류장 검색 결과 데이터 클래스
class StationSearchResult {
  final String bsId;
  final String bsNm;
  final double? latitude;
  final double? longitude;

  StationSearchResult({
    required this.bsId,
    required this.bsNm,
    this.latitude,
    this.longitude,
  });

  factory StationSearchResult.fromJson(Map<String, dynamic> json) {
    return StationSearchResult(
      bsId: json['bsId'] as String,
      // 네이티브 쪽에서는 컬럼명이 "stop_name"일 수 있으므로 fallback 처리
      bsNm: json['bsNm'] ?? json['stop_name'] ?? '',
      latitude: json['latitude'] != null
          ? (json['latitude'] as num).toDouble()
          : null,
      longitude: json['longitude'] != null
          ? (json['longitude'] as num).toDouble()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bsId': bsId,
      'bsNm': bsNm,
      'latitude': latitude,
      'longitude': longitude,
    };
  }
}

// 버스 도착 정보 결과 데이터 클래스
class BusArrivalInfo {
  final String name; // 노선 이름
  final String sub; // 노선 부제목
  final String id; // 노선 ID
  final String forward; // 방면 (종점)
  final List<BusInfoData> bus; // 버스 목록

  BusArrivalInfo({
    required this.name,
    required this.sub,
    required this.id,
    required this.forward,
    required this.bus,
  });

  factory BusArrivalInfo.fromJson(Map<String, dynamic> json) {
    return BusArrivalInfo(
      name: json['name'] ?? '',
      sub: json['sub'] ?? '',
      id: json['id'] ?? '',
      forward: json['forward'] ?? '',
      bus: (json['bus'] as List? ?? [])
          .map((bus) => BusInfoData.fromJson(bus))
          .toList(),
    );
  }
}

class BusInfoData {
  final String busNumber;
  final String currentStation;
  final String remainingStations;
  final String estimatedTime;

  BusInfoData({
    required this.busNumber,
    required this.currentStation,
    required this.remainingStations,
    required this.estimatedTime,
  });

  factory BusInfoData.fromJson(Map<String, dynamic> json) {
    // 자동 알람에서 오는 응답 형식 처리
    if (json.containsKey('vhcNo2') || json.containsKey('bsNm')) {
      return BusInfoData(
        busNumber: json['vhcNo2'] ?? '',
        currentStation: json['bsNm'] ?? '',
        remainingStations: '${json['bsGap'] ?? 0} 개소',
        estimatedTime: json['arrState'] ?? '${json['bsGap'] ?? 0}분',
      );
    }

    // 기본 형식 처리
    return BusInfoData(
      busNumber: json['버스번호'] ?? '',
      currentStation: json['현재정류소'] ?? '',
      remainingStations: json['남은정류소'] ?? '',
      estimatedTime: json['도착예정소요시간'] ?? '',
    );
  }
}
