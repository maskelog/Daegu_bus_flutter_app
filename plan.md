# 대구 버스 앱 — 개발 계획 체크리스트

> 기준일: 2026-02-28  
> `research.md` 분석 기반으로 작성된 전체 개발 계획

---

## ✅ Phase 1 — 성능 & 안정성 기반 작업 (완료)

### 1-1. API 최적화
- [x] API 호출 주기 30초 → 90초로 조정
- [x] 800ms 디바운싱 시스템 구현 (`utils/debouncer.dart`)
- [x] 중복 API 호출 방지 로직 적용

### 1-2. 캐싱 시스템
- [x] `BusCacheManager` 구현 (최대 50개, TTL 5분)
- [x] `CacheCleanupService` — 30분 주기 자동 정리
- [x] 유효한 캐시만 저장하는 스마트 캐싱
- [x] 캐시 통계 모니터링 로깅

### 1-3. 에러 처리
- [x] `BusApiResult<T>` 타입 안전 래퍼 구현
- [x] 8가지 에러 타입 세분화 (네트워크/서버/파싱/노데이터 등)
- [x] 자동 에러 분석 및 분류 시스템

### 1-4. 알람 시스템 기반
- [x] 단건 알람 (`AlarmData`) CRUD
- [x] 자동 알람 (`AutoAlarm`) CRUD
- [x] 공휴일 API 연동 (`HolidayService`)
- [x] 사용자 정의 제외 날짜 (`customExcludeDates`) 영구 저장
- [x] 알람 재시작 방지 시간 30초 → 3초 단축
- [x] 출퇴근 알람 (`isCommuteAlarm`) 로직 구현
  - [x] 출근: 스피커 강제 발화
  - [x] 퇴근: 이어폰 연결 시 TTS, 미연결 시 진동

### 1-5. Android 16 Live Update 알림
- [x] `setRequestPromotedOngoing(true)` — Now Bar 승격
- [x] `setShortCriticalText("N분")` — 상태 칩
- [x] `Notification.ProgressStyle` — 진행 바
- [x] `setProgressTrackerIcon(ic_bus_tracker)` — 버스 아이콘 이동
- [x] `setProgressSegments()` — 구간별 색상
- [x] `setProgressPoints()` — 출발/도착 마커
- [x] `setWhen(now + remainingMin)` — 카운트다운 수정
- [x] `canPostPromotedNotifications()` 로깅 추가
- [x] `hasPromotableCharacteristics()` 로깅 추가
- [x] 승격 불가 시 "알림 설정" 액션 버튼 추가

### 1-6. 데이터 동기화 (Flutter → Native)
- [x] `getBusArrivalByRouteId` 호출 후 Native로 결과 전송
- [x] `BusAlertService.updateBusInfoFromFlutter()` 구현
- [x] `MainActivity.kt` `updateBusInfo` 채널 핸들러 추가
- [ ] 홈 스크린 자동 알람 갱신 시 Native 호출 연결 확인
- [ ] 즐겨찾기 화면 새로고침 시 Native 호출 연결 확인

### 1-7. UI 기반 개선
- [x] 홈 화면 섹션 헤더 (아이콘 + 제목) 개선
- [x] 즐겨찾기 버스 카드 애니메이션 (staggered)
- [x] 3분 이내 도착 버스 강조 표시
- [x] 즐겨찾기 화면 빈 상태 디자인
- [x] Material 3 테마 전면 적용 (8가지 컬러 스키마)

---

## 🔄 Phase 2 — 기능 완성 및 UX 개선 (진행 중)

### 2-1. 데이터 동기화 마무리
- [ ] 홈 화면 버스 정보 갱신 → Native 알림 즉시 반영 검증
- [ ] 즐겨찾기 화면 갱신 → Native 알림 즉시 반영 검증
- [ ] Now Bar 실기기 표시 end-to-end 테스트 (Android 16+)
- [ ] 홈 화면과 알림 시간 일치 여부 확인

### 2-2. 알람 화면 (`alarm_screen.dart`) 개선
- [ ] 자동 알람 목록 UI 폰트·간격 정리
- [ ] 알람 다음 발동 시각 미리보기 표시 (`getNextAlarmTime()` 활용)
- [ ] 알람 상태 뱃지 (활성/비활성/실행 중) 시각화
- [ ] 자동 알람 드래그로 순서 변경 (선택)

### 2-3. 홈 화면 (`home_screen.dart`) 개선
- [ ] 근처 정류장 카드 — 빈 상태 메시지 개선
- [ ] 즐겨찾기 버스 로딩 스켈레톤 UI 통일
- [ ] 당겨서 새로고침 시 Native 동기화 호출 포함 확인
- [ ] 홈 화면 광고(AdMob) 표시 위치 최적화

### 2-4. 지도 화면 (`map_screen.dart`) 개선
- [ ] 카카오맵 마커 클릭 → 버스 정보 표시 속도 개선
- [ ] 지도 로드 실패 시 fallback 화면 처리
- [ ] 현재 위치 갱신 버튼 추가 (선택)

