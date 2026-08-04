# Flutter ↔ 네이티브 메서드 채널

## 현행 구조 (2026-08-04 갱신)

채널 생성·와이어링은 `MainActivity.configureFlutterEngine()`에서 하고,
핸들러 구현은 `android/.../daegubus/channels/` 패키지에 분리되어 있다.

| 채널 이름 (`com.devground.daegubus/…`) | 핸들러 클래스 | 담당 |
|---|---|---|
| `bus_api` | `BusApiChannelHandler` (36개 라우팅) | 책임별 operation으로 호출을 전달하는 66줄 진입점. Flutter로의 역호출(`invokeMethod`)도 이 채널로 나감 |
| `tts` | `TtsChannelHandler` | TTS 발화·볼륨·오디오 출력 모드·알람 소리 설정 |
| `permission` | `PermissionChannelHandler` | 정확한 알람·배터리 최적화 상태·promoted 알림 권한 조회/설정 이동. 배터리 최적화는 직접 예외 요청 대신 시스템 설정 목록을 연다 |
| `station_tracking` | `StationTrackingChannelHandler` | `getBusInfo`(정류장 도착 정보 동기 조회), 추적 중지 |
| `bus_tracking` | `BusTrackingChannelHandler` | 추적 알림 업데이트·추적/자동알람 중지·정류장 추적 시작 |

### `bus_api` 내부 분리

| 클래스 | 현재 줄 수 | 담당 |
|---|---:|---|
| `BusApiTrackingOperations` | 470 | 버스·정류장 추적 시작, 갱신, 중지와 Flutter 취소 이벤트 역호출 |
| `BusApiQueryOperations` | 338 | 로컬 DB·웹 API 기반 정류장/노선 조회와 JSON 변환 |
| `BusApiAlarmOperations` | 320 | 일회성 알림, 즉시 자동알람, AlarmManager 예약·취소 |
| `BusApiTtsOperations` | 131 | bus_api 채널의 기존 TTS 위임과 응답 시맨틱 |

`BusApiChannelHandler`가 36개 메서드 이름의 단일 목록을 유지하고 operation은
실제 처리만 맡는다. `android_quality_regression_test.dart`가 메서드 집합과 라우터
140줄 이하, 각 operation 500줄 이하를 고정한다.

## 핸들러 ↔ MainActivity 의존

핸들러 또는 `bus_api` operation은 생성자로 `MainActivity`를 받고, 다음 internal
멤버를 사용한다:

- `busAlertService` (바인딩 상태에 따라 null 가능 — 핸들러는 매 호출 시 null 체크)
- `busApiService`, `notificationHandler` (lateinit — 콜백 시점에는 초기화 완료)
- `_methodChannel` — Flutter로의 이벤트 역전송 (`onAlarmCanceledFromNotification` 등)
- 폴백 헬퍼: `speakFallbackTts` / `stopFallbackTts` / `isHeadphoneConnectedViaAudioManager` /
  `startAndBindBusAlertService`

## 함정

- BUS_API 채널의 `speakTTS`·`setAudioOutputMode`·`setVolume`은 TTS 채널에도 존재하며
  **에러 처리 시맨틱이 다르다** (BUS_API는 `result.error`, TTS 채널은 실패도 `result.success(true)`).
  분리 시점의 기존 동작을 그대로 보존한 것 — 통일하려면 Flutter 호출부 확인 필요.
- 로그 TAG는 채널별 (`BusApiChannel`, `TtsChannel`, `PermissionChannel`,
  `StationTrackingChannel`, `BusTrackingChannel`).
- `MainActivity.ALARM_NOTIFICATION_CHANNEL_ID`(`bus_alarm_channel`)는 companion const로
  노출되어 `BusApiAlarmOperations.showNotification`이 사용한다.

## 폐기된 접근

- MainActivity 인라인 핸들러 (2,622줄 모놀리스, ~2026-07-07): `when` 내 중복 케이스
  3개(`startTtsTracking`/`setAudioOutputMode`/`setVolume` 2차 정의)는 도달 불가 죽은
  코드였고 분리 시 제거됨.
- 단일 `BusApiChannelHandler` 구현(1,276줄, ~2026-07-07~2026-08-04): 채널 진입점과
  네 책임의 구현이 한 파일에 섞여 있어 66줄 라우터 + 네 operation으로 교체됨.
