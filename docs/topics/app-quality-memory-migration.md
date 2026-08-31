# Google Play 앱 품질: 메모리·DEX·기기 이전

> 마지막 갱신: 2026-08-29
>
> 기준: [Android Developers Blog — Elevating app quality](https://android-developers.googleblog.com/2026/08/app-quality-memory-optimization-secure-onboarding.html)

## 적용 범위

Google Play은 2027년 2월부터 Anonymous RSS + Swap, Bitmap memory, DEX 최적화의
bad behavior threshold를 적용한다. 로그인 기능이 있는 앱의 Restore Credentials API
기반 Zero-Tap Sign-In 요구는 2027년 4월부터 적용한다.

이 앱은 사용자 계정이나 로그인 기능이 없으므로 Zero-Tap Sign-In 대상이 아니다.
향후 계정 기능을 추가하면 로그인 구현과 동시에 Restore Credentials API를 도입하고 이
판정을 갱신해야 한다.

## 동적 메모리와 Bitmap 대응

- 앱의 기본 진입 탭은 홈이다. `home_screen.dart`는 지도/노선도 탭이 선택되기 전에는
  해당 위젯을 생성하지 않는다. 따라서 Kakao WebView와 지도 그래픽 리소스를 시작부터
  숨긴 채 보유하지 않는다.
- 지도 탭을 벗어나면 `IndexedStack`의 해당 child를 빈 위젯으로 교체해 WebView를
  dispose한다. 다시 진입할 때 최신 상태로 지도를 생성한다.
- 지도 좌표 검색 캐시는 12개, 정류장 도착 캐시는 24개, 이름→ID 캐시는 100개로
  제한한다. background/cached 전환과 시스템 메모리 압박 때 모두 비운다.
- 노선 지도 버스 위치 타이머는 앱이 보이지 않을 때 중지하고 foreground 복귀 시에만
  재개한다.

## DEX 최적화

- Play용 release 빌드는 `minifyEnabled true`, `shrinkResources true`,
  `proguard-android-optimize.txt`, R8 full mode와 optimized resource shrinking을 쓴다.
- `localFastRelease=true`는 축소를 끄므로 Play 업로드에 사용하지 않는다.
- 로컬 설정만으로 Play의 최소 25% optimization/shrinking/obfuscation coverage 충족을
  확정하지 않는다. 업로드한 AAB의 Play Console DEX optimization insight가 최종 증거다.

## 실기기 메모리 기준선

- 2026-08-31 Galaxy Note10+의 디버그 빌드에서 지도 foreground `TOTAL PSS`는
  641,847KB, 홈 전환 후 background 상태는 499,531KB였다. 지도 WebView가 생성된 뒤
  홈으로 돌아오면 화면이 dispose되고 메모리가 감소하는 방향은 확인했다.
- 디버그 런타임 수치는 릴리스 빌드나 저RAM 기기의 Play 품질 지표를 대신하지 않는다.
  동일 릴리스 후보의 상태별 반복 측정과 Android vitals 확인은 계속 필요하다.

## 안전한 기기 이전

- Android 12 이상은 `data_extraction_rules.xml`, Android 11 이하는
  `backup_rules.xml`을 사용한다.
- 즐겨찾기, 사용자 설정, 자동 알람 정의가 든 `FlutterSharedPreferences.xml`은 이전을
  허용한다. 새 기기에서 사용자가 설정을 다시 만들 필요가 없도록 하기 위함이다.
- 앱 번들에서 복구 가능한 `bus_stops.db`와 네이티브 `BusRouteCache.xml`은 cloud backup과
  device transfer에서 제외한다. 불필요한 이전 용량과 오래된 API 캐시 복원을 막는다.
- cloud backup은 암호화 기능이 있는 기기에서만 허용한다. Android의 cache/no-backup
  디렉터리는 플랫폼 기본 정책대로 이전하지 않는다.

## 검증 경계

회귀 테스트는 지도의 lazy 생성, 캐시 상한/정리, 백업 규칙 연결, 사용자 설정 파일 보존을
검사한다. 실제 메모리 threshold와 DEX coverage는 로컬 테스트로 판정할 수 없으므로
[follow-up-status.md](follow-up-status.md)의 Play Console·실기기 측정을 완료해야 한다.
