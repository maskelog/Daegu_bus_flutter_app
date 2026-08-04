# 빌드 품질·CI·의존성

> 마지막 갱신: 2026-08-04

## 검증 게이트

- Dart 정적 분석: `flutter analyze`
- Flutter 테스트: `flutter test` — 현재 기준선 68건
- Android JVM 테스트·lint: `android/`에서
  `.\gradlew.bat :app:testDebugUnitTest :app:lintDebug`
- Kotlin만 바뀐 빠른 확인: `.\gradlew.bat :app:compileDebugKotlin`
- 최종 디버그 산출물: `flutter build apk --debug`
- `.github/workflows/ci.yml`은 main push와 pull request에서 위 검증을 자동 실행한다.
  CI 기준은 Flutter 3.35.6, Java 17, Gradle wrapper 8.11.1이다.

## 재현 가능한 체크아웃

- 앱 저장소이므로 `pubspec.lock`을 추적한다.
- `android/gradlew`, `android/gradlew.bat`, `gradle-wrapper.jar`,
  `gradle-wrapper.properties`를 함께 추적한다. 새 체크아웃도 로컬 캐시에 의존하지
  않고 같은 Gradle 버전을 사용한다.
- `.claude/settings.local.json`과 `.claude/worktrees/`는 개발자 로컬 상태다. Git에서
  추적하지 않는다. 2026-08-03 점검에서 끊어진 `funny-fermat` worktree와 로컬 권한
  파일은 휴지통으로 정리했으며, 필요한 설정은 Claude Code가 다시 생성할 수 있다.
  미완성 커밋은 `claude/funny-fermat`와 `origin/claude/funny-fermat` 브랜치에 보존한다.

## 의존성 정책

- 2026-08-03에 lockfile 내 호환 업데이트 54개와 직접 의존성 메이저 업데이트를
  적용했다. `flutter_dotenv` 6의 `testLoad` 제거는 `loadFromString`으로 이전했다.
- `permission_handler`는 12.x로 제한한다. 13.x는 compileSdk 37, AGP 9.0.1,
  Kotlin 2.3.20을 요구하므로 현재 SDK 36/AGP 8.9.1 기준과 맞지 않는다.
- 향후 메이저 업데이트는 하나씩 적용하고 `flutter analyze`, `flutter test`, Android
  JVM 테스트·lint, APK 빌드를 모두 통과시킨 뒤 유지한다.

## 정책 민감 Android 권한

- 정확 알람은 `SCHEDULE_EXACT_ALARM`만 선언하며, 미승인 시 부정확 알람으로
  폴백한다. `USE_EXACT_ALARM`은 선언하지 않는다.
- `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`와 `SYSTEM_ALERT_WINDOW`는 선언하지 않는다.
  배터리 최적화 안내는 직접 예외 요청 대신 시스템 설정 목록을 연다.
- 알림은 계속 `NotificationCompat.Builder`로 생성한다. 상태 표시줄 small icon은
  단색 벡터 `notification_icon`을 사용하고, RemoteViews 내부 그림과 분리한다.
  `android_quality_regression_test.dart`는 Live Update 경로에 네이티브 빌더,
  `setExtras()`, 수동 promoted 플래그 조작이 다시 들어오지 않도록 고정한다. 같은
  테스트가 `bus_api` 36개 메서드 집합과 책임별 operation 크기 상한도 검사한다.

## 알려진 로컬 환경 경고

- Android SDK XML 3/4 불일치 경고가 계속 재현된다. Android Studio와 command-line
  tools 버전 차이에서 나오며 현재 빌드는 성공한다. 해소 기준은
  [follow-up-status.md](follow-up-status.md)에 유지한다.
