class BusArrival {
  final String stationId;
  final String routeId;
  final String routeNo;
  final String destination;
  final List<BusInfo> buses;

  BusArrival({
    required this.stationId,
    required this.routeId,
    required this.routeNo,
    required this.destination,
    required this.buses,
  });

  factory BusArrival.fromJson(Map<String, dynamic> json) {
    final busesJson = json['buses'] as List<dynamic>? ?? [];
    return BusArrival(
      stationId: json['stationId'] as String? ?? '',
      routeId: json['routeId'] ?? json['id'] ?? '',
      routeNo: json['routeNo'] ?? json['name'] ?? '',
      destination:
          json['destination'] ?? json['forward'] ?? json['sub'] ?? 'default',
      buses: busesJson.map((busJson) => BusInfo.fromJson(busJson)).toList(),
    );
  }
}

class BusInfo {
  final String busNumber;
  final String currentStation;
  final String remainingStops;
  final String arrivalTime;
  final bool isLowFloor;
  final bool isOutOfService;

  BusInfo({
    required this.busNumber,
    required this.currentStation,
    required this.remainingStops,
    required this.arrivalTime,
    required this.isLowFloor,
    required this.isOutOfService,
  });

  factory BusInfo.fromJson(Map<String, dynamic> json) {
    final busNumber = json['busNumber'] as String? ?? '';
    final isLowFloor = json['isLowFloor'] as bool? ?? busNumber.contains('저상');
    final estimatedTime = json['estimatedTime'] as String? ?? '';
    final isOutOfService =
        json['isOutOfService'] as bool? ?? (estimatedTime == '운행종료');

    // remainingStops 처리
    String remainingStopsText = json['remainingStops'] as String? ?? '';
    int remainingStopsValue = 0;
    if (remainingStopsText.contains('개소')) {
      remainingStopsText = remainingStopsText.split(' ')[0];
      remainingStopsValue = int.tryParse(remainingStopsText) ?? 0;
    } else {
      remainingStopsValue = int.tryParse(remainingStopsText) ?? 0;
    }

    // arrivalTime 처리
    String arrivalTime = estimatedTime;
    if (arrivalTime != '-' &&
        arrivalTime != '운행종료' &&
        !arrivalTime.contains('분')) {
      arrivalTime = '$arrivalTime분';
    }

    return BusInfo(
      busNumber: busNumber.replaceAll('(저상)', '').replaceAll('(일반)', ''),
      currentStation: json['currentStation'] as String? ?? '',
      remainingStops: '$remainingStopsValue 개소',
      arrivalTime: arrivalTime,
      isLowFloor: isLowFloor,
      isOutOfService: isOutOfService,
    );
  }

  // 남은 시간을 분 단위의 int로 변환
  int getRemainingMinutes() {
    if (arrivalTime == '-' || isOutOfService) return -1;

    final regex = RegExp(r'(\d+)분');
    final match = regex.firstMatch(arrivalTime);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '0') ?? 0;
    }
    return 0;
  }
}
