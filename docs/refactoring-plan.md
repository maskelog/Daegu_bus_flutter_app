# 리팩토링 실행 계획서

작성: 2026-07-07 (Claude Fable 5). 실행 에이전트(Claude Opus 4.8 등)가 세션 단위로
집어들 수 있도록 작성됨. **한 세션에 작업 1개만** 진행할 것 — 각 작업이 단독 세션
크기다.

## 이 문서의 사용법

1. 아래 작업 목록에서 미완료(`[ ]`) 중 우선순위가 가장 높은 것 하나를 고른다.
2. 작업 섹션의 "읽기 순서"대로 파일을 읽고, "단계"를 순서대로 실행한다.
3. 각 단계마다 검증 → 커밋. 검증 실패 상태로 다음 단계로 넘어가지 않는다.
4. 완료하면: ① `docs/devlog.md`에 엔트리 추가 ② 이 문서의 체크박스와 줄 수를
   실측값으로 갱신 ③ 관련 `docs/topics/*.md` 갱신.
5. 막히면 **추측으로 밀어붙이지 말 것**: 진행분까지 커밋하고, 막힌 지점과 이유를
   devlog에 기록한 뒤 세션을 끝낸다.

## 작업 목록 (우선순위순)

- [x] 작업 1: BusAlertService.kt 분리 (2,535줄 → 1,620줄, 2026-07-25 완료. ~1,200줄
      목표는 못 미쳤으나 계획서에 명시된 4단계는 모두 verbatim 이동 + diff 대조로 완료됨.
      실기기 검증 필요 — devlog 2026-07-25 (2~4차) 참조)
- [ ] 작업 1b: BusAlertService.kt 추가 축소 (1,620줄 → ~1,200줄 목표) — 세션 4개로
      분할. 1b-1~3 완료로 목표 달성(1,101줄), 1b-4는 보류 (2026-07-28, 사용자 확인)
  - [x] 1b-1: 하단 유틸/확장 함수를 별도 파일로 (가장 쉬움, ~55줄) — 2026-07-28
        완료, 1,620→1,563줄 (devlog 2026-07-28 참조)
  - [x] 1b-2: 취소 로직을 BusAlertTrackingManager로 (중간, ~130줄) — 2026-07-28
        완료, 1,563→1,444줄 (devlog 2026-07-28 (2차) 참조)
  - [x] 1b-3: 도착 확인/추적정보 갱신 클러스터를 신규 협력 클래스로 (가장 큰 감소,
        ~340줄, 실기기 검증 중요) — 2026-07-28 완료, 1,444→1,101줄. 신규 클래스
        대신 기존 `BusAlertTrackingManager` 확장(devlog 2026-07-28 (3차) 참조).
        실기기 검증 일부 완료(수동 알람 시작/중지, devlog 2026-07-28 (5차) 참조) —
        전체 중지·자동알람·stationId 보정 등은 아직 미완
  - [ ] 1b-4: onStartCommand 디스패치 본문 축소 (~390줄) — foreground 서비스 시작
        타이밍 직결이라 고위험. 1b-1~3 완료 후 목표를 이미 달성했으면 실기기
        스모크 없이는 손대지 않는 걸 권장 (아래 섹션 참조)
- [ ] 작업 2: UI 위젯 테스트 보강 — 작업 3~5의 선행 조건
- [ ] 작업 3: map_screen.dart 분리 (1,578줄) — 작업 2 완료 후
- [ ] 작업 4: unified_bus_detail_widget.dart 분리 (1,411줄) — 작업 2 완료 후
- [ ] 작업 5: home_widgets.dart 분리 (1,032줄) — 작업 2 완료 후
- [ ] 작업 6: alarm_service.dart 잔여 이관 (1,150줄)

---

## 공통 원칙 (모든 작업에 적용 — 위반하지 말 것)

### 동작 보존
- 리팩토링 커밋에 기능 변경·스타일 개선을 섞지 않는다. "고치고 싶은 것"이 보이면
  devlog 백로그에 적고 넘어간다.
