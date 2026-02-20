# 자동알람 기능 구현 점검 및 보완 계획

## ✅ 1. 출근/퇴근 알람 작동 점검 (완료)
- **Android Native 측 (Kotlin)**: `isCommuteAlarm` 관련 로직 점검. 출근(스피커 강제), 퇴근(이어폰 시 TTS, 미연결 시 진동) 등 사양에 맞게 동작하는지 테스트 및 코드 수정. `BusAlertService.kt`, `TTSService.kt`, `BusAlertTtsController.kt` 수정 완료. 退근 알람 시 이어폰(미디어 스트림)으로 발화하도록 수정하고, 이어폰 미연결 시 TTS 발화를 스킵하고 즉시 진동이 울리도록 처리함.
- **Flutter 측 (Dart)**: 알람 스케줄링 로직 연동 확인 완료.

## ✅ 2. 자동알람 CRUD 추가 (완료)
- 이미 `alarm_screen.dart`에 "자동 알림 추가", "자동 알림 편집", 그리고 목록을 보여주는 부분(스위치, 활성화 토글 등)이 구현되어 있는 것으로 보임.
- 추가 점검:
  - Create: 새로운 자동알람을 추가할 때 문제 없이 저장됨 (SharedPreferences 연동).
  - Read: 저장된 알람을 불러와 UI에 제대로 띄우도록 수정 및 확인 완료.
  - Update: 시간, 노선, 요일, 공휴일 제외 등을 수정했을 때 잘 갱신됨.
  - Delete: 자동알람 삭제 기능 정상 작동.
  - **공휴일 제외 로직**: 공공데이터포털 API 연동 완료 및 메모리 캐싱(`HolidayService`) 적용 완료, `AutoAlarm` 모델과 연동하여 `excludeHolidays`가 완벽히 동작하도록 구현함.

## ✅ 3. 휴일/스케줄 설정 (커스텀 반복) 기능 강화 (완료)
- 기존에는 `[1, 2, 3, 4, 5]` 형태의 요일 반복(`repeatDays`), `excludeHolidays`, `excludeWeekends` 옵션 존재.
- "스케줄이 다른 사람도 있기 때문에 설정에서 추가":
  - `SettingsScreen`에 `나만의 알람 예외 날짜`를 관리할 수 있는 UI 구현 (달력에서 날짜 추가/삭제).
  - `SettingsService`를 통해 `customExcludeDates`를 기기에 영구 저장함.
  - 다음 알람일자 계산 시 공공 공휴일과 사용자가 직접 정한 나만의 휴일을 함께 병합(`...customExcludeDates`) 처리하여 알람이 울리지 않도록 구현 완료.
