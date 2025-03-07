class BusArrival {
  final String routeId;
  final String routeNo;
  final String destination;
  final List<BusInfo> buses;

  BusArrival({
    required this.routeId,
    required this.routeNo,
    required this.destination,
    required this.buses,
  });

  factory BusArrival.fromJson(Map<String, dynamic> json) {
    List<BusInfo> busList = [];

    if (json['bus'] != null) {
      if (json['bus'] is List) {
        busList = (json['bus'] as List)
            .map((busJson) => BusInfo.fromJson(busJson))
            .toList();
      } else {
        // 단일 항목인 경우
        busList.add(BusInfo.fromJson(json['bus']));
      }
    }

    return BusArrival(
      routeId: json['id'] ?? '',
      routeNo: json['name'] ?? '',
      // forward가 null일 수 있으므로 기본값 제공
      destination: json['forward'] ?? json['sub'] ?? 'default',
      buses: busList,
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
    final busNumStr = json['버스번호'] as String? ?? '';
    final isLowFloor = busNumStr.contains('저상');

    String remainingStopsText = json['남은정류소'] as String? ?? '';
    int remainingStopsValue = 0;

    if (remainingStopsText.contains('개소')) {
      remainingStopsText = remainingStopsText.split(' ')[0];
      remainingStopsValue = int.tryParse(remainingStopsText) ?? 0;
    }

    String arrivalTime = json['도착예정소요시간'] as String? ?? '';
    // 운행종료 여부 확인
    final isOutOfService = arrivalTime == '운행종료';

    if (arrivalTime != '-' &&
        arrivalTime != '운행종료' &&
        !arrivalTime.contains('분')) {
      arrivalTime = '$arrivalTime분';
    }

    return BusInfo(
      busNumber: busNumStr.replaceAll('(저상)', '').replaceAll('(일반)', ''),
      currentStation: json['현재정류소'] as String? ?? '',
      remainingStops: '$remainingStopsValue 개소',
      arrivalTime: arrivalTime,
      isLowFloor: isLowFloor,
      isOutOfService: isOutOfService, // 운행종료 여부 설정
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