- 코드를 옮길 때는 **verbatim 이동 + 최소 치환**(참조 경로 수정)만 한다.
  로직을 "이해한 대로 다시 쓰기" 금지 — 이번 MainActivity 분리에서 이 원칙으로
  케이스 54개를 누락 0으로 이관했다.
- 미묘하게 다른 중복 코드(예: 에러 시 `result.error` vs `result.success`)는
  **통일하지 말고 각각의 시맨틱을 보존**한다. 통일은 호출부 검증이 가능한
  별도 작업이다.

### 죽은 코드 삭제 기준
- `private`(Dart는 `_` 접두) + 저장소 전체 grep 참조 0건일 때만 삭제.
- 삭제 목록을 커밋 메시지와 devlog에 명시한다.
- Kotlin `when`의 중복 케이스는 첫 분기만 실행되므로 두 번째 이후는 죽은 코드다
  — 단, 첫 정의의 시맨틱을 유지해야 한다.

### 검증 (각 단계 후 필수)
```powershell
# Dart 변경 시
flutter analyze          # 0건이어야 함 (pre-commit 훅도 실행함)
flutter test             # 현재 38건 전체 통과가 기준선

# Kotlin 변경 시 (android/ 디렉토리에서)
.\gradlew.bat :app:compileDebugKotlin --console=plain -q
```
- **주의**: `flutter analyze`를 상위 폴더(`code/active`)에서 실행하면 옆
  프로젝트들까지 분석된다. 반드시 `daegu_bus_app` 루트에서 실행.
- 이관 완전성은 컴파일만 믿지 말고 **기계적 대조**로 확인한다. 예 (MainActivity
  분리에서 사용):
```bash
git show HEAD:<원본파일> | grep -oE '"[a-zA-Z]+" ->' | sort | uniq -c > /tmp/old.txt
cat <신규파일들> | grep -oE '"[a-zA-Z]+" ->' | sort | uniq -c > /tmp/new.txt
diff /tmp/old.txt /tmp/new.txt   # 함수 목록이면 grep -oE 'fun \w+' 등으로 응용
```

### 커밋
- conventional commits (`refactor:` / `test:` / `docs:`), 단계당 1커밋, docs는
  별도 커밋. push는 사용자가 요청할 때만.
- 커밋 전 `git status`로 의도한 파일만 스테이징됐는지 확인. 이 저장소 작업트리에는
  릴리스/배포 관련 미추적 파일이 상존하므로 `git add .` 금지.

### 절대 하지 말 것
- 알림 구현을 `NotificationCompat.Builder` 이외로 바꾸기 (2026-02-16 결정,
  배경은 devlog 참조)
- `flutter upgrade`, 의존성 버전 변경, `pubspec.yaml` 버전 변경
- Codex/Cursor가 만질 수 있는 파일의 병렬 수정 유발 (AGENTS.md)
- 원본 대비 diff가 커지는 재포맷 (dart format이 자동으로 하는 것은 허용)

### 읽기 순서 (모든 세션 공통)
1. `AGENTS.md` → `docs/index.md` → 작업 관련 `docs/topics/*.md`
2. 이 문서의 해당 작업 섹션
3. 대상 파일 (부분 읽기로 시작하되, 옮길 블록은 반드시 전체를 읽고 옮긴다)

---

## 작업 1: BusAlertService.kt 분리 — 완료 (2026-07-25)

> ✅ 4단계 모두 완료. `BusAlertService.kt`: 2,535 → 1,620줄 (목표였던 ~1,200줄에는
> 못 미침 — 남은 것은 대부분 서비스 라이프사이클 자체(onCreate/onStartCommand/
> onDestroy)와 여러 협력 클래스에 걸친 조정 로직이라 추가 분리는 새로운 판단이
> 필요해 이 작업 범위 밖으로 남겨둔다). 각 단계 verbatim 이동을 `git diff HEAD`로
> 대조 확인, 컴파일 통과. **실기기(adb) 검증은 아직 못 함** — devlog
> 2026-07-25 (2~4차) 엔트리에 확인해야 할 구체적 시나리오를 남겨뒀다.

