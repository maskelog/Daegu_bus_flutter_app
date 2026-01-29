# 대구 버스 앱 개발 기록

## 2026-01-28: Android 16 Live Update 알림 구현

### 목표
Android 16의 Live Updates 기능을 사용하여 버스 알림에 실시간 업데이트 표시 (버스 아이콘이 Live Update 영역에 표시되도록)

### 참고 자료
- https://github.com/android/platform-samples/tree/main/samples/user-interface/live-updates/src/main

### 수정된 파일

#### 1. `android/app/build.gradle`
- `compileSdk`: `flutter.compileSdkVersion` → `36` (Android 16 지원)
- `targetSdk`: `flutter.targetSdkVersion` → `36` (Android 16 지원)
- `androidx.core:core-ktx`: `1.9.0` → `1.15.0` (최신 버전)

#### 2. `android/app/src/main/kotlin/com/example/daegu_bus_app/utils/NotificationHandler.kt`

##### Live Update 핵심 API 추가 (Reflection 사용)
Android 16 API가 아직 SDK에 공개되지 않아 Reflection으로 호출:

```kotlin
// setRequestPromotedOngoing(true) - Live Update 활성화 핵심
try {
    val setRequestPromotedOngoingMethod = nativeBuilder.javaClass.getMethod(
        "setRequestPromotedOngoing", Boolean::class.javaPrimitiveType
    )
    setRequestPromotedOngoingMethod.invoke(nativeBuilder, true)
    Log.d(TAG, "✅ setRequestPromotedOngoing(true) 호출 성공")
} catch (e: NoSuchMethodException) {
    Log.w(TAG, "⚠️ setRequestPromotedOngoing 메서드 없음 (Android 16 미만)")
} catch (e: Exception) {
    Log.e(TAG, "❌ setRequestPromotedOngoing 호출 실패: ${e.message}")
}

// setShortCriticalText(chipText) - 상태 칩 텍스트
try {
    val setShortCriticalTextMethod = nativeBuilder.javaClass.getMethod(
        "setShortCriticalText", CharSequence::class.java
    )
    setShortCriticalTextMethod.invoke(nativeBuilder, chipText)
    Log.d(TAG, "✅ setShortCriticalText('$chipText') 호출 성공")
} catch (e: NoSuchMethodException) {
    Log.w(TAG, "⚠️ setShortCriticalText 메서드 없음 (Android 16 미만)")
} catch (e: Exception) {
    Log.e(TAG, "❌ setShortCriticalText 호출 실패: ${e.message}")
}
```

##### 알림 카테고리 추가
```kotlin
.setCategory(Notification.CATEGORY_PROGRESS)
```

##### 아이콘 생성 함수 개선 (`createColoredBusIcon`)
Live Update 영역에 아이콘이 잘 보이도록 최적화:
- 아이콘 크기: 48x48dp (Live Update 권장 크기)
- 원형 배경 + 흰색 아이콘으로 변경
- `ic_bus_large.png` 우선 사용

```kotlin
private fun createColoredBusIcon(context: Context, color: Int, busNo: String): android.graphics.Bitmap? {
    try {
        val density = context.resources.displayMetrics.density
        val iconSizePx = (48 * density).toInt()

        val drawable = ContextCompat.getDrawable(context, R.drawable.ic_bus_large)
            ?: ContextCompat.getDrawable(context, R.drawable.ic_bus_notification)
            ?: return null

        val bitmap = android.graphics.Bitmap.createBitmap(
            iconSizePx, iconSizePx, android.graphics.Bitmap.Config.ARGB_8888
        )
        val canvas = android.graphics.Canvas(bitmap)

        // 원형 배경 그리기
        val paint = android.graphics.Paint().apply {
            this.color = color
            isAntiAlias = true
            style = android.graphics.Paint.Style.FILL
        }
        canvas.drawCircle(iconSizePx / 2f, iconSizePx / 2f, iconSizePx / 2f - 2 * density, paint)

        // 아이콘 그리기 (흰색)
        val iconPadding = (8 * density).toInt()
        drawable.setBounds(iconPadding, iconPadding, iconSizePx - iconPadding, iconSizePx - iconPadding)
        drawable.setTint(android.graphics.Color.WHITE)
        drawable.draw(canvas)

        return bitmap
    } catch (e: Exception) {
        Log.e(TAG, "버스 아이콘 생성 실패: ${e.message}")
        return null
    }
}
```

