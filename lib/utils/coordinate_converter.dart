import 'dart:math';

class CoordinateConverter {
  // NGIS 좌표계 (EPSG:5185)를 WGS84 (위도/경도) 좌표계로 변환
  static List<double> convertNGISToLatLon(double x, double y) {
    // NGIS 중부원점 기준 좌표 (미리 계산된 값)
    const double baseX = 1.0E6;
    const double baseY = 2.0E6;

    // 회전각도 및 축척 계수 (대구 지역에 맞는 계수)
    const double rotationAngle = -38.3; // 도
    const double scaleFactor = 1.0;

    // 라디안으로 변환
    const double rotationRad = rotationAngle * (pi / 180);

    // 원점 이동 및 회전 계산
    final double translatedX = x - baseX;
    final double translatedY = y - baseY;

    final double rotatedX =
        translatedX * cos(rotationRad) - translatedY * sin(rotationRad);
    final double rotatedY =
        translatedX * sin(rotationRad) + translatedY * cos(rotationRad);

    // 축척 조정
    final double scaledX = rotatedX * scaleFactor;
    final double scaledY = rotatedY * scaleFactor;

    // 대구 지역 기준점 (대략적인 위치)
    const double baseLat = 35.8714;
    const double baseLon = 128.6014;

    // 대략적인 좌표 변환 (실제 정확한 변환을 위해서는 더 복잡한 투영 알고리즘 필요)
    final double deltaLat = scaledY / 100000.0;
    final double deltaLon = scaledX / 100000.0;

    final double lat = baseLat + deltaLat;
    final double lon = baseLon + deltaLon;

    return [lat, lon];
  }
}