**목표**: 2,535줄 → 코어 서비스 ~1,200줄 이하. 서비스 라이프사이클·상태 소유는
남기고, 독립 가능한 로직을 협력 클래스로 이동.

### 최종 구조 (2026-07-25 기준)

| 파일 | 줄 | 역할 |
|---|---|---|
| `BusAlertService.kt` | 1,620 | 서비스 라이프사이클·상태 소유, 협력 클래스로의 위임 |
| `BusAlertAutoAlarmNotifier.kt` | 870 | 자동알람 알림 + 경량 모드 (2026-07-25 확장) |
| `BusAlertTrackingManager.kt` | 705 | 추적 루프 + 중지 로직 (2026-07-25 확장) |
| `BusAlertTtsController.kt` | 384 | TTS 발화·오디오 라우팅 |
| `BusAlertNotificationUpdater.kt` | 293 | 알림 조립·갱신 (2026-07-25 확장) |
| `BusAlertAlarmSoundPlayer.kt` | 97 | 알람음 재생 |
| `BusAlertCommandParser.kt` | 70 | ServiceCommand 파싱 (2026-07-25 신규) |
| `BusAlertParsers.kt` | 46 | 파싱 |
| `TrackingInfo.kt` | 25 | 추적 데이터 모델 |

### 분리 방향 (단계 = 커밋 단위) — 전부 완료
1. **명령 파싱 분리** ✅: `parseCommand`/`ServiceCommand`를
   `BusAlertCommandParser.kt`로. Intent extras 읽기뿐이라 Context 의존 없음.
2. **중지 로직 이동** ✅: `stopTrackingForRoute`(이미 콜백으로 되불리던 함수),
   `stopSpecificTracking`, `stopAllTracking`을 `BusAlertTrackingManager`로.
   `sendCancellationBroadcast`(호출부가 이 둘뿐이라 같이 이관)도 포함.
   서비스 라이프사이클 상태(`isServiceActive`/`instance`/
   `isManuallyStoppedByUser` 등)는 getter/setter 콜백으로 다리를 놓았다 —
   3개 함수가 서로 얽혀 있어 계획보다 커밋을 2개로 나눠 진행했다
   (`stopTrackingForRoute` 먼저, 나머지 둘은 별도 세션에서).
3. **자동알람 경량 모드 이동** ✅: `handleAutoAlarmLightweight` /
   `stopAutoAlarmLightweight` / `updateAutoAlarmBusInfo`를
   `BusAlertAutoAlarmNotifier`로. 이 클래스는 이미 `service: BusAlertService`
   전체 참조를 갖고 있어(콜백 아님), 필요한 `private` 멤버를 `internal`로
   넓히는 방식으로 이동했다.
4. **알림 조립 이동** ✅: `showOngoingBusTracking` / `updateTrackingNotification` /
   `showBusArrivingSoon`을 `BusAlertNotificationUpdater`로.
   `BusAlertNotificationUpdater`의 생성자 타입을 `Service` → `BusAlertService`로
   넓혀 3단계와 같은 방식을 재사용했다.

3~4단계에서 쓴 패턴(협력 클래스가 `service: BusAlertService` 전체 참조를 갖고
필요한 멤버를 `internal`로 넓히는 방식)이 2단계의 콜백 주입 방식보다 새 코드
이동을 훨씬 적은 diff로 끝낼 수 있었다. **다음에 비슷한 이동을 할 때는 콜백
주입보다 이 패턴을 먼저 고려할 것.**

