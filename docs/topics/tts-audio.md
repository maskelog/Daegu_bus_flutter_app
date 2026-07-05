# TTS·오디오 출력 정책

> 이 문서는 **현재 상태**를 서술한다. 변경 이력은 [devlog.md](../devlog.md)의 해당 날짜 참조.
> 마지막 갱신: 2026-07-05 (devlog 2026-02-20 기반으로 초기 작성)

## 개요

버스 도착 안내 TTS 발화와 진동의 출력 경로(스피커/이어폰)를 알람 종류에 따라 분기한다.

## 구성 요소 (`android/.../com/devground/daegubus/services/`)

- `TTSService.kt` — 실제 TTS 발화. `isAutoAlarm`, `autoAlarmForceSpeaker`,
  `autoAlarmForceEarphone` 인자로 출력 경로 결정
- `BusAlertTtsController.kt` — TTS·오디오 포커스·헤드셋 연결 체크를 담당.
  `startTtsServiceSpeak`에서 인텐트 옵션으로 플래그를 `TTSService`에 전달
- `BusAlertAlarmSoundPlayer.kt` — 알람음 재생

## 출력 정책

| 알람 종류 | 이어폰 연결됨 | 이어폰 없음 |
|---|---|---|
| 출근 알람 (`isCommuteAlarm == true`) | 스피커 강제 발화 | 스피커 발화 |
| 퇴근 알람 (`isCommuteAlarm == false`) | `STREAM_MUSIC`(이어폰)으로 발화 | **TTS 스킵 + 500ms 진동** |

- 과거에는 자동알람이면 무조건 스피커가 강제됐으나, 퇴근 알람은 공공장소 소음 방지를 위해
  이어폰 전용으로 변경됨 (2026-02-20)
- `BusAlertTtsController` 경유 시 `isAutoAlarm` 플래그 전달 누락에 주의 — 한 번 누락 버그가 있었음

## devlog 참조

2026-02-20 (출퇴근 알람 TTS 및 진동 로직 개선)