##### 플래그 설정 방식 수정 (Kotlin 컴파일 오류 해결)
```kotlin
// 수정 전 (컴파일 오류)
builtNotification.flags = builtNotification.flags or
    Notification.FLAG_ONGOING_EVENT or ...

// 수정 후
val liveUpdateFlags = Notification.FLAG_ONGOING_EVENT or
    Notification.FLAG_NO_CLEAR or
    Notification.FLAG_FOREGROUND_SERVICE or
    0x00000080 // FLAG_PROMOTED_ONGOING (Android 16+)
builtNotification.flags = builtNotification.flags or liveUpdateFlags
```

### Live Update 작동 조건 (Android 16+)
1. `setOngoing(true)` - 진행 중인 알림
2. `setRequestPromotedOngoing(true)` - Live Update 승격 요청
3. `setShortCriticalText()` - 상태 칩 텍스트 (예: "5분")
4. `setProgress()` - 진행 바
5. `setLargeIcon()` - 아이콘
6. `setCategory(Notification.CATEGORY_PROGRESS)` - 카테고리

---

## 2026-01-28 (2차): ProgressStyle로 버스 아이콘 진행 바 이동 구현

### 문제
- 버스 아이콘이 오른쪽 Large Icon 위치에만 표시됨
- 진행 바 위에서 버스 아이콘이 이동하지 않음

### 해결: `Notification.ProgressStyle` 사용

#### 핵심 변경 사항

##### 1. `InboxStyle` 제거 → `ProgressStyle` 사용
```kotlin
// 기존: InboxStyle (여러 줄 텍스트)
.setStyle(Notification.InboxStyle()...)

// 변경: ProgressStyle (진행 바 + 트래커 아이콘)
val progressStyleClass = Class.forName("android.app.Notification\$ProgressStyle")
val progressStyle = progressStyleClass.getConstructor().newInstance()
```

##### 2. `setProgressTrackerIcon()` - 버스 아이콘이 진행 바 위에서 이동!
```kotlin
val busIcon = android.graphics.drawable.Icon.createWithResource(context, R.drawable.ic_bus_large)
val setProgressTrackerIconMethod = progressStyleClass.getMethod(
    "setProgressTrackerIcon", android.graphics.drawable.Icon::class.java
)
setProgressTrackerIconMethod.invoke(progressStyle, busIcon)
```

##### 3. `setProgressSegments()` - 구간별 색상 표시
```kotlin
val segmentClass = Class.forName("android.app.Notification\$ProgressStyle\$Segment")
val segmentConstructor = segmentClass.getConstructor(Int::class.javaPrimitiveType)
val setColorMethod = segmentClass.getMethod("setColor", Int::class.javaPrimitiveType)

// 진행된 구간 (버스 색상)
val segment1 = segmentConstructor.newInstance(progress)
setColorMethod.invoke(segment1, busTypeColor)

// 남은 구간 (회색)
val segment2 = segmentConstructor.newInstance(maxMinutes - progress)
setColorMethod.invoke(segment2, 0xFFE0E0E0.toInt())

val segments = listOf(segment1, segment2)
progressStyleClass.getMethod("setProgressSegments", List::class.java)
    .invoke(progressStyle, segments)
```

##### 4. `setProgressPoints()` - 출발/도착 지점 표시
```kotlin
val pointClass = Class.forName("android.app.Notification\$ProgressStyle\$Point")
val pointConstructor = pointClass.getConstructor(Int::class.javaPrimitiveType)

// 시작점 (초록)
val startPoint = pointConstructor.newInstance(0)
pointClass.getMethod("setColor", Int::class.javaPrimitiveType)
    .invoke(startPoint, 0xFF4CAF50.toInt())

// 도착점 (주황)
val endPoint = pointConstructor.newInstance(maxMinutes)
pointClass.getMethod("setColor", Int::class.javaPrimitiveType)
    .invoke(endPoint, 0xFFFF5722.toInt())

progressStyleClass.getMethod("setProgressPoints", List::class.java)
    .invoke(progressStyle, listOf(startPoint, endPoint))
```

