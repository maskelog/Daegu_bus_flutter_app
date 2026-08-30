# 현재 후속 확인 항목

> 이 문서는 **아직 완료되지 않은 검증과 운영 후속 조치**만 모은다. 완료 이력은
> [devlog.md](../devlog.md), 코드 구조 개선 작업은
> [refactoring-plan.md](../refactoring-plan.md)를 참조한다.
>
> 마지막 갱신: 2026-08-04

## 우선순위 높음: Android 16 Live Update 회귀 수정 실기기 확인

- 현재 상태: 수동 추적과 자동알람 경로에 재도입돼 있던 네이티브
  `Notification.Builder`/`Notification.ProgressStyle`, Reflection, 수동 promoted 플래그
  조작을 제거하고 2026-02-16의 `NotificationCompat` 직접 호출 구조로 통일했다.
  소스 회귀 테스트와 Kotlin 컴파일은 통과했다. 이 변경을 포함한 릴리스 APK를
  Galaxy Note10+(Android 12/API 31, One UI 4.1)에 설치해 수동 추적 알림의
  도착 정보 갱신, 펼친 알림의 `추적 중지` 액션, foreground 서비스 정리를 확인했다.
  API 31은 표준 진행 알림 폴백만 검증할 수 있으므로 API 36 승격 검증은 남아 있다.
- 완료 기준: API 36 / One UI 8 실기기에서 (1) 수동 추적 상태칩 텍스트·진행 아이콘,
  (2) 자동알람 상태칩·Now Bar 갱신, (3) `추적 중지`·`알람 끄기` 액션을 확인하고
  `hasPromotableCharacteristics()`와 `canPostPromotedNotifications()`가 모두 true인지
  logcat으로 기록한다.

## 우선순위 중간: 자동알람 수정 실기기 재검증

- 현재 상태: 자동알람 시작(foreground 5초 제한 내 기동, TTS 분기 진입)과
  도착임박 TTS 트리거, 추적 중지는 2026-07-28에 실기기로 확인했다(devlog
  2026-07-28 (7차) 참조). 이후 발견된 3~5초 중복 발화와 60~62초 재시작은
  `AlarmReceiver`가 사전 추적 직후 오늘 회차를 다시 체인하고,
  `BusAlertService`가 60초 지난 중복을 새 알람으로 오인한 결합 버그로
  코드에서 확인·수정했다. 다음 회차 계산, pending/active 중복 방지,
  타임아웃 경계, stationId 형식 판정은 JVM 단위 테스트로 검증했다. 2026-08-04
  데이터 보존 업데이트 뒤에도 기존 17:35 알람의 활성 상태와 17:30
  `RTC_WAKEUP` 예약이 유지되는 것은 확인했지만, 예약 시각의 실제 기동은 기다리지 않았다.
- 완료 기준: 수정 빌드를 실기기에 설치한 뒤 트리거가 임박한 자동알람으로
  (1) 본 시각 전 3~5초 재발화가 없는지, (2) 설정 타임아웃 후 서비스·알림이
  정리되는지 확인한다. stationId 보정은 형식이 잘못된 실제 정류장 데이터를
  특정할 수 있을 때 로그의 `stationId 보정 후 추적 시작`까지 확인한다.

## 우선순위 높음: 1.0.4+66 Play 배포 확인

- 현재 상태: 2026-08-04 현행 작업 트리에서 다시 빌드한 로컬 릴리스 서명
  APK(sideload, Play 배포 아님)를 Galaxy Note10+(`R3CM70K2YZD`)에 데이터 보존
  업데이트했다. 서명·최초 설치 시각·데이터 디렉터리 inode가 유지됐고 홈·검색·지도·
  노선·알람·설정, 수동 추적 알림과 중지 액션까지 정상 동작했다. Play Console
  업로드·배포는 아직 하지 않았다.
- 완료 기준: Play Console이 `versionCode 66`을 수락하고 배포한 뒤, **Play 배포본**을
  실기기에 설치해 같은 흐름을 재확인한다 (sideload 검증과 Play 배포본 검증은
  별개로 취급한다).

## 우선순위 중간: Android SDK 도구 경고 해소

- 현재 상태: 2026-07-15 AAB 빌드에서 Android Studio와 command-line tools 사이의
  SDK XML 버전 불일치 경고가 1건 발생했고, 2026-07-29 디버그 APK 빌드에서도
  SDK XML 3/4 불일치 경고가 재현됐다. 2026-08-04 `build_release.ps1 -Apk`에서도
  같은 경고가 재현됐으며 세 빌드 모두 성공했다.
- 완료 기준: 두 도구의 SDK 구성 버전을 정렬하고 다음 `build_release.ps1` 실행에서
  같은 경고가 재발하지 않는지 확인한다.

## 우선순위 중간: Play 메모리 품질 지표 기준선 수집

- 현재 상태: 홈 시작 시 숨은 WebView 생성을 제거하고 지도 런타임 캐시 상한과
  background/메모리 압박 정리를 적용했다. 소스 회귀 테스트와 로컬 빌드 게이트는
  메모리 실측을 대신하지 않는다.
- 완료 기준: 같은 릴리스 후보로 저RAM/중RAM 기기에서 홈, 지도 foreground, 지도에서
  홈으로 복귀, 앱 background/cached 상태의 `dumpsys meminfo` 기준선을 기록한다.
  Play Console Android vitals에서 Anonymous RSS + Swap, Bitmap memory, OOM 필터와
  새 AAB의 DEX optimization coverage가 기준을 만족하는지 확인한다.

## 우선순위 높음: Android lint 게이트 복구

- 현재 상태: 2026-08-29 `:app:lintDebug`는 기존 `MissingPermission` 3건
  (`NotificationHandler.kt` 2건, `StationTrackingService.kt` 1건)과 개발자 로컬
  `android/local.properties`의 `PropertyEscape` 2건으로 실패한다. 같은 실행의
  `:app:testDebugUnitTest`는 성공했고, 앱 품질 최적화 변경 파일에서 새 lint 오류는
  나오지 않았다.
- 완료 기준: 알림 권한 거부/SecurityException 경로를 동작 테스트로 고정해 3개 호출을
  안전하게 처리하고, 로컬 SDK 경로 표기를 Gradle properties 문법에 맞춘 뒤
  `:app:testDebugUnitTest :app:lintDebug`가 종료 코드 0으로 완료돼야 한다.

## 관리 원칙

- 과거 devlog의 `아직 검증하지 않음` 표기는 그 뒤의 전체 검증이 해당 변경을 포함했는지
  불명확할 수 있다. 새 작업에서는 검증 명령뿐 아니라 검증한 범위와 대상 빌드도 함께
  기록한다.
- 항목이 완료되면 이 문서에서 제거하고, 완료 사실과 증거를 devlog에 append한다.
- 코드 분리·테스트 보강처럼 계획된 개발 작업은 이 문서에 중복하지 않고
  `refactoring-plan.md`의 체크박스로 관리한다.