### 겪은 함정과 실제 대응
- **코루틴 스코프 소유권**: 우려했던 것과 달리 `stopSpecificTracking`/
  `stopAllTracking`은 애초에 동기 함수였다(코루틴을 스폰하지 않음) — 이동 후에도
  스코프 소유권 문제 없음. `stopTrackingForRoute`만 `serviceScope.launch`를
  쓰는데, 이 스코프는 여전히 서비스가 소유하고 협력 클래스는 주입받은 참조로만
  쓴다.
- Foreground 서비스 타이밍(`startForeground` 호출 경로)은 옮기지 않고 그대로
  뒀다 — `BusAlertNotificationUpdater.updateOngoing()`이 이미 이 책임을 갖고
  있었고, 이번에 옮긴 함수들은 그걸 호출만 한다.
- 채널 핸들러가 호출하는 public 메서드(`stopTrackingForRoute`,
  `showOngoingBusTracking`, `updateTrackingNotification`)는 시그니처를 그대로
  두고 본문만 위임으로 바꿨다. 외부 호출부가 없는 것으로 확인된(grep 전체 검색)
  public 메서드(`updateAutoAlarmBusInfo`, `showBusArrivingSoon`)도 혹시 몰라
  삭제 대신 위임 스텁만 남겼다.
- Log 태그: 이동한 함수의 `Log.d(TAG, ...)`가 원래 참조하던 `BusAlertService`의
  `TAG`와, 이동 대상 클래스 자신의 TAG 상수가 다를 수 있다 — 실제로
  `BusAlertAutoAlarmNotifier`는 자기 TAG가 "BusAlertAutoAlarmNotifier"라
  그대로 옮기면 로그 태그가 조용히 바뀔 뻔했다. 리터럴 `"BusAlertService"`로
  치환해 원래 태그를 보존했다 (`BusAlertNotificationUpdater`는 우연히 자기
  TAG도 "BusAlertService"라 치환이 필요 없었다).

### 검증
- 단계마다 `:app:compileDebugKotlin` (저장소에 `gradlew`/`gradlew.bat`가
  없으면 — `.gitignore` 대상, Flutter가 최초 빌드 시 생성 — 캐시된 Gradle
  배포판을 `--project-dir android`로 직접 호출) + `git show HEAD:<원본>`과
  신규 위치를 `diff`로 대조.
- **아직 안 함**: 실기기 스모크. devlog 2026-07-25 (2~4차) 각 엔트리 하단에
  확인해야 할 구체적 시나리오를 적어뒀다 — 다음에 실기기가 준비되면 그 목록을
  그대로 체크리스트로 쓸 것. **2026-07-28 갱신**: 이후 세션에서 adb로 연결된
  실기기 접근이 가능해졌다 (`docs/devlog.md` 2026-07-25 sideload 검증 엔트리
  참조). 지도 CTA 검증에서 쓴 것과 같은 방식(`adb install`, `uiautomator dump`
  + `input tap`, `logcat`)을 이 목록에도 적용할 수 있다.

---

## 작업 1b: BusAlertService.kt 추가 축소 (작업 1 후속)

> 작업 1의 4단계를 모두 마쳤지만 목표였던 ~1,200줄에는 못 미쳤다 (1,620줄).
> 한 세션에 전체를 밀어붙이면 시간이 너무 오래 걸린다는 게 확인됐으므로,
> 아래처럼 위험도가 낮은 것부터 4개 세션으로 쪼갠다. **1b-1~1b-3만 끝내도
> 합계 ~525줄이 줄어 1,095줄로 목표를 이미 달성한다** — 가장 위험한 1b-4
> (onStartCommand)는 그 경우 손댈 필요가 없다.

### 현재 구조 (2026-07-28 기준, `git grep -nE` 결과)

