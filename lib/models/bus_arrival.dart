import 'bus_info.dart';

class BusArrival {
  final String routeNo;
  final String routeId;
  final List<BusInfo> busInfoList;
  final String direction;

  BusArrival({
    required this.routeNo,
    required this.routeId,
    required this.busInfoList,
    this.direction = '',
  });

  factory BusArrival.fromJson(Map<String, dynamic> json) {
    final List<dynamic> busList = json['busInfoList'] ?? [];

    return BusArrival(
      routeNo: (json['routeNo'] ?? '').toString(),
      routeId: (json['routeId'] ?? '').toString(),
      busInfoList: busList.map((info) => BusInfo.fromJson(info)).toList(),
      direction: (json['direction'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'routeNo': routeNo,
      'routeId': routeId,
      'busInfoList': busInfoList.map((info) => info.toJson()).toList(),
      'direction': direction,
    };
  }

  BusInfo? get firstBus => busInfoList.isNotEmpty ? busInfoList[0] : null;

  BusInfo? get secondBus => busInfoList.length > 1 ? busInfoList[1] : null;

  bool get hasArrival => busInfoList.isNotEmpty;

  bool get hasLowFloorBus => busInfoList.any((bus) => bus.isLowFloor);

  bool get hasArrivalInfo =>
      busInfoList.any((bus) => !bus.isOutOfService && bus.getRemainingMinutes() > 0);

  int getFirstArrivalMinutes() {
    return firstBus?.getRemainingMinutes() ?? 0;
  }

  String getFirstArrivalTimeText() {
    final first = firstBus;
    if (first == null) {
      return '\ub3c4\ucc29 \uc815\ubcf4 \uc5c6\uc74c';
    }

    if (first.isOutOfService) {
      return '\uc6b4\ud589 \uc885\ub8cc';
    }

    final minutes = first.getRemainingMinutes();
    if (minutes < 0) {
      return '\uc6b4\ud589 \uc885\ub8cc';
    }
    if (minutes == 0) {
      return '\uace7 \ub3c4\ucc29';
    }
    return '$minutes\ubd84';
  }

  String getSecondArrivalTimeText() {
    final second = secondBus;
    if (second == null) {
      return '';
    }

    if (second.isOutOfService) {
      return '\uc6b4\ud589 \uc885\ub8cc';
    }

    final minutes = second.getRemainingMinutes();
    if (minutes < 0) {
      return '\uc6b4\ud589 \uc885\ub8cc';
    }
    if (minutes == 0) {
      return '\uace7 \ub3c4\ucc29';
    }
    return '$minutes\ubd84';
  }

  String getSummaryText() {
    if (!hasArrival) {
      return '\ub3c4\ucc29 \uc608\uc815 \ubc84\uc2a4 \uc5c6\uc74c';
    }

    final first = getFirstArrivalTimeText();
    final second = getSecondArrivalTimeText();

    if (second.isEmpty) {
      return first;
    }
    return '$first, $second';
  }

  BusArrival copyWith({
    String? routeNo,
    String? routeId,
    List<BusInfo>? busInfoList,
    String? direction,
  }) {
    return BusArrival(
      routeNo: routeNo ?? this.routeNo,
      routeId: routeId ?? this.routeId,
      busInfoList: busInfoList ?? this.busInfoList,
      direction: direction ?? this.direction,
    );
  }

  @override
  String toString() {
    return 'BusArrival{routeNo: $routeNo, routeId: $routeId, busCount: \${busInfoList.length}}';
  }
}
