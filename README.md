# 🚌 대구 버스 앱 (Daegu Bus App)

대구 지역 버스 정보를 실시간으로 제공하는 Flutter 기반 모바일 애플리케이션입니다. 버스 정류장별 도착 정보, 노선 정보, 카카오맵 연동을 통한 위치 기반 서비스를 제공합니다.

## ✨ 주요 기능

### 🎯 핵심 기능
- **실시간 버스 도착 정보**: 정류장별 버스 도착 예정 시간 및 남은 정류장 수 표시
- **정류장 검색**: 정류장명으로 빠른 검색 및 정보 조회
- **카카오맵 연동**: 현재 위치 기반 주변 정류장 표시 및 상호작용
- **즐겨찾기**: 자주 이용하는 정류장 즐겨찾기 기능
- **자동버스 알람**: 정해진 시간/요일에 자동으로 실행되는 스마트 알람 시스템
- **백그라운드 알림**: 버스 도착 시 푸시 알림 및 음성 안내
- **노선도**: 버스 노선별 정류장 시각화

### 🚀 최적화된 성능
- **메모리 사용량**: ~105MB (30% 감소 달성)
- **API 호출 최적화**: 90초 간격 (70% 감소)
- **스마트 캐싱**: 자동 캐시 관리 및 오프라인 데이터 지원
- **디바운싱**: 중복 API 호출 방지 (800ms 지연)
- **배터리 최적화**: 자동알람 경량화 모드로 배터리 소모 최소화

## 🏗️ 시스템 아키텍처

### 📊 데이터 흐름
```
대구 버스 API ↔ 네이티브 서비스 (Android/Kotlin) ↔ Flutter 앱 ↔ 카카오맵 WebView
```

### 🗂️ 주요 컴포넌트
- **Flutter Frontend**: 사용자 인터페이스 및 상태 관리
- **Native Services**: Android 백그라운드 서비스 및 API 통신
- **SQLite DB**: 정류장 정보 로컬 캐싱
- **Kakao Maps**: 지도 기반 정류장 표시 및 상호작용

## 🛠️ 기술 스택

### Frontend
- **Flutter**: 3.5.2
- **Dart**: 3.5.2
- **상태 관리**: Provider 패턴

### 주요 패키지
```yaml
dependencies:
  http: ^1.3.0                    # HTTP 통신
  flutter_local_notifications: ^18.0.1  # 로컬 알림
  geolocator: ^13.0.2            # 위치 서비스
  webview_flutter: ^4.4.2        # 카카오맵 WebView
  sqflite: ^2.4.1               # 로컬 데이터베이스
  dio: ^5.4.2                   # HTTP 클라이언트
  shared_preferences: ^2.2.2     # 로컬 저장소
  permission_handler: ^11.3.1    # 권한 관리
  flutter_tts: ^3.8.5           # 음성 안내 (TTS)
  workmanager: ^0.5.2           # 백그라운드 작업 관리
```

### Backend/Native
- **Android**: Kotlin
- **API 통신**: 대구시 버스 정보 API
- **지도**: 카카오맵 JavaScript API
- **데이터베이스**: SQLite (로컬)
- **백그라운드 서비스**: BusAlertService, TTSService
- **알람 시스템**: AlarmReceiver, BackgroundWorker

## 📂 프로젝트 구조