| 블록 | 대략 위치 | 줄수 | 비고 |
|---|---|---|---|
| `onCreate`/`onStartCommand` | 148~643행 | ~495 | 서비스 시작·명령 디스패치. `onStartCommand` 본문만 ~390줄 |
| `updateBusInfo`/`updateBusInfoFromFlutter`/`checkNextBusAndNotify`/`checkArrivalAndNotify`/`updateTrackingInfoFromFlutter` | ~~756~876, 1008~1044, 1227~1451행~~ | ~~340~~ | ✅ 1b-3 완료 (2026-07-28) — `BusAlertTrackingManager.kt`로 이동(신규 파일 대신 기존 클래스 확장). 실기기 검증 아직 미완 |
| `cancelOngoingTracking`/`cancelNotification`/`cancelAllNotifications`/`stopTrackingIfIdle`/`sendAllCancellationBroadcast` | ~~1095~1222행~~ | ~~130~~ | ✅ 1b-2 완료 (2026-07-28) — `BusAlertTrackingManager.kt`로 이동. `checkAndStopService`는 죽은 코드로 판명돼 삭제 |
| 하단 top-level 유틸/확장 함수 + `NotificationDismissReceiver` | ~~1562~1620행~~ | ~~55~~ | ✅ 1b-1 완료 (2026-07-28) — `BusAlertModels.kt`로 이동 |

### 1b-1: 하단 유틸/확장 함수 분리 (가장 쉬움, ~55줄) — 완료 (2026-07-28)

> ✅ `BusAlertModels.kt` 신규 생성(69줄)으로 verbatim 이동 완료. `BusAlertService.kt`:
> 1,620 → 1,563줄. `getNotificationChannels` 호출부는 저장소 전체에 정의부 외
> 0건이었다(계획서가 우려한 "다른 파일에서 호출" 케이스는 실제로 없었음).
> 상세는 devlog 2026-07-28 참조.

**읽기 순서**: 이 섹션 → `BusAlertService.kt` 1562~1620행만.

- 대상: `NotificationDismissReceiver`(BroadcastReceiver, 1562행), `isSamsungOneUi()`
  (1571행), `getNotificationChannels()`(1575행), `StationArrivalOutput.toMap()`/
  `RouteStation.toMap()`/`BusInfo.toMap()`/`StationArrivalOutput.BusInfo.toMap()`
  (1585~1620행) — 전부 top-level 선언이라 서비스 인스턴스 상태에 의존하지 않는다.
- 새 파일 `BusAlertModels.kt`(같은 `services` 패키지)로 verbatim 이동.
- 함정: `getNotificationChannels`는 다른 파일(채널 생성 로직)에서 호출될 수 있다 —
  이동 전 grep으로 호출부를 확인하고, import만 필요하면 추가한다(로직 변경 없음).
- 완료 기준: `BusAlertService.kt` ≤ ~1,565줄, 컴파일 통과, `git show HEAD:...`
  diff 대조로 이동 외 변경 없음 확인.

### 1b-2: 취소 로직 → BusAlertTrackingManager (중간, ~130줄) — 완료 (2026-07-28)

> ✅ 5개 함수 모두 verbatim 이동, 새 콜백 0개(기존 생성자 파라미터로 충분했음).
> `BusAlertService.kt`: 1,563 → 1,444줄. `checkAndStopService()`는 grep으로
> 저장소 전체 참조 0건(private, dead code)임을 확인해 이관 대신 삭제 — 계획서의
> "대상" 목록에 있었지만 공통 원칙의 죽은 코드 삭제 기준이 우선했다. 상세는
> devlog 2026-07-28 (2차) 참조.

**읽기 순서**: 이 섹션 → 작업 1의 "2단계" 서술(콜백 주입 패턴 참고) →
`BusAlertService.kt`의 `cancelOngoingTracking`(1095행)부터 `checkAndStopService`
(1212~1227행)까지 → 현재 `BusAlertTrackingManager.kt`.

- 대상: `cancelOngoingTracking`/`cancelNotification`/`cancelAllNotifications`/
  `stopTrackingIfIdle`/`sendAllCancellationBroadcast`(이미 작업 1에서 관련
  브로드캐스트 헬퍼가 옮겨졌는지 확인)/`checkAndStopService`.
