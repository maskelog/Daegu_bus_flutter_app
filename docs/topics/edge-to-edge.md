# Android edge-to-edge

## 현재 구성

- 앱은 `compileSdk`/`targetSdk` 36이며 Android 16에서도 edge-to-edge를 해제하지 않는다.
- Flutter 진입점은 `SystemUiMode.edgeToEdge`를 설정하고 테마에 맞춰 시스템 바 아이콘 명도를 갱신한다.
- `MainActivity.onCreate()`는 `super.onCreate()` 뒤 `WindowCompat.enableEdgeToEdge(window)`를 호출한다.
- Android 10 이상에서는 3버튼 내비게이션 바의 강제 대비를 끈다.
- `AndroidManifest.xml`의 `adjustResize`와 Flutter 화면의 `SafeArea`가 시스템 바·IME 인셋을 처리한다.
- `values-v35/styles.xml`은 상태·내비게이션 바 대비 강제를 비활성화한다.

## Play Console 지원 중단 API 발견 항목

프로덕션 `62 (1.0.3)`에는 다음 Android 15 지원 중단 API가 포함돼 있다.

- `Window.setNavigationBarDividerColor`
- `Window.setStatusBarColor`
- `Window.setNavigationBarColor`

APK 역참조 결과, 사용하지 않던 직접 Material Components 의존성이
`MaterialDatePicker` 시작점을 포함하고 있어 해당 의존성을 제거했다. 현재 릴리스 APK에는
`MaterialDatePicker`가 없다.

세 API 참조 자체는 Flutter 3.35.6의 Android 임베딩과 AndroidX
`WindowCompat.enableEdgeToEdge()`의 하위 Android 호환 경로에 남는다. 앱 코드에서 시스템 바
색상 API를 직접 호출하지 않으며, Android 15/16에서는 플랫폼이 edge-to-edge를 강제한다.
따라서 Play Console 정적 분석 경고의 완전한 해소 여부는 다음 APK 업로드 후 확인해야 한다.

## 후속 확인 상태

- `1.0.4+65` AAB는 로컬 빌드됐지만 Play Console 업로드·분석 결과는 아직 이 문서에
  기록되지 않았다.
- 업로드 후 지원 중단 API 발견 항목이 남는지와 새 시작점이 무엇인지 확인한다. 결과에
  따라 이 절을 갱신하고 [devlog.md](../devlog.md)에 기록한다.
- 2026-07-15 빌드에서 Android Studio와 command-line tools의 SDK XML 버전 불일치
  경고가 1건 발생했다. SDK 도구 버전을 정렬한 뒤 다음 빌드에서 경고가 사라졌는지
  확인한다.

## 검증 기준

- `flutter test test/edge_to_edge_config_test.dart`
- `flutter analyze`
- `./gradlew :app:compileDebugKotlin`
- `build_release.ps1 -Apk` 후 `apkanalyzer dex reference-tree`로 호출 시작점 확인
- 제스처 및 3버튼 내비게이션에서 상·하단 겹침, 키보드 입력 화면, 다크/라이트 아이콘 대비를 실기기 확인
