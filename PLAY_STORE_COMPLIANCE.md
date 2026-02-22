# Play Store 제출 체크리스트

## 1) 개인 정보 처리방침

- 앱에는 사용자 계정, 결제, 로그인 기능이 없습니다.
- 앱은 다음 데이터만 처리합니다.
  - 앱 사용 시점의 현재 위치(버스 정류장 검색/지도 표시 목적)
  - 로컬 즐겨찾기/알람 설정 데이터
  - 앱 로그(디버깅용 임시 데이터, 기본적으로 디버그 빌드에서만 수집 권장)
- 모든 API 키는 빌드 시 `--dart-define` 또는 환경변수로 주입되며, 앱 번들 내 평문 `.env` 파일을 포함하지 않습니다.
- 버스 노선·정류장 데이터는 대구버스 공개 API 응답을 전달 받은 후 즉시 표시됩니다.
- 광고는 Google AdMob SDK를 사용하되, 테스트 ID가 아닌 실제 운영 ID로만 빌드합니다.

## 2) 접근 권한 사용 근거 (Play Console 입력용)

### ACCESS_FINE_LOCATION / ACCESS_COARSE_LOCATION
- 사용 목적: `주변 정류장 검색`, `지도/현재 위치 중심 보기`
- 사용 시점: 앱이 사용자에게 위치 기반 기능을 표시할 때(전경).

### ACCESS_BACKGROUND_LOCATION
- 본 앱은 현재 백그라운드 위치 권한을 사용하지 않습니다.
- AndroidManifest에서 `ACCESS_BACKGROUND_LOCATION` 권한이 제거되어 있으므로 Play Console의 `백그라운드 위치` 항목에는 `미사용`으로 기재하세요.

## 3) Play Store 업로드 직전 필수 항목

1. 개인정보처리방침 URL 등록
2. AdMob 앱 ID 및 광고 단위 ID가 운영값인지 최종 확인
3. `android/key.properties`로 릴리즈 서명 키 적용 (`build.gradle` 릴리즈 빌드에서 사용)
4. `com.example.*` 패키지명이 아닌 최종 `applicationId` 사용
5. 릴리즈 빌드에서 로그 비활성화 (`ENABLE_LOGGING = false`)
