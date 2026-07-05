import 'dart:convert';

import '../../main.dart' show logMessage, LogLevel;
import 'arrival_time_parser.dart';

/// 네이티브 getBusArrivalByRouteId 응답에서 추출한 자동 알람용 도착 정보.
class AutoAlarmArrival {
  const AutoAlarmArrival({
    required this.remainingMinutes,
    required this.currentStation,
  });

  final int remainingMinutes;
  final String currentStation;
}

/// 네이티브 API 응답(String/List/Map)에서 [routeNo]·[routeId] 노선의 도착 정보를 추출한다.
///
/// 응답 형태가 제각각이라(JSON 문자열, arrList/bus 키를 가진 Map, List)
/// 순서대로 정규화한 뒤, 노선 매칭 실패 시 첫 항목을 사용한다.
/// 파싱 실패·도착 정보 없음이면 null을 반환한다 (원인은 로그로 남김).
AutoAlarmArrival? parseAutoAlarmArrival(
  dynamic result, {
  required String routeNo,
  required String routeId,
}) {
  try {
    dynamic parsedData;
    List<dynamic> arrivals = [];

    // 응답 타입별 처리
    if (result is String) {
      logMessage('🚌 [API 파싱] String 형식 응답 처리', level: LogLevel.debug);
      try {
        parsedData = jsonDecode(result);
      } catch (e) {
        logMessage('❌ JSON 파싱 오류: $e', level: LogLevel.error);
        return null;
      }
    } else if (result is List) {
      logMessage('🚌 [API 파싱] List 형식 응답 처리', level: LogLevel.debug);
      parsedData = result;
    } else if (result is Map) {
      logMessage('🚌 [API 파싱] Map 형식 응답 처리', level: LogLevel.debug);
      parsedData = result;
    } else {
      logMessage(
        '❌ 지원되지 않는 응답 타입: ${result.runtimeType}',
        level: LogLevel.error,
      );
      return null;
    }

    // parsedData 구조 분석 및 arrivals 추출
    if (parsedData is List) {
      arrivals = parsedData;
    } else if (parsedData is Map) {
      // 자동 알람 응답 형식: { "routeNo": "623", "arrList": [...] }
      if (parsedData.containsKey('arrList')) {
        arrivals = parsedData['arrList'] as List? ?? [];
        logMessage(
          '🚌 [API 파싱] arrList에서 도착 정보 추출: ${arrivals.length}개',
          level: LogLevel.debug,
        );
      } else if (parsedData.containsKey('bus')) {
        arrivals = parsedData['bus'] as List? ?? [];
        logMessage(
          '🚌 [API 파싱] bus에서 도착 정보 추출: ${arrivals.length}개',
          level: LogLevel.debug,
        );
      } else {
        logMessage(
          '❌ 예상치 못한 Map 구조: ${parsedData.keys}',
          level: LogLevel.error,
        );
        return null;
      }
    }

    logMessage(
      '🚌 [API 파싱] 파싱된 arrivals: ${arrivals.length}개 항목',
      level: LogLevel.debug,
    );

    if (arrivals.isEmpty) {
      logMessage('⚠️ 도착 정보 없음', level: LogLevel.warning);
      return null;
    }

    // 알람에 설정된 노선 번호와 일치하는 버스 찾기
    dynamic busInfo;
    bool found = false;
    for (var bus in arrivals) {
      if (bus is Map) {
        final busRouteNo = bus['routeNo']?.toString() ?? '';
        final busRouteId = bus['routeId']?.toString() ?? '';
        // routeNo 또는 routeId로 매칭
        if (busRouteNo == routeNo || busRouteId == routeId) {
          busInfo = bus;
          found = true;
          logMessage(
            '✅ 일치하는 노선 찾음: $routeNo (routeNo: $busRouteNo, routeId: $busRouteId)',
            level: LogLevel.debug,
          );
          break;
        }
      }
    }

    // 일치하는 노선이 없으면 첫 번째 항목 사용
    if (!found) {
      busInfo = arrivals.first;
      final firstRouteNo = busInfo['routeNo']?.toString() ?? '정보 없음';
      logMessage(
        '⚠️ 일치하는 노선 없음, 첫 번째 항목 사용: $firstRouteNo',
        level: LogLevel.warning,
      );
    }

    if (busInfo == null) return null;

    // 도착 정보 추출 - 다양한 필드명 지원
    final estimatedTime = busInfo['arrState'] ??
        busInfo['estimatedTime'] ??
        busInfo['도착예정소요시간'] ??
        "정보 없음";

    final currentStation = busInfo['bsNm'] ??
        busInfo['currentStation'] ??
        busInfo['현재정류소'] ??
        '정보 없음';

    final int remainingMinutes = parseRemainingMinutes(estimatedTime);

    logMessage(
      '🚌 [정보 추출] estimatedTime: $estimatedTime, currentStation: $currentStation, remainingMinutes: $remainingMinutes',
      level: LogLevel.debug,
    );

    return AutoAlarmArrival(
      remainingMinutes: remainingMinutes,
      currentStation: currentStation.toString(),
    );
  } catch (e) {
    logMessage('❌ 버스 정보 파싱 오류: $e', level: LogLevel.error);
    logMessage('원본 응답: $result', level: LogLevel.debug);
    return null;
  }
}