##### 5. 여러 버스 추적 시 subText에 요약 표시
```kotlin
val summaryText = if (activeTrackings.size > 1) {
    activeTrackings.values.drop(1).take(3).joinToString(" | ") { info ->
        "${info.busNo}: ${timeStr}"
    }
} else null
nativeBuilder.setSubText(summaryText)
```

### 참고 자료
- [Progress-centric notifications | Android Developers](https://developer.android.com/about/versions/16/features/progress-centric-notifications)
- [Create a progress-centric notification | Android Developers](https://developer.android.com/develop/ui/views/notifications/progress-centric)

### 예상 결과
```
┌─────────────────────────────────────────┐
│ 🚌  버스 알람 추적 중 (13:45:30)        │
│ 410번 (대구삼성창조캠퍼스4): 14분       │
│                                         │
│ ●━━━━━━━━━🚌━━━━━━━━━●                  │
│ 출발        ↑         도착             │
│       버스 아이콘 이동                   │
└─────────────────────────────────────────┘
```

### 로그 확인
```
✅ ProgressStyle.setProgress(16) 호출 성공
✅ ProgressStyle.setProgressTrackerIcon() 호출 성공 - 버스 아이콘 설정됨
✅ ProgressStyle.setProgressSegments() 호출 성공
✅ ProgressStyle.setProgressPoints() 호출 성공
✅ nativeBuilder.setStyle(ProgressStyle) 호출 성공
🎯 Live Update 설정 완료:
   - ProgressStyle: 사용됨
   - setProgressTrackerIcon: 버스 아이콘 (진행 바 위 이동)
   - setProgress: 16/30
   - setShortCriticalText: '14분'
   - SDK Version: 36
```

---

## 2026-01-28 (3차): 버스 트래커 아이콘 및 알람 재시작 개선

### 1. 버스 트래커 아이콘 추가

#### 새 파일: `android/app/src/main/res/drawable/ic_bus_tracker.xml`
- 72dp 크기의 파란색 버스 Vector Drawable
- Live Update 진행 바에서 이동하는 트래커 아이콘으로 사용
- 회색 상단 + 파란색 하단 + 검은색 창문 + 노란색 라이트

```xml
<vector android:width="72dp" android:height="72dp" ...>
    <!-- 버스 상단 (회색) -->
    <path android:fillColor="#D1D3D3" ... />
    <!-- 버스 하단 (파란색) -->
    <path android:fillColor="#000FE6" ... />
    <!-- 창문들 -->
    <path android:fillColor="#333E48" ... />
    <!-- 라이트 -->
    <path android:fillColor="#FFB819" ... />
</vector>
```

#### NotificationHandler.kt 수정
```kotlin
// 단일 흰색 버스 아이콘 사용
val busIcon = android.graphics.drawable.Icon.createWithResource(context, R.drawable.ic_bus_tracker)
```

### 2. 알람 재시작 방지 시간 단축

#### 문제
- 알람 해제 후 다른 버스 클릭 시 바로 알람이 생성되지 않음
- 30초간 재시작 방지 로직이 너무 김

#### 수정: `BusAlertService.kt` (라인 144)
```kotlin
// 이전: 30초간 재시작 방지
private val RESTART_PREVENTION_DURATION = 30000L

// 수정: 3초로 단축
private val RESTART_PREVENTION_DURATION = 3000L
```

#### 결과
- 알람 해제 후 3초 후에 바로 다른 버스 알람 시작 가능

---

## 2026-01-28 (4차): 홈 화면 및 즐겨찾기 화면 UI 개선

### 목표
Material 3 디자인 원칙에 따라 홈 화면과 즐겨찾기 화면의 UI를 개선하여 더 직관적이고 시각적으로 풍부한 사용자 경험 제공

### 수정된 파일

#### 1. `lib/screens/home_screen.dart`

##### 섹션 헤더 개선
아이콘과 함께 섹션 제목 표시:
```dart
Widget _buildSectionHeader({
  required String title,
  required IconData icon,
  required Color iconColor,
}) {
  return Row(
    children: [
      Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: iconColor.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: iconColor),
      ),
      const SizedBox(width: 10),
      Text(title, style: TextStyle(fontWeight: FontWeight.w700)),
    ],
  );
}
```

##### 근처 정류장 카드 개선
- 빈 상태: 로딩 인디케이터와 메시지 표시
- 선택된 정류장 하이라이트 (primaryContainer 배경, 그림자 효과)
- 각 정류장 카드에 첫 번째 버스 도착 정보 미리보기 표시
- 애니메이션 효과 (AnimatedContainer)

##### 즐겨찾기 버스 목록 개선
- 빈 상태: 그라데이션 배경 + 아이콘 + 안내 메시지
- 카드 진입 애니메이션 (TweenAnimationBuilder, staggered effect)
- 그라데이션 노선 번호 배지 + 그림자 효과
- 3분 이내 도착 버스 강조 표시 (빨간색 테두리 + 배지)
- 햅틱 피드백 (HapticFeedback.lightImpact)
- 이어폰 알람 아이콘 변경 (schedule → headphones_rounded)

#### 2. `lib/screens/favorites_screen.dart`

##### 헤더 섹션 개선
- 그라데이션 별 아이콘 배지 + 그림자 효과
- 즐겨찾기 개수 표시
- FilledButton.tonalIcon 스타일 "추가" 버튼

##### 빈 상태 디자인
- 동심원 원형 배경 + 별 아이콘
- 안내 메시지 + "버스 추가하기" 버튼

##### 즐겨찾기 카드 개선
- 2행 레이아웃: 노선/정류장 정보 + 시간/액션
- 카드 진입 애니메이션 (TweenAnimationBuilder)
- 그라데이션 노선 배지 + 그림자
- 시간 표시 컨테이너:
  - 도착 임박: errorContainer 배경
  - 운행 종료: surfaceContainerHigh 배경
  - 일반: primaryContainer 배경
- 위치 아이콘과 함께 현재 정류장 표시
- 액션 버튼 배경색 추가

##### 한글 인코딩 수정
- `'?? ?? ??'` → `'도착 정보 없음'`
- `'?? ??'` → `'운행 종료'`
- `'? ??'` → `'곧 도착'`
- `'${minutes}?'` → `'$minutes분'`

### 디자인 특징
1. **시각적 계층**: 섹션별 아이콘 헤더, 그라데이션 배지
2. **상태 피드백**: 도착 임박 강조, 빈 상태 안내
3. **애니메이션**: 카드 진입 효과, 선택 하이라이트
4. **접근성**: 햅틱 피드백, 충분한 터치 영역

---

## 2026-01-28 (5차): 즐겨찾기 UI 통일 및 기능 추가

### 목표
- 버스 정류장 상세 모달과 홈 화면 즐겨찾기 목록의 디자인 이질감 해소
- 정류장 상세 모달에 누락된 '즐겨찾기' 버튼 추가

### 수정된 파일

#### 1. `lib/widgets/unified_bus_detail_widget.dart`
- **즐겨찾기 버튼 추가**: 승차 알람 버튼 옆에 즐겨찾기 추가/해제 버튼 배치.
- **기능 구현**: `FavoriteBusStore` 및 로컬 상태(`_favoriteBuses`)를 사용하여 즐겨찾기 토글 기능 구현.
- **UI**: `FilledButton.tonalIcon` 스타일 적용하여 일관성 유지.

#### 2. `lib/screens/home_screen.dart`
- **즐겨찾기 카드 디자인 변경**:
    - 기존의 Material Card 스타일에서 정류장 상세 모달과 유사한 컴팩트 스타일로 변경.
    - 왼쪽: 단색 버스 번호 뱃지 (50x28).
    - 중앙: 도착 시간 강조 (Bold 16) + 남은 정거장 수.
    - Next 버스 정보 표시 추가.
    - 우측: 별 아이콘 및 알람 아이콘 배치.

### 결과
이제 홈 화면의 즐겨찾기 목록과 정류장 상세 화면의 리스트 디자인이 통일되어, 사용자에게 일관된 경험을 제공합니다. 정류장 상세 화면에서도 바로 즐겨찾기를 추가할 수 있습니다.

---

## 2026-01-29~30: 즐겨찾기 여백 조정 + 버스 알림/추적 리팩터링

### 목표
- 즐겨찾기 화면 좌우 여백을 홈 화면 비율로 통일
- 버스 알림 서비스의 거대 파일 분리 및 성능/안정성 개선
- 폴링/타이머 과다 사용 완화 및 안전성 강화

### 수정된 파일/주요 변경

#### UI/여백
- `lib/screens/favorites_screen.dart`
  - 리스트 좌우 패딩을 홈 화면과 맞춤 (16 기준).
  - 카드 내부 좌우 패딩 정렬.
- `lib/widgets/compact_bus_card.dart`
  - 카드 내부 좌우 패딩 조정 (즐겨찾기 전광판 라인 정렬).

#### 성능/안정성
- `lib/services/alarm_service.dart`
  - 알람 로드 주기 완화(15초마다 무조건 로드 → 2분 간격 스로틀).
- `lib/widgets/bus_card.dart`, `lib/widgets/compact_bus_card.dart`
  - 카드별 주기 타이머 폴링 제거(중앙 갱신 로직에 의존).
- `lib/screens/map_screen.dart`
  - `Future.delayed` 콜백에 `mounted` 체크 추가.

#### Android 서비스 리팩터링
- `android/app/src/main/kotlin/com/example/daegu_bus_app/services/BusAlertService.kt`
  - 대형 로직을 모듈로 분리하고 서비스는 조정/위임 역할로 축소.
- 신규 추가
  - `BusAlertTtsController.kt`: TTS/오디오 포커스/헤드셋 체크 분리
  - `BusAlertNotificationUpdater.kt`: 알림 생성/포그라운드 갱신 분리
  - `BusAlertTrackingManager.kt`: 추적 루프/폴링/오류 처리 분리
  - `BusAlertParsers.kt`: JSON 파서 분리
  - `TrackingInfo.kt`: 추적 데이터 모델 분리
- `android/app/src/main/kotlin/com/example/daegu_bus_app/utils/NotificationHandler.kt`
  - `TrackingInfo` 타입 참조 갱신
- `android/app/src/main/kotlin/com/example/daegu_bus_app/utils/RouteTracker.kt`
  - `TrackingInfo` 타입 참조 갱신

### 빌드 확인
- `flutter build apk` 성공 (WSL 환경 기준).

### 주의/보류 사항 (추가 작업 필요)
1. `RouteTracker.kt` 파서 통합 완료  
   → 공용 파서(`BusAlertParsers.kt`) 사용으로 정리됨.
2. `android/local.properties`의 `flutter.sdk` 경로 변경은 로컬 환경용  
   → 커밋하지 말고, 팀 표준 경로/README 안내 필요.
3. 알림/추적 분리 후 기능 회귀 테스트 필요  
   - 자동 알람/이어폰 전용 모드/포그라운드 알림 갱신 시나리오.

---

## 2026-01-30: 초기 검은 화면 및 권한 플로우 개선

### 목표
- 앱 초기 실행 시 권한 요청으로 인해 발생하는 검은 화면 해소
- 일반적인 앱 권한 온보딩 플로우 제공

### 수정된 파일
- `lib/main.dart`
  - 앱 시작 시 권한 요청을 제거하고 온보딩 화면으로 이동.
- `lib/screens/startup_screen.dart` (신규)
  - 권한 안내 화면 UI 추가
  - 위치/알림 권한 요청 버튼 제공
  - 권한 허용 시 홈 화면으로 전환

### 추가 작업 필요
1. 권한 거부 시 제한 모드 UX(예: 지도 탭 제한) 안내 강화
