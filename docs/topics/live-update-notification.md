# Live Update 알림 (Android 16 / Samsung Now Bar)

> 이 문서는 **현재 상태**를 서술한다. 변경 이력·시행착오의 전체 맥락은 [devlog.md](../devlog.md)의 해당 날짜 참조.
> 마지막 갱신: 2026-07-13 (Android 16 / One UI 8 실기기 검증 반영)

## 개요

버스 추적 중 포그라운드 알림을 Android 16 Live Update(상태 칩 + 잠금화면)와
Samsung One UI Now Bar로 승격시켜 실시간 도착 정보를 표시한다.

## 현행 아키텍처

- **알림 생성**: `android/app/src/main/kotlin/com/devground/daegubus/utils/NotificationHandler.kt`
- **추적/갱신**: `services/BusAlertService.kt` (조정 역할) + `BusAlertNotificationUpdater.kt`, `BusAlertTrackingManager.kt`
- **빌더**: `NotificationCompat.Builder` + `NotificationCompat.ProgressStyle` — **직접 API 호출** (Reflection 아님)
- **데이터 흐름**: Flutter가 단일 진실 공급원. Flutter에서 버스 정보를 fetch할 때마다
  `updateBusInfo` 메서드 채널로 Native에 전달 → 알림 즉시 갱신 (2026-02-05 결정)

## 핵심 결정: NotificationCompat.Builder를 유지할 것 (2026-02-16)

네이티브 `Notification.Builder` + Reflection 방식은 AndroidX 호환성 레이어를 우회해서
Live Update 승격 정보가 시스템에 전달되지 않았다. Google 공식 샘플과의 비교로 발견.

- `androidx.core:core-ktx` **1.17.0 이상 필수** — `setShortCriticalText()`, `setRequestPromotedOngoing()`,
  `NotificationCompat.ProgressStyle`은 1.17.0부터 존재 (1.15.0에는 없음)
- 의존성 체인: core-ktx 1.17.0 → AGP 8.9.1+ → Gradle 8.11.1+

## Live Update 작동 요구사항 체크리스트 (2026-03-15 정리)

1. `compileSdk 36` + `targetSdk 36`
2. `POST_PROMOTED_NOTIFICATIONS` 권한 선언 (AndroidManifest.xml)
3. `androidx.core:core-ktx:1.17.0` 이상
4. **앱 시작 시** `NotificationChannel` 생성 (`MainActivity.initializeEssentialComponents()`에서
   `notificationHandler.createNotificationChannels()` 호출) — 서비스 시작 시에만 생성하면
   설정의 "실시간 정보" 토글이 표시되지 않음
5. `setRequestPromotedOngoing(true)`
6. `setShortCriticalText()` — 상태 칩 텍스트 (7자 미만이면 전체 표시, 최대 96dp)
7. `NotificationCompat.ProgressStyle` — 진행 바 + `setProgressTrackerIcon(IconCompat)` (버스 아이콘 이동)
8. `setOngoing(true)`
9. `setCategory(Notification.CATEGORY_PROGRESS)`

카운트다운: `setWhen(도착 예정 시각)`이 **현재보다 2분 이상 미래**여야 칩에 "5분" 형식 표시.
`setUsesChronometer(true)` + `setChronometerCountDown(true)` 병용.

## 함정 (한 번 밟은 것들)

- **`setExtras()` 금지 → `addExtras()` 사용**: `setExtras()`는 NotificationCompat이 내부적으로
  설정한 extras를 덮어써 승격이 깨진다. (2026-02-16)
- **설정 바로가기 인텐트**: `Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS` +
  `EXTRA_APP_PACKAGE`가 올바른 값. `ACTION_MANAGE_APP_PROMOTED_NOTIFICATIONS`는 잘못된 값이었음.
- **디버깅 API**: `NotificationManager.canPostPromotedNotifications()`(사용자 설정 여부),
  `Notification.hasPromotableCharacteristics()`(알림 자체의 승격 가능성) — 둘 다 true인데도
  안 되면 채널 등록 시점(위 4번)이나 빌더 종류를 의심할 것.

## Samsung One UI 지원

- AndroidManifest에 `com.samsung.android.support.ongoing_activity` meta-data 선언
- `android.ongoingActivityNoti.*` extras Bundle을 `addExtras()`로 병합 (One UI 7 전용 필드)
- One UI 7의 Live Notifications는 삼성 화이트리스트 앱만 직접 사용 가능.
  One UI 8부터는 Android 16 표준 API로 자동 지원되므로 표준 API 구현이 본선.

## 실기기 검증 상태

- Galaxy S25 Ultra (`SM-S938N`), Android 16(API 36), One UI 8에서 Live Update와
  Samsung Now Bar 표시·갱신이 정상 작동한다.
- `POST_PROMOTED_NOTIFICATIONS`, 알림, 정확 알람, FGS 권한과 배터리 최적화 예외가
  허용된 상태에서 검증했다.

## 폐기된 접근 (다시 쓰지 말 것)

- ~~Reflection으로 `setRequestPromotedOngoing` / `setShortCriticalText` 호출~~ (2026-01-28 ~ 02-05)
- ~~네이티브 `Notification.Builder` / `Notification.ProgressStyle`~~
- ~~`builtNotification.flags` 수동 조작 (`FLAG_PROMOTED_ONGOING` 등)~~

## devlog 참조

2026-01-28(1~3차), 2026-02-05(1~4차), **2026-02-16(핵심 — 빌더 전환)**, 2026-03-15(채널 등록 시점)