```
lib/
├── main.dart                 # 앱 진입점
├── models/                   # 데이터 모델
│   ├── bus_arrival.dart     # 버스 도착 정보
│   ├── bus_info.dart        # 개별 버스 정보
│   ├── bus_stop.dart        # 정류장 정보
│   ├── bus_route.dart       # 버스 노선 정보
│   ├── auto_alarm.dart      # 자동 알람 모델
│   └── alarm_data.dart      # 알람 데이터 모델
├── services/                 # 비즈니스 로직
│   ├── bus_api_service.dart # 버스 API 전용
│   ├── station_service.dart # 정류장 서비스
│   ├── alarm_service.dart   # 알람 관리 서비스
│   ├── notification_service.dart # 알림 서비스
│   └── cache_cleanup_service.dart # 캐시 관리
├── screens/                  # 화면 위젯
│   ├── home_screen.dart     # 메인 화면
│   ├── search_screen.dart   # 검색 화면
│   ├── map_screen.dart      # 지도 화면
│   ├── favorites_screen.dart # 즐겨찾기 화면
│   ├── alarm_screen.dart    # 알람 설정 화면
│   └── route_map_screen.dart # 노선도 화면
├── widgets/                  # 재사용 위젯
│   ├── bus_card.dart        # 버스 정보 카드
│   └── station_item.dart    # 정류장 아이템
└── utils/                    # 유틸리티
    ├── api_result.dart      # 에러 처리 시스템
    ├── bus_cache_manager.dart # 캐싱 관리
    └── debouncer.dart       # 디바운싱 유틸리티

android/app/src/main/kotlin/.../
├── services/                 # 네이티브 서비스
│   ├── BusApiService.kt     # API 통신
│   ├── BusAlertService.kt   # 버스 알림 서비스
│   ├── TTSService.kt        # 음성 안내
│   └── StationTrackingService.kt  # 추적 서비스
├── receivers/                # 브로드캐스트 리시버
│   ├── AlarmReceiver.kt     # 알람 수신기
│   └── NotificationCancelReceiver.kt # 알림 취소 수신기
├── workers/                  # 백그라운드 작업
│   ├── BackgroundWorker.kt  # 백그라운드 작업 관리
│   └── AutoAlarmWorker.kt   # 자동 알람 작업
└── models/                   # 데이터 모델
    └── BusInfo.kt           # 버스 정보 모델

assets/
├── kakao_map.html           # 카카오맵 WebView 템플릿
└── bus_stops.db            # 정류장 데이터베이스
```

## 🚀 설치 및 실행

### 1. 환경 설정
```bash
# Flutter 환경 확인
flutter doctor

# 의존성 설치
flutter pub get
```

### 2. 카카오맵 API 키 설정
```bash
# .env 파일 생성 (선택사항)
KAKAO_JS_API_KEY=your_kakao_api_key
```

### 3. 빌드 및 실행
```bash
# 개발 모드
flutter run

# 릴리즈 빌드
flutter build apk --release

# iOS 빌드
flutter build ios --release
```

## 📊 성능 메트릭

### 최적화 결과
- **메모리 사용량**: ~105MB (기존 대비 30% 감소) ✅
- **API 호출 빈도**: 90초마다 (기존 대비 70% 감소) ✅
- **배터리 소모**: 낮음 수준 ✅
- **캐싱 시스템**: 스마트 캐싱 + 자동 정리 ✅
- **에러 처리**: 8단계 세분화 처리 ✅
- **디바운싱**: 800ms 지연으로 중복 방지 ✅

## 🔔 자동버스 알람 시스템

### 🎯 주요 특징
- **정확한 시간 알람**: 설정된 시간에 정확히 실행되는 알람 시스템
- **요일별 반복**: 월-일 요일별 개별 설정 가능
- **주말/공휴일 제외**: 선택적으로 주말이나 공휴일 제외 가능
- **TTS 음성 안내**: 강제 스피커 모드로 확실한 음성 알림
- **실시간 버스 추적**: 알람 실행 후 실시간으로 버스 위치 추적
- **배터리 최적화**: 경량화 모드로 배터리 소모 최소화

### ⚙️ 작동 방식
1. **알람 등록**: 사용자가 시간, 요일, 버스 노선 설정
2. **백그라운드 모니터링**: 시스템이 설정된 시간을 지속적으로 모니터링
3. **정확한 실행**: 설정된 시간에 정확히 알람 실행
4. **실시간 추적**: 알람 실행 후 버스 위치 실시간 추적
5. **음성 안내**: TTS를 통한 강제 스피커 모드 음성 알림
6. **자동 종료**: 버스 도착 후 자동으로 알람 종료

### 🔧 기술적 구현
```kotlin
// Android 네이티브 알람 시스템
class AlarmReceiver : BroadcastReceiver {
    private fun handleOptimizedAutoAlarm(context: Context, intent: Intent) {
        // 배터리 최적화된 경량화 모드
        // ANR 방지를 위한 비동기 처리
        // 정확한 시간 매칭
    }
}

// 백그라운드 서비스
class BusAlertService : Service {
    // 실시간 버스 추적
    // 포그라운드 알림 관리
    // TTS 서비스 연동
}
```