- `BusAlertTrackingManager`는 이미 서비스 라이프사이클 상태 콜백 다수를 갖고
  있다(작업 1의 2단계 참조) — 추가로 필요한 콜백만 생성자에 더한다. 새 콜백을
  10개 이상 추가해야 하면 계획보다 범위가 크다는 신호이니 일부만 옮기고 나머지는
  devlog에 이유를 남긴 채 다음 세션으로 미룰 것 (작업 1의 2단계에서 실제로 이렇게
  했다).
- 함정: `cancelNotification`/`cancelAllNotifications`는 채널 핸들러가 직접 호출할
  수 있는 public 메서드일 가능성이 높다 — grep으로 호출부를 확인하고, 있으면
  시그니처를 유지한 채 위임 스텁만 남긴다.
- 완료 기준: `BusAlertService.kt` ≤ ~1,435줄, 컴파일 통과, diff 대조 완료.

### 1b-3: 도착 확인/추적정보 갱신 클러스터 → 신규 협력 클래스 (가장 큰 감소, ~340줄) — 완료 (2026-07-28)

> ✅ 5개 함수 모두 verbatim 이동. **신규 파일이 아니라 `BusAlertTrackingManager`를
> 확장** — 이동 대상 3개(`updateBusInfo`/`checkArrivalAndNotify`/
> `checkNextBusAndNotify`)가 이미 그 클래스의 추적 루프에서 콜백으로 호출되고
> 있어서 겹침이 명백했다. 콜백 3개 제거(셀프 호출로 전환) + 4개 신설
> (`notificationHandler`, `restartPreventionDurationMs`,
> `lastManualStopTimeProvider`, `alertOnArrivalOnlyProvider`) = 순증가 1개.
> `BusAlertService.kt`: 1,444 → 1,101줄. **실기기 검증은 아직 미완** — 사용자
> 지시로 오케스트레이터가 adb로 이어서 확인하기로 하고 이 세션은 코드 이동만
> 완료. 상세는 devlog 2026-07-28 (3차) 참조.

**읽기 순서**: 이 섹션 → `docs/topics/tts-audio.md`(TTS 출력 정책, 이 클러스터가
TTS를 트리거함) → `BusAlertService.kt`의 `updateBusInfo`(756행)부터
`updateTrackingInfoFromFlutter`(1348~1451행)까지 전체.

- 대상: `updateBusInfo`, `updateBusInfoFromFlutter`, `checkNextBusAndNotify`,
  `checkArrivalAndNotify`, `updateTrackingInfoFromFlutter`. 작업 1의 3~4단계에서
  검증된 패턴(신규 클래스가 `service: BusAlertService` 전체 참조를 갖고, 필요한
  `private` 멤버를 `internal`로 넓힘)을 우선 고려한다 — 콜백 주입보다 diff가
  훨씬 작았다.
- 새 파일(가칭 `BusAlertArrivalMonitor.kt`)로 이동. 기존 협력 클래스 중 역할이
  겹치는 게 없는지(`BusAlertTrackingManager`? `BusAlertNotificationUpdater`?)
  먼저 확인하고, 겹치면 새 파일 대신 기존 클래스를 확장한다.
- 함정: 이 클러스터는 TTS 발화(`ttsController` 경유)와 알림 갱신을 실제로
  트리거하는 지점이라, 계획서의 "절대 하지 말 것"(알림 구현을
  `NotificationCompat.Builder` 이외로 바꾸지 말 것)과 특히 관련이 크다. 로직은
  건드리지 말고 이동만 한다.
- **실기기 검증 중요**: 이 클러스터를 옮긴 뒤에는 devlog 2026-07-25 (3차)에
  적힌 "알림 렌더링"/"stationId 보정 재시도"/"1초 후 백업 notify()" 항목을
  실기기로 반드시 확인한다 (오케스트레이터가 adb로 진행 가능).
- 완료 기준: `BusAlertService.kt` ≤ ~1,095줄, 컴파일 통과, diff 대조 완료,
  실기기 확인 완료 또는 devlog에 미확인 항목 명시.

