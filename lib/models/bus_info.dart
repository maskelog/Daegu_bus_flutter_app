class BusInfo {
  final String busNumber;
  final String currentStation;
  final String remainingStops;
  final String estimatedTime;
  final bool isLowFloor;
  final bool isOutOfService;
  final String? busTCd2;

  BusInfo({
    required this.busNumber,
    required this.currentStation,
    required this.remainingStops,
    required this.estimatedTime,
    this.isLowFloor = false,
    this.isOutOfService = false,
    this.busTCd2,
  });

  factory BusInfo.fromJson(Map<String, dynamic> json) {
    final estTime = (json['estimatedTime'] ?? '').toString();
    final busTCd3 = json['busTCd3']?.toString();
    final outOfService = estTime.contains('\uc6b4\ud589\uc885\ub8cc') ||
        estTime.contains('\uc6b4\ud589 \uc885\ub8cc') ||
        estTime == '-' ||
        json['isOutOfService'] == true ||
        busTCd3 == '1';

    final String? busTCd2 = json['busTCd2']?.toString();
    return BusInfo(
      busNumber: (json['busNumber'] ?? '').toString(),
      currentStation: (json['currentStation'] ?? '').toString(),
      remainingStops: (json['remainingStops'] ?? '0').toString(),
      estimatedTime: estTime,
      isLowFloor: busTCd2 == 'D',
      isOutOfService: outOfService,
      busTCd2: busTCd2,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'busNumber': busNumber,
      'currentStation': currentStation,
      'remainingStops': remainingStops,
      'estimatedTime': estimatedTime,
      'isLowFloor': isLowFloor,
      'isOutOfService': isOutOfService,
      'busTCd2': busTCd2,
    };
  }

  int getRemainingMinutes() {
    if (isOutOfService) return -1;

    final time = estimatedTime.trim();
    if (time.isEmpty) return 0;

    if (time.contains('\uace7 \ub3c4\ucc29') ||
        time.contains('\uace7\ub3c4\ucc29') ||
        time.contains('\uc9c4\uc785') ||
        time == '0' ||
        time == '0\ubd84') {
      return 0;
    }

    if (time.contains('\uc6b4\ud589\uc885\ub8cc') ||
        time.contains('\uc6b4\ud589 \uc885\ub8cc') ||
        time == '-' ||
        time.contains('\ucd9c\ubc1c\uc608\uc815') ||
        time.contains('\uae30\uc810\ucd9c\ubc1c')) {
      return -1;
    }

    final numberMatch = RegExp(r'(\d+)').firstMatch(time);
    if (numberMatch != null) {
      return int.tryParse(numberMatch.group(1) ?? '') ?? 0;
    }

    final stops = int.tryParse(remainingStops.replaceAll(RegExp(r'[^0-9]'), ''));
    if (stops != null) {
      return stops * 2;
    }

    return 0;
  }

  String getRemainingTimeText() {
    if (isOutOfService) {
      return '\uc6b4\ud589 \uc885\ub8cc';
    }

    final minutes = getRemainingMinutes();
    if (minutes < 0) {
      return '\uc6b4\ud589 \uc885\ub8cc';
    }
    if (minutes == 0) {
      return '\uace7 \ub3c4\ucc29';
    }
    return '${minutes}\ubd84';
  }

  String getLowFloorText() {
    return isLowFloor ? '[\uc800\uc0c1]' : '';
  }

  BusInfo copyWith({
    String? busNumber,
    String? currentStation,
    String? remainingStops,
    String? estimatedTime,
    bool? isLowFloor,
    bool? isOutOfService,
  }) {
    return BusInfo(
      busNumber: busNumber ?? this.busNumber,
      currentStation: currentStation ?? this.currentStation,
      remainingStops: remainingStops ?? this.remainingStops,
      estimatedTime: estimatedTime ?? this.estimatedTime,
      isLowFloor: isLowFloor ?? this.isLowFloor,
      isOutOfService: isOutOfService ?? this.isOutOfService,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is BusInfo &&
        other.busNumber == busNumber &&
        other.currentStation == currentStation &&
        other.remainingStops == remainingStops &&
        other.estimatedTime == estimatedTime &&
        other.isLowFloor == isLowFloor &&
        other.isOutOfService == isOutOfService;
  }

  @override
  int get hashCode {
    return busNumber.hashCode ^
        currentStation.hashCode ^
        remainingStops.hashCode ^
        estimatedTime.hashCode ^
        isLowFloor.hashCode ^
        isOutOfService.hashCode;
  }

  @override
  String toString() {
    return 'BusInfo{busNumber: $busNumber, remainingTime: ${getRemainingMinutes()}\ubd84, currentStation: $currentStation, isLowFloor: $isLowFloor}';
  }
}
