# 자동 알람 (출퇴근 알람)

> 이 문서는 **현재 상태**를 서술한다. 변경 이력은 [devlog.md](../devlog.md)의 해당 날짜 참조.
> 마지막 갱신: 2026-07-05 (alarm/ 모듈 이관 반영)

## 개요

요일·시각 기반으로 반복되는 버스 승차 알람. 공휴일 제외, 사용자 지정 예외 날짜(연차 등),
출근/퇴근 오디오 분기를 지원한다.

## 구성 요소

### Flutter (`lib/`)

- `models/auto_alarm.dart` — 알람 모델. `getNextAlarmTime({List<DateTime>? holidays})`가
  `excludeHolidays` 옵션에 따라 휴일을 건너뛰고 다음 알람 시각 계산
- `services/alarm_service.dart` — ChangeNotifier 코디네이터. CRUD 진입점·추적 제어·notifyListeners만 담당 (로드 주기: 2분 간격 스로틀)
- `services/alarm/` — 실질 로직 모듈:
  - `alarm_facade.dart` — state/cache/scheduler/engine 묶음의 진입점
  - `alarm_repository.dart` — SharedPreferences 영속화 (알람 로드·저장, 유효성 필터)
  - `alarm_event_handler.dart` — 네이티브→Flutter MethodChannel 이벤트 처리 (취소 동기화, 중복 이벤트 방지)
  - `auto_alarm_engine.dart` — 자동 알람 저장·직렬화
  - `auto_alarm_arrival_parser.dart` — 네이티브 도착 응답(String/List/Map) 정규화
  - `arrival_time_parser.dart` — "5분"/"곧 도착"/"운행종료" → 분 변환
  - `auto_alarm_validator.dart` — 자동 알람 JSON 필수 필드 검증
  - `station_id_resolver.dart` — 정류장 이름→stationId 하드코딩 fallback 매핑
  - `alarm_keys.dart` — 알람/캐시 키 표준 포맷 (반드시 이걸로만 키 생성)
  - `holiday_service.dart` — 공공데이터포털 공휴일 API + 메모리 캐시
  - `alarm_scheduler.dart`, `alarm_native_bridge.dart`, `alarm_state.dart`, `alarm_cache.dart`
- `services/settings_service.dart` — `customExcludeDates` (SharedPreferences 영구 저장)

### Android (`android/.../com/devground/daegubus/`)

- `utils/AutoAlarmScheduleCalculator.kt` — 네이티브 측 스케줄 계산
- `services/BusAlertAutoAlarmNotifier.kt` — 자동알람 알림
- `workers/` — WorkManager 기반 백그라운드 실행
- `receivers/` — 부팅/알람 브로드캐스트 수신

## 동작 규칙

- 알람 계산 전에 **현재 달 + 다음 달(2개월치)** 공휴일을 로드해서 `getNextAlarmTime(holidays:)`에 전달
- `customExcludeDates`는 공휴일 리스트에 결합되어 동일하게 스킵 처리됨 (설정 화면에서 캘린더 피커로 관리)
- 출근 알람(`isCommuteAlarm == true`): TTS 스피커 강제. 퇴근 알람: 이어폰 전용 —
  상세는 [tts-audio.md](tts-audio.md)
- 알람 저장은 SharedPreferences 기반, 수동 중지 플래그 별도 관리

## devlog 참조

2026-02-20 (TTS/진동 분기, 공휴일 CRUD 연동, 커스텀 예외 날짜). 최근 재예약 버그 수정은
git 이력 참조 (`bd589ad Fix auto alarm rescheduling`).