### 1b-4: onStartCommand 디스패치 본문 축소 (~390줄, 고위험 — 신중히 판단)

> **1b-1~3을 마쳐 목표(~1,200줄)를 이미 달성했다면, 이 단계는 필수가 아니다.**
> 진행 여부는 다음 세션에서 devlog/이 문서를 다시 보고 판단할 것 — 지금 미리
> 결정하지 않는다.

- `onStartCommand`(251~643행)는 `parseCommand()`가 반환한 `ServiceCommand`를
  `when`으로 분기해 각 케이스를 처리하는 본문이다. `startForeground` 호출
  시점·순서가 여기 있을 가능성이 높다 — Android는 `Service.onStartCommand`
  진입 후 일정 시간 안에 `startForeground`가 호출되지 않으면
  `ForegroundServiceDidNotStartInTimeException`을 던진다.
- 옮기더라도 `startForeground` 호출은 `onStartCommand` 안에 남겨야 한다 —
  협력 클래스로 위임하는 코드 경로가 길어지면 타이밍이 깨질 수 있다.
- **진행하려면**: 먼저 실기기로 각 `ServiceCommand` 분기(수동 알람 시작/자동알람
  시작/중지 등)를 한 번씩 트리거해 정상 동작을 스크린샷/logcat으로 기록해두고,
  이동 후 같은 시나리오를 다시 확인한다. 이 사전 기록 없이는 착수하지 않는다.

---

## 작업 2: UI 위젯 테스트 보강 (작업 3~5의 선행 조건)

**목표**: 분리 대상 3개 파일의 관찰 가능한 동작을 위젯 테스트로 고정해,
UI 분리가 동작을 깨면 테스트가 잡아내게 한다.

### 현재 상태
- `test/`에 38건 통과 중이나 대부분 로직/파싱 테스트. 화면 위젯 테스트는
  `widget_test.dart`(스모크)와 `agent_automation_test.dart` 수준.
- `test/helpers/`에 기존 테스트 헬퍼 있음 — 먼저 읽고 재사용할 것.

### 방법
- 네이티브 호출은 `TestDefaultBinaryMessengerBinding.instance
  .defaultBinaryMessenger.setMockMethodCallHandler`로 채널 mock.
  채널 이름·메서드 목록은 `docs/topics/method-channels.md` 참조.
- ApiService가 정적 메서드라 주입이 어려우면: 화면을 통째로 pump하는 대신
  하위 위젯(예: `home_widgets.dart`의 `HomeNearbyStopsRow` 등 6개 클래스)을
  데이터를 직접 넘겨 pump하는 테스트부터 작성 — 이것만으로도 분리 검증에는
  충분하다.
- 고정할 것 (화면당 3~6케이스면 충분):
  - 주어진 데이터로 렌더링되는 핵심 텍스트/버튼 존재
  - 탭 시 콜백 호출 (예: 버스 행 탭 → `showUnifiedBusDetailModal` 경로)
  - 빈 데이터/에러 상태 표시
- **과욕 금지**: golden test, 통합 테스트 도입하지 않는다. 분리 작업의 안전망이
  목적이다.

### 완료 기준
- map_screen / unified_bus_detail_widget / home_widgets 각각에 대한 위젯 테스트
  파일 추가, `flutter test` 전체 통과, devlog 기록.

---

## 작업 3~5: UI 모놀리스 분리 (작업 2 완료 후에만)

공통 패턴: **private 위젯 클래스를 파일로 승격**. 이번에 검증된 선례가
`alarm_screen.dart`(1,630줄)에서 `AutoAlarmEditScreen`(664줄)을
`auto_alarm_edit_screen.dart`로 분리한 커밋 `51f7d9d` — 이 diff를 먼저 볼 것.

### 작업 3: map_screen.dart (1,578줄)
- 구조: `MapScreen` + `_MapScreenState`(133행~끝, 사실상 전부) +
  `_TimedCacheEntry`.
