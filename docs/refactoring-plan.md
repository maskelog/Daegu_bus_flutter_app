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

- [ ] 작업 1: BusAlertService.kt 분리 (2,535줄) — **최우선**
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

## 작업 1: BusAlertService.kt 분리 — 최우선

**목표**: 2,535줄 → 코어 서비스 ~1,200줄 이하. 서비스 라이프사이클·상태 소유는
남기고, 독립 가능한 로직을 협력 클래스로 이동.

### 현재 구조
2026-01-29에 1차 분리된 협력 클래스들이 이미 있다 (같은 `services/` 패키지):

| 파일 | 줄 | 역할 |
|---|---|---|
| `BusAlertTtsController.kt` | 384 | TTS 발화·오디오 라우팅 |
| `BusAlertAutoAlarmNotifier.kt` | 635 | 자동알람 알림 |
| `BusAlertTrackingManager.kt` | 178 | 추적 상태 관리 |
| `BusAlertNotificationUpdater.kt` | 61 | 알림 갱신 |
| `BusAlertAlarmSoundPlayer.kt` | 97 | 알람음 재생 |
| `BusAlertParsers.kt` | 46 | 파싱 |
| `TrackingInfo.kt` | 25 | 추적 데이터 모델 |

재비대화된 큰 블록 (2026-07-07 기준 대략 위치 — 실행 시 재확인):
- `parseCommand` + `onStartCommand` 명령 디스패치: 261~689행 (~430줄)
- `stopSpecificTracking`: 708~922행 (~215줄)
- `checkArrivalAndNotify`: 1652~1773행
- `updateTrackingInfoFromFlutter` / `updateTrackingNotification`: 1773~1964행
- `stopAllTracking`: 1964~2137행 (~170줄)
- `handleAutoAlarmLightweight` / `stopAutoAlarmLightweight`: 2300~2478행

### 분리 방향 (단계 = 커밋 단위)
1. **명령 파싱 분리**: `parseCommand`와 ServiceCommand 관련 타입을
   `BusAlertCommandParser.kt`(신규)로. `onStartCommand`는 파서를 호출해
   디스패치만 남긴다. Intent extras 읽기가 전부이므로 Context 의존이 없어
   가장 안전한 첫 단계.
2. **중지 로직 통합**: `stopSpecificTracking` / `stopAllTracking` /
   `stopTrackingForRoute` 3개는 알림 취소·브로드캐스트·상태 정리가 중복된다.
   공통 부분을 `BusAlertTrackingManager`로 이동하되, **중복 제거가 아니라 이동
   먼저** — 3개의 미묘한 차이(브로드캐스트 여부, 알림 ID 처리)를 보존한 채
   옮기고, 통일은 별도 백로그로 남긴다.
3. **자동알람 경량 모드 이동**: `handleAutoAlarmLightweight` /
   `stopAutoAlarmLightweight` / `updateAutoAlarmBusInfo`를
   `BusAlertAutoAlarmNotifier`로. 이미 자동알람 담당 클래스가 있으므로 신규
   파일을 만들지 않는다.
4. **알림 조립 이동**: `showOngoingBusTracking` / `updateTrackingNotification` /
   `showBusArrivingSoon`의 NotificationCompat 조립 부분을
   `BusAlertNotificationUpdater`로.

### 주의 (이 작업의 함정)
- **코루틴 스코프 소유권**: `serviceScope`(또는 유사)는 서비스에 남긴다. 협력
  클래스는 suspend 함수나 콜백만 노출하고 자체 스코프를 만들지 않는다 —
  onDestroy 시 취소 보장이 깨진다.
- Foreground 서비스 규칙: `startForeground` 호출 경로(타이밍 포함)를 옮기지
  말 것. ANR/ForegroundServiceDidNotStartInTimeException 위험.
- `MainActivity.getInstance()` / `_methodChannel` 역참조가 서비스 안에 있다면
  그대로 둔다 (구조 개선은 별도 작업).
- 채널 핸들러(`channels/BusApiChannelHandler` 등)가 서비스의 public 메서드를
  호출한다. **public 시그니처를 바꾸지 말 것.** 바꾸면 컴파일이 잡아주긴 하지만
  diff가 번진다.

### 검증
- 단계마다 `:app:compileDebugKotlin` + 함수 목록 grep 대조.
- 전체 완료 후 실기기 스모크 (사용자에게 요청): 승차 알람 시작→알림 표시→종료
  버튼→알림 제거, 자동알람 1회 트리거.

### 완료 기준
- BusAlertService.kt ≤ ~1,200줄, 컴파일 통과, 함수 누락 0, devlog/topics 갱신.

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
