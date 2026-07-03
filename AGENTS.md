# 대구 버스 앱 (daegu_bus_app)

대구광역시 버스 도착 정보·승차 알람 Flutter 앱. Android 우선 타겟(Android 16 Live Update / Samsung One UI Now Bar 지원).

## 빌드·검증
- 의존성: `flutter pub get`
- 정적 분석: `flutter analyze` — 코드 변경 후 필수
- 디버그 빌드: `flutter build apk --debug`
- 릴리스 빌드: `.\build_release.ps1` (APK만: `-Apk`)
- 네이티브(Kotlin) 변경 후: `./gradlew :app:compileDebugKotlin`으로 컴파일 확인

## 구조
- `lib/` — Flutter UI·서비스 (알람 로직: `lib/services/alarm_service.dart`)
- `android/app/src/main/kotlin/com/devground/daegubus/` — 네이티브 알림·버스 추적 (core / models / receivers / services / utils)
- applicationId `com.devground.daegubus`, compileSdk/targetSdk 36

## 규칙
- 알림은 `NotificationCompat.Builder` 기반을 유지할 것 (2026-02-16 결정 — 배경은 devlog 참조)
- 개발 이력·의사결정 기록은 `docs/devlog.md`에 추가할 것. **이 파일(AGENTS.md)에 일지를 쓰지 말 것.**