### 2-5. 설정 화면 (`settings_screen.dart`) 개선
- [ ] 컬러 스키마 선택 UI 미리보기 추가 (색상 동그라미)
- [ ] 폰트 크기 배율 슬라이더 실시간 미리보기
- [ ] TTS 테스트 버튼 ("버스가 곧 도착합니다" 재생)
- [ ] 알람 볼륨 미리 듣기 기능 (선택)

### 2-6. 즐겨찾기 기능 고도화
- [ ] 즐겨찾기 버스 순서 드래그 변경
- [ ] 즐겨찾기 그룹/태그 기능 (선택)
- [ ] 즐겨찾기 버스 노선·정류장 변경 편집 기능

---

## 📋 Phase 3 — 품질 및 안정성 강화

### 3-1. 에러 핸들링 UI
- [ ] 네트워크 오류 시 재시도 버튼 표시
- [ ] API 파싱 오류 시 상세 에러 메시지 (Debug 모드)
- [ ] 정류장 DB 로드 실패 시 서버 검색으로 자동 전환

### 3-2. 백그라운드 서비스 안정성
- [ ] `BusAlertService` 비정상 종료 후 자동 재시작 검증
- [ ] WorkManager 작업 실패 재시도 정책 확인
- [ ] 배터리 최적화 허용 목록 안내 UI

### 3-3. Gradle / 빌드 최적화
- [ ] ProGuard 규칙 검토 (알림 Reflection API 보호)
- [ ] Release APK 크기 측정 및 최적화
- [ ] 불필요한 의존성 제거 검토

### 3-4. 코드 품질
- [ ] `BusAlertService.kt` (153KB) 서브 클래스 분리 검토
- [ ] `MainActivity.kt` (127KB) MethodChannel 핸들러 모듈화
- [ ] `alarm_service.dart` (67KB) 알람 facade 완성도 점검
- [ ] `bus_card.dart` (48KB) → 재사용성 높은 서브 위젯으로 분리

### 3-5. 테스트
- [ ] `BusArrival`, `BusInfo`, `AutoAlarm` 단위 테스트
- [ ] `AutoAlarm.getNextAlarmTime()` 공휴일 엣지 케이스 테스트
- [ ] `BusCacheManager` TTL 만료 동작 테스트
- [ ] MethodChannel 통신 Mock 테스트
- [ ] Android 16 알림 통합 테스트 (실기기)

---

## 🚀 Phase 4 — 고급 기능 (장기)

### 4-1. 실시간성 향상
- [ ] WebSocket / SSE 기반 실시간 버스 위치 스트리밍 검토
- [ ] 도착 예측 정확도 향상 알고리즘 (이력 기반)

### 4-2. 플랫폼 확장
- [ ] iOS 빌드 환경 구성 및 테스트
- [ ] 웹 버전 (flutter build web) 검토

### 4-3. 사용자 경험 심화
- [ ] 버스 탑승 확인 (Geofence 기반 자동 알람 종료)
- [ ] 통계 화면: 자주 탄 버스, 이용 정류장 등
- [ ] 위젯 (Android App Widget) 홈 화면 배치

### 4-4. 배포
- [ ] Play Store 설명문 / 스크린샷 최신화
- [ ] 버전 코드 1.0.0+1 → 정식 버전 네이밍 전략 수립
- [ ] Play Store 내부 테스트 트랙 배포
- [ ] 프로덕션 배포

---

## 🐛 알려진 버그 / 미해결 이슈

| # | 증상 | 관련 파일 | 우선순위 |
|---|------|-----------|----------|
| 1 | 홈 화면 vs 알림 시간 불일치 가능성 (부분 해결) | `alarm_service.dart`, `BusAlertService.kt` | 높음 |
| 2 | Now Bar — `canPostPromotedNotifications()` false 시 표시 안 됨 | `NotificationHandler.kt` | 높음 |
| 3 | 즐겨찾기 화면 한글 인코딩 깨짐 일부 잔존 가능성 | `favorites_screen.dart` | 중간 |
| 4 | 자동 알람 다음 발동 시각이 UI에 표시되지 않음 | `alarm_screen.dart` | 중간 |
| 5 | 대용량 파일 (`BusAlertService.kt`) 유지보수 어려움 | `BusAlertService.kt` | 낮음 |

---

## 📌 개발 규칙 & 참고

- **Single Source of Truth**: 버스 도착 정보는 Flutter가 조회 → Native로 동기화
- **API 호출**: 중복 방지를 위해 반드시 `Debouncer` 또는 캐시 확인 후 호출
- **알림**: Android 16+ `Notification.ProgressStyle`은 Reflection으로 호출 (SDK 미공개)
- **TTS**: 이어폰 모드는 `AudioManager.isWiredHeadsetOn` / `isBluetoothA2dpOn` 체크
- **디버깅**: `adb logcat | grep -E "(BusApiResult|CacheManager|LiveUpdate)"`
- **메모리**: `adb shell dumpsys meminfo com.example.daegu_bus_app` 으로 주기적 점검