- 분리 후보: WebView/JS 브리지 로직 vs 마커·정류장 데이터 준비 vs UI 오버레이.
  `_MapScreenState`가 단일 거대 State라 **메서드 그룹 → mixin 또는 위임 클래스**
  추출이 현실적. 상태 변수를 공유하는 메서드들은 무리해서 쪼개지 말 것.
- 함정: `AutomaticKeepAliveClientMixin` 유지, WebView 초기화 실패 경로는
  기존 테스트(`agent_automation_test.dart`)가 고정하고 있음.

### 작업 4: unified_bus_detail_widget.dart (1,411줄)
- 구조: `UnifiedBusDetailWidget`(+State, 18~924행) /
  `showUnifiedBusDetailModal`(925행) / `_BusDetailModalContent`(+State, 950행~).
- 1단계: `_BusDetailModalContent` + `showUnifiedBusDetailModal`을
  별도 파일로 (모달 계열 ~460줄). `_` 클래스가 파일 밖에서 쓰이게 되면 `_` 제거
  필요 — 호출부 3곳(favorites 687, home_widgets 860, route_map 670) 확인.
- 함정: 이 위젯의 `_setAlarm`/`_cancelAlarm`은 boarding_alarm_actions로 통합하지
  **않은** 별도 동작이다 (TTS·동일 정류장 타 버스 취소 — devlog 2026-07-07 참조).
  분리하면서 실수로 통합하지 말 것.

### 작업 5: home_widgets.dart (1,032줄)
- 구조: 독립 StatelessWidget 6개 (`HomeSectionHeader` 33행, `HomeNearbyStopsRow`
  76행, `HomeFavoriteStopsRow` 251행, `HomeFavoriteBusList` 562행,
  `HomeMainStationCard` 678행, `HomeRouteItem` 780행).
- 가장 기계적인 분리: 클래스별 파일로 나누고 배럴 파일(`home_widgets.dart`)이
  전부 export하게 하면 **호출부 import 수정이 0건**이 된다. 이 방식 권장.

### 공통 완료 기준
- 각 파일 ≤ ~700줄, `flutter analyze` 0건 + `flutter test`(작업 2에서 늘어난
  기준선) 전체 통과, 커밋은 파일당 1개.

---

## 작업 6: alarm_service.dart 잔여 이관 (1,150줄)

- `lib/services/alarm/`에 모듈 15개(facade, scheduler, repository, engine 등)가
  이미 있고, `AlarmService`(ChangeNotifier)가 facade와 역할이 겹친다.
- **먼저 조사부터**: `alarm_facade.dart`와 `alarm_service.dart`의 public 멤버를
  대조해 (a) facade에 이미 있는 것 (b) service에만 있는 것 (c) 호출부가 어느 쪽을
  쓰는지 목록화한다. 조사 결과를 devlog에 남기고, 이관은 그 다음 세션에서 해도
  된다.
- 함정: `AlarmService`는 ChangeNotifier로 Provider에 물려 있다. UI 리스너가
  깨지지 않도록 notifyListeners 경로는 마지막까지 service에 남긴다.
- 관련 테스트가 이미 있다: `alarm_service_auto_alarm_restore_test.dart`,
  `alarm_service_restart_prevention_test.dart`, `auto_alarm_logic_test.dart` —
  이관 중 이 테스트들이 기준선이다.

---

## 선례 (참고용 diff)

| 커밋 | 내용 | 참고할 점 |
|---|---|---|
| `5086dad` | MainActivity 채널 핸들러 분리 (2,622→631줄) | verbatim 이동 + 케이스 grep 대조 방법 |
| `51f7d9d` | alarm_screen에서 AutoAlarmEditScreen 분리 | Flutter 화면 분리 패턴 |
| `c70f836` | 설정 타일 공용화 | 파라미터화로 중복 제거하는 방식 |
| `84816bd` | 승차 알람 토글 통합 | 의도된 동작 변화를 devlog에 명시하는 방식 |
