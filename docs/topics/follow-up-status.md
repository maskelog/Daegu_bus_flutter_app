# 현재 후속 확인 항목

> 이 문서는 **아직 완료되지 않은 검증과 운영 후속 조치**만 모은다. 완료 이력은
> [devlog.md](../devlog.md), 코드 구조 개선 작업은
> [refactoring-plan.md](../refactoring-plan.md)를 참조한다.
>
> 마지막 갱신: 2026-07-28

## 우선순위 높음: TTSService REPEAT_TTS_ALERT 잔류 버그 — 코드 수정 완료, 실기기 재검증 대기

- 현재 상태: 근본 원인을 코드 레벨로 확인했다 — `BusAlertService.stopTtsTracking()`이
  `TTSService`에 `STOP_TTS_TRACKING`을 보내지 않는 미완성 스텁이었다(리팩토링
  이전부터 있던 사전 존재 버그, 작업 1/1b 회귀 아님). `ttsController.stopTtsServiceTracking()`
  호출을 추가해 수정했고 `:app:compileDebugKotlin`은 통과했다(devlog 2026-07-28
  (8차) 참조).
- 완료 기준: devlog 2026-07-28 (7차)와 동일한 시나리오(자동알람 도착임박 TTS →
  알림의 "추적 중지" 탭)를 실기기로 재현해 `id=1002` 알림이 즉시 사라지고
  `TTSService`가 foreground에서 내려가는지 `dumpsys activity services`로
  확인한다. 아직 실기기 검증 전이므로 완료로 간주하지 않는다.

## 우선순위 중간: BusAlertService.kt 1b 자동알람 잔여 검증

- 현재 상태: 자동알람 시작(foreground 5초 제한 내 기동, TTS 분기 진입)과
  도착임박 TTS 트리거, 추적 중지는 2026-07-28에 실기기로 확인했다(devlog
  2026-07-28 (7차) 참조, 우연히 발동한 기존 623번 자동알람을 활용). 타임아웃
  (무응답 시 자동 정리)과 중복 트리거 방지(`pendingAutoAlarms`),
  stationId 보정 재시도는 아직 확인 못 했다.
- 완료 기준: 타임아웃/중복방지는 재현 시나리오를 설계해(예: 같은 노선을
  짧은 간격으로 두 번 트리거) 실기기로 확인한다. stationId 보정은 해당
  엣지케이스 정류장을 특정해야 한다.

## 우선순위 높음: 1.0.4+66 Play 배포 확인

- 현재 상태: 로컬 릴리스 서명 APK(sideload, Play 배포 아님)를 실기기(Galaxy Note10+,
  `R3CM70K2YZD`)에 설치해 지도 `도착정보 보기` 단일 카드·홈 전환·edge-to-edge
  렌더링에 기능 문제가 없음을 2026-07-25에 확인했다 (devlog 참조). Play Console
  업로드·배포는 아직 하지 않았다.
- 완료 기준: Play Console이 `versionCode 66`을 수락하고 배포한 뒤, **Play 배포본**을
  실기기에 설치해 같은 흐름을 재확인한다 (sideload 검증과 Play 배포본 검증은
  별개로 취급한다).

## 우선순위 중간: Android SDK 도구 경고 해소

- 현재 상태: 2026-07-15 AAB 빌드에서 Android Studio와 command-line tools 사이의
  SDK XML 버전 불일치 경고가 1건 발생했으나 빌드는 성공했다.
- 완료 기준: 두 도구의 SDK 구성 버전을 정렬하고 다음 `build_release.ps1` 실행에서
  같은 경고가 재발하지 않는지 확인한다.

## 관리 원칙

- 과거 devlog의 `아직 검증하지 않음` 표기는 그 뒤의 전체 검증이 해당 변경을 포함했는지
  불명확할 수 있다. 새 작업에서는 검증 명령뿐 아니라 검증한 범위와 대상 빌드도 함께
  기록한다.
- 항목이 완료되면 이 문서에서 제거하고, 완료 사실과 증거를 devlog에 append한다.
- 코드 분리·테스트 보강처럼 계획된 개발 작업은 이 문서에 중복하지 않고
  `refactoring-plan.md`의 체크박스로 관리한다.