### 📱 사용자 경험
- **간편한 설정**: 직관적인 UI로 알람 설정
- **확실한 알림**: 강제 스피커 모드로 놓치지 않는 알림
- **실시간 정보**: 버스 도착까지 남은 시간 실시간 표시
- **자동 관리**: 설정된 조건에 따라 자동으로 알람 관리

## 🔧 주요 기능 구현

### 1. 실시간 버스 도착 정보
```dart
// 정류장별 버스 도착 정보 조회
Future<BusApiResult<List<BusArrival>>> getStationInfo(String stationId) async {
  final result = await _callNativeMethod('getStationInfo', {'stationId': stationId});
  return _parseBusArrivalResult(result);
}
```

### 2. 자동버스 알람 시스템
```dart
// 자동 알람 모델
class AutoAlarm {
  final String id;
  final String routeNo;
  final String stationName;
  final int hour;
  final int minute;
  final List<int> repeatDays;  // 1-7 (월-일)
  final bool excludeWeekends;
  final bool excludeHolidays;
  final bool useTTS;
}

// 자동 알람 실행
Future<void> _executeAutoAlarmImmediately(AutoAlarm alarm) async {
  // 실시간 버스 정보 조회
  await refreshAutoAlarmBusInfo(alarm);
  
  // TTS 음성 안내 (강제 스피커 모드)
  if (alarm.useTTS) {
    await SimpleTTSHelper.speakBusAlert(
      busNo: alarm.routeNo,
      stationName: alarm.stationName,
      remainingMinutes: remainingMinutes,
      isAutoAlarm: true, // 강제 스피커 모드
    );
  }
}
```

### 3. 스마트 캐싱 시스템
```dart
// 캐시 유효성 검증
bool isValidCache(String key) {
  final cachedTime = _cacheTimestamp[key];
  if (cachedTime == null) return false;
  return DateTime.now().difference(cachedTime).inSeconds < CACHE_DURATION;
}
```

### 4. 에러 처리 시스템
```dart
enum BusApiError {
  networkError,
  serverError,
  parsingError,
  noData,
  timeout,
  invalidResponse,
  permissionDenied,
  unknown
}
```

## 🐛 문제 해결

### 일반적인 문제
1. **버스 정보가 표시되지 않음**
   - 네트워크 연결 확인
   - 앱 재시작
   - 캐시 초기화

2. **지도가 로드되지 않음**
   - 카카오 API 키 확인
   - WebView 권한 설정 확인

3. **백그라운드 알림 작동하지 않음**
   - 배터리 최적화 설정 해제
   - 알림 권한 확인

4. **자동버스 알람이 작동하지 않음**
   - 알람 권한 확인 (Android 13+)
   - 배터리 최적화 예외 설정
   - 자동 시작 권한 확인 (제조사별)
   - 알람 설정에서 자동알람 활성화 확인

### 디버깅 명령어
```bash
# 로그 모니터링
adb logcat | grep -E "(BusApiResult|CacheManager|CacheCleanupService)"

# 캐시 상태 확인
adb logcat | grep "캐시"

# 에러 추적
adb logcat | grep -E "(ERROR|❌)"

# 자동알람 로그 확인
adb logcat | grep -E "(AlarmReceiver|BusAlertService|AutoAlarm)"

# 메모리 사용량 확인
adb shell dumpsys meminfo com.example.daegu_bus_app

# 백그라운드 서비스 상태 확인
adb shell dumpsys activity services com.example.daegu_bus_app
```

## 📱 지원 플랫폼

- **Android**: API 21+ (Android 5.0+)
- **iOS**: iOS 12.0+
- **Web**: Chrome, Safari, Firefox (제한적 지원)

## 🤝 기여하기

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 라이선스

이 프로젝트는 MIT 라이선스 하에 배포됩니다. 자세한 내용은 `LICENSE` 파일을 참조하세요.

## 📞 문의

프로젝트에 대한 문의사항이나 버그 리포트는 Issues 탭을 통해 제출해 주세요.

---

**대구 버스 앱** - 실시간 버스 정보로 더 스마트한 이동을 경험하세요! 🚌✨
