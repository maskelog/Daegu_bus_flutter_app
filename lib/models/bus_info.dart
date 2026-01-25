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
    final outOfService = estTime.contains('운행종료') ||
        estTime.contains('운행 종료') ||
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

    if (time.contains('곧 도착') ||
        time.contains('곧도착') ||
        time.contains('진입') ||
        time == '0' ||
        time == '0분') {
      return 0;
    }

    if (time.contains('운행종료') ||
        time.contains('운행 종료') ||
        time == '-' ||
        time.contains('출발예정') ||
        time.contains('기점출발')) {
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
      return '운행 종료';
    }

    final minutes = getRemainingMinutes();
    if (minutes < 0) {
      return '운행 종료';
    }
    if (minutes == 0) {
      return '곧 도착';
    }
    return '${minutes}분';
  }

  String getLowFloorText() {
    return isLowFloor ? '[저상]' : '';
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
    return 'BusInfo{busNumber: $busNumber, remainingTime: ${getRemainingMinutes()}분, currentStation: $currentStation, isLowFloor: $isLowFloor}';
  }
}
