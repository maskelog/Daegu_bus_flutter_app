# docs 색인

프로젝트 지식의 진입점. 질문에 답하거나 작업을 시작하기 전에 여기서 관련 문서를 찾을 것.

## 주제별 문서 (현재 상태 — 작업 후 갱신 대상)

| 문서 | 내용 |
|---|---|
| [topics/live-update-notification.md](topics/live-update-notification.md) | Android 16 Live Update / Samsung Now Bar 알림 — 현행 아키텍처, 작동 조건, 함정, 폐기된 접근 |
| [topics/auto-alarm.md](topics/auto-alarm.md) | 출퇴근 자동 알람 — 공휴일 제외, 커스텀 예외 날짜, 모듈 구성 |
| [topics/tts-audio.md](topics/tts-audio.md) | TTS·오디오 출력 정책 — 출근(스피커)/퇴근(이어폰) 분기 |
| [topics/method-channels.md](topics/method-channels.md) | Flutter ↔ 네이티브 메서드 채널 — 채널 5개, channels/ 핸들러 구조, 함정 |
| [topics/bus-detail-ui.md](topics/bus-detail-ui.md) | 버스 상세 모달 — 노선도 진입, 즐겨찾기·승차 알람 액션 |
| [topics/station-ui.md](topics/station-ui.md) | 정류장 번호 배지 — 다크모드 대비가 높은 테마 대응 칩 |
| [topics/route-branding.md](topics/route-branding.md) | 노선 배지 색상 — 직행/급행/순환/간선/지선/출근맞춤/군위/투어/DRT 팔레트 |

## 시간순 로그

- [devlog.md](devlog.md) — append-only 개발 일지. "언제 무엇을 왜 했나"의 기록.
  폐기된 접근에는 `⚠️ 폐기됨` 표시가 있으니 플래그 없이 인용하지 말 것.

## 계획 문서

- [refactoring-plan.md](refactoring-plan.md) — 리팩토링 백로그 실행 계획서.
  세션 단위 작업 지시서 (실행 에이전트용). 작업 완료 시 체크박스·실측값 갱신할 것.

## 워크플로

1. 작업 완료 → `devlog.md`에 날짜별 엔트리 추가 (append)
2. 관련 `topics/*.md`를 현재 상태에 맞게 **수정** (이력 나열이 아니라 현재형 서술 유지)
3. 기존 topic 문서와 모순되는 변경이면 옛 서술을 지우고, 필요 시 "폐기된 접근"에 한 줄 남김
4. 새 주제가 생기면 `topics/`에 문서를 만들고 이 색인에 등록

## 미정리 문서 (루트)

아래 루트 문서들은 이 색인 체계 이전의 산출물로, topic 문서로 흡수하거나 폐기 판정 필요:
`BUS_INFO_ISSUE_FIX.md`, `LIVE_UPDATE_INTEGRATION.md`, `MATERIAL3_EXPRESSIVE_COMPLETE.md`,
`MATERIAL3_EXPRESSIVE_UPGRADE.md`, `OPTIMIZATION_SUMMARY.md`, `plan.md`, `PLAY_STORE_COMPLIANCE.md`
(`Requirements.md`, `README.md`는 유지)
