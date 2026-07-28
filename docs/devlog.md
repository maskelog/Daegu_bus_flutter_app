# 대구 버스 앱 개발 일지 (아카이브)

> 2026-07-03: AGENTS.md와 GEMINI.md에 쌓여 있던 개발 기록을 이 파일로 이전.
> 2026-07-05: 두 기록에 중복 수록되어 있던 2026-01-28 1~4차 섹션(구 AGENTS.md 쪽)을 제거.
> 폐기된 접근 방식의 엔트리에는 `⚠️ 폐기됨` 표시를 추가.
>
> 이 파일은 시간순 append-only 로그다. "지금 무엇이 참인가"는 [docs/topics/](topics/)의
> 주제별 문서를 먼저 볼 것 (목록: [docs/index.md](index.md)).

---

<!-- ===== 이하: 구 GEMINI.md 전문 ===== -->

# 대구 버스 앱 개발 기록

## 2026-01-28: Android 16 Live Update 알림 구현

> ⚠️ **폐기됨 (2026-02-16)**: 이 엔트리의 Reflection + `Notification.Builder` 접근은
> `NotificationCompat.Builder` 전환으로 전면 교체됨. 현행 구현은
> [topics/live-update-notification.md](topics/live-update-notification.md) 참조.

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

> ⚠️ **폐기됨 (2026-02-16)**: Reflection 기반 네이티브 `Notification.ProgressStyle`은
> `NotificationCompat.ProgressStyle` 직접 호출로 교체됨.
> [topics/live-update-notification.md](topics/live-update-notification.md) 참조.

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

## 2026-02-05: 홈 화면과 노티피케이션 버스 정보 동기화 문제

### 🚨 문제 상황
홈 스크린에 표시되는 버스 도착 시간과 알림(Notification)에 표시되는 버스 도착 시간이 서로 다름
- **홈 스크린**: Flutter에서 실시간 API로 가져온 최신 데이터
- **노티피케이션**: Android Native (BusAlertService.kt)에서 별도로 관리하는 데이터

### 🔍 원인 분석
1. **데이터 소스 분리**
   - Flutter: `BusApiService` (Dart)로 버스 정보 fetch
   - Native: `BusApiService` (Kotlin)로 버스 정보 fetch
   - 두 서비스가 독립적으로 API 호출 → **동기화 안 됨**

2. **업데이트 타이밍 불일치**
   - Flutter: 화면이 보일 때마다 refresh
   - Native: 백그라운드 주기적 업데이트 (독립 타이머)
   - **같은 시점에 다른 데이터 표시 가능**

3. **캐싱 전략 차이**
   - Flutter: UI 즉시 업데이트
   - Native: `TrackingInfo.lastBusInfo` 캐시 사용
   - **캐시 불일치로 구버전 데이터 표시**

### 🎯 해결 방안

#### 방안 1: Flutter → Native 실시간 업데이트 (권장)
Flutter에서 버스 정보를 가져올 때마다 Native로 업데이트 전송

**장점:**
- Flutter가 단일 진실 공급원(Single Source of Truth)
- Native는 최신 정보만 표시
- Native API 호출 횟수 감소 (배터리 절약)

**구현 방법:**
```dart
// lib/screens/home_screen.dart 또는 bus_info 갱신 지점
Future<void> _refreshBusArrivals() async {
  final arrivals = await busApiService.getBusArrivalInfo(...);
  
  // 각 버스 정보를 Native로 전송
  for (var arrival in arrivals) {
    await _methodChannel.invokeMethod('updateBusInfo', {
      'routeId': arrival.routeId,
      'busNo': arrival.routeNo,
      'stationName': stationName,
      'remainingMinutes': arrival.remainingMinutes,
      'currentStation': arrival.currentStation,
      'estimatedTime': arrival.estimatedTime,
      'isLowFloor': arrival.isLowFloor,
    });
  }
}
```

```kotlin
// BusAlertService.kt
fun updateBusInfoFromFlutter(
    routeId: String,
    busNo: String,
    stationName: String,
    remainingMinutes: Int,
    currentStation: String?,
    estimatedTime: String?,
    isLowFloor: Boolean
) {
    val trackingInfo = activeTrackings[routeId] ?: return
    
    // BusInfo 업데이트
    trackingInfo.lastBusInfo = BusInfo(
        currentStation = currentStation ?: "정보 없음",
        estimatedTime = estimatedTime ?: "${remainingMinutes}분",
        remainingStops = "0",
        busNumber = busNo,
        isLowFloor = isLowFloor
    )
    
    // 노티피케이션 즉시 갱신
    updateForegroundNotification()
    
    Log.d(TAG, "✅ Flutter에서 버스 정보 업데이트: $busNo, $remainingMinutes분")
}
```

#### 방안 2: 공통 데이터 소스 사용
Native API만 사용하고 Flutter는 Native에서 데이터 가져오기

**장점:**
- 단일 API 호출로 일관성 보장
- 데이터 흐름이 단순함

**단점:**
- Flutter UI가 Native에 의존
- 화면 갱신이 느릴 수 있음

#### 방안 3: 이벤트 기반 동기화
Native가 업데이트하면 Flutter에 이벤트 전송, Flutter가 업데이트하면 Native에 이벤트 전송

**장점:**
- 양방향 동기화
- 실시간성 보장

**단점:**
- 구현 복잡도 증가
- 순환 업데이트 위험

### ✅ 권장 솔루션: 방안 1 구현
1. **Flutter 측 수정**
   - `bus_api_service.dart`에서 버스 정보 fetch 후 Native로 전송
   - `home_screen.dart`, `favorites_screen.dart` 등 버스 정보 표시 화면 모두 적용

2. **Native 측 수정**
   - `MainActivity.kt`에 `updateBusInfo` 메서드 추가
   - `BusAlertService.kt`에 `updateBusInfoFromFlutter()` 함수 추가
   - 받은 데이터로 `activeTrackings[routeId].lastBusInfo` 업데이트
   - 즉시 `updateForegroundNotification()` 호출

3. **나우바(Now Bar) 지원**
   - Android 16의 Now Bar는 Live Update 알림을 우선 표시
   - `setRequestPromotedOngoing(true)` 이미 설정됨
   - 최신 버스 정보만 제공하면 Now Bar에 자동 반영

### 📝 구현 체크리스트
- [x] Flutter `BusApiService`에 Native 업데이트 로직 추가
- [x] `MainActivity.kt`에 `updateBusInfo` 메서드 채널 핸들러 추가
- [x] `BusAlertService.kt`에 `updateBusInfoFromFlutter()` 구현
- [ ] 홈 스크린 버스 정보 갱신 시 Native 호출 추가 (getBusArrivalByRouteId에서 자동 호출)
- [ ] 즐겨찾기 화면 버스 정보 갱신 시 Native 호출 추가 (getBusArrivalByRouteId 사용 시 자동 호출)
- [ ] 자동 알람 갱신 시 Native 호출 추가
- [ ] 테스트: 홈 화면과 노티피케이션 시간 일치 확인
- [ ] 테스트: Now Bar 표시 확인 (Android 16+)

### 🎯 기대 효과
1. **데이터 일관성**: 모든 화면에서 동일한 버스 정보 표시
2. **사용자 신뢰**: 홈 화면과 알림이 항상 일치
3. **Now Bar 지원**: Android 16+에서 최신 정보 실시간 표시
4. **배터리 절약**: Native API 호출 감소 (Flutter가 대신 호출)

---

## 2026-02-05 (2차): Now Bar 상태 칩 카운트다운 수정

> ⚠️ **부분 폐기 (2026-02-16)**: `setWhen(미래 시간)` 원칙과 Now Bar 작동 조건 정리는 여전히 유효하나,
> Reflection 기반 구현 코드는 `NotificationCompat.Builder` 직접 호출로 교체됨.

### 문제
- Android 16 Now Bar에서 상태 칩이 표시되지 않음
- 버스 도착 시간 카운트다운이 작동하지 않음

### 원인
1. **setWhen() 설정 오류**: 현재 시간으로 설정되어 카운트다운 불가
   - 공식 문서: "when 시간이 현재 시간보다 2분 이상 후여야 카운트다운 표시"
2. **API 호출 순서**: `setRequestPromotedOngoing`을 ProgressStyle 설정 후에 호출

### 해결 방법

#### 1. `setWhen()` 수정 - 버스 도착 예정 시간으로 설정
```kotlin
// 수정 전
.setWhen(System.currentTimeMillis())

// 수정 후
val remainingMinutes = busInfo?.getRemainingMinutes() ?: 0
val arrivalTimeMillis = if (remainingMinutes > 0) {
    System.currentTimeMillis() + (remainingMinutes * 60 * 1000L)
} else {
    System.currentTimeMillis() + 60000L // 1분 후 (곧 도착)
}
nativeBuilder.setWhen(arrivalTimeMillis)
```

#### 2. API 호출 순서 최적화
```kotlin
// 올바른 순서:
// 1. setWhen() 설정
// 2. setRequestPromotedOngoing(true)
// 3. setShortCriticalText()
// 4. ProgressStyle 설정

nativeBuilder.setWhen(arrivalTimeMillis)  // ①

setRequestPromotedOngoingMethod.invoke(nativeBuilder, true)  // ②
setShortCriticalTextMethod.invoke(nativeBuilder, chipText)   // ③

// ProgressStyle 설정  // ④
val progressStyle = progressStyleClass.getConstructor().newInstance()
...
```

### Now Bar 작동 조건 (Android 16+)
✅ **필수 조건**:
1. `setOngoing(true)` - 진행 중인 알림
2. `setRequestPromotedOngoing(true)` - Live Update 승격 요청
3. `setWhen(미래 시간)` - 현재 시간보다 2분 이상 후
4. `setShortCriticalText()` - 상태 칩 텍스트
5. `setSmallIcon()` - 상태 칩 아이콘 (필수)
6. `setCategory(CATEGORY_PROGRESS)` - 진행 중 카테고리

📊 **상태 칩 표시 규칙**:
- 7자 미만: 전체 텍스트 표시
- 텍스트 절반 미만 표시 가능: 아이콘만 표시
- 텍스트 절반 이상 표시 가능: 최대한 많은 텍스트 표시
- 최대 너비: 96dp

⏰ **카운트다운 표시 규칙**:
- `when` 시간이 현재보다 2분 이상 후: "5분" 형식으로 표시
- `when` 시간이 과거: 텍스트 표시 안 됨
- `setUsesChronometer(true)` + `setChronometerCountdown(true)`: 타이머 표시

### 참고 자료
- [실시간 업데이트 알림 만들기 | Android Developers](https://developer.android.com/develop/ui/views/notifications/live-update?hl=ko)

---

## 2026-02-05 (3차): Live Update 알림 승격 가능성 확인 및 설정 바로가기 추가

> ⚠️ **폐기됨 (2026-02-16)**: 여기서 사용한 Settings 인텐트
> `ACTION_MANAGE_APP_PROMOTED_NOTIFICATIONS`는 잘못된 값 —
> `Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS` + `EXTRA_APP_PACKAGE`로 교체됨.
> Reflection 호출도 직접 API 호출로 교체됨.

### 목표
- Android 16 Live Update 알림의 승격 가능 여부를 확인하고 로깅하여 디버깅 정보 강화
- 사용자가 앱의 Live Update 기능을 비활성화한 경우, 설정으로 바로 이동할 수 있는 액션 추가

### 수정된 파일
#### `android/app/src/main/kotlin/com/example/daegu_bus_app/utils/NotificationHandler.kt`

##### 1. Live Update 승격 가능성 로깅 추가
- `NotificationManager.canPostPromotedNotifications()`: 앱이 승격 알림을 게시할 수 있는지 (사용자 설정 여부) 확인하여 로그에 출력
- `Notification.hasPromotableCharacteristics()`: 생성된 알림 객체가 승격될 수 있는 특성을 가졌는지 확인하여 로그에 출력

```kotlin
// ... (setShortCriticalText 호출 후)
                    // --- Live Update Promotable Characteristics Checks ---
                    val notificationManager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    val canPostPromoted = try {
                        val method = notificationManager.javaClass.getMethod("canPostPromotedNotifications")
                        method.invoke(notificationManager) as Boolean
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ canPostPromotedNotifications 호출 실패: ${e.message}")
                        false
                    }
                    Log.d(TAG, "📋 NotificationManager.canPostPromotedNotifications(): $canPostPromoted")
// ... (builtNotification 생성 후)
                val builtNotification = nativeBuilder.build()
                val hasPromotableCharacteristics = try {
                    val method = builtNotification.javaClass.getMethod("hasPromotableCharacteristics")
                    method.invoke(builtNotification) as Boolean
                } catch (e: Exception) {
                    Log.e(TAG, "❌ hasPromotableCharacteristics 호출 실패: ${e.message}")
                    false
                }
                Log.d(TAG, "📋 builtNotification.hasPromotableCharacteristics(): $hasPromotableCharacteristics")
```

##### 2. 승격 불가 시 '알림 설정' 액션 추가
- `NotificationManager.canPostPromotedNotifications()` 결과가 `false`일 경우, 알림에 "알림 설정" 액션 버튼을 추가
- 이 버튼 클릭 시 `Settings.ACTION_MANAGE_APP_PROMOTED_NOTIFICATIONS` 인텐트를 통해 앱의 프로모션 알림 설정 화면으로 사용자를 바로 안내

```kotlin
// ... (자동알람 중지 액션 추가 후)
                // Add action to manage promoted notifications if they can't be posted
                if (!canPostPromoted) {
                    try {
                        val manageSettingsIntent = Intent(android.provider.Settings.ACTION_MANAGE_APP_PROMOTED_NOTIFICATIONS).apply {
                            data = android.net.Uri.fromParts("package", context.packageName, null)
                        }
                        val manageSettingsPendingIntent = PendingIntent.getActivity(
                            context,
                            9997, // Unique request code
                            manageSettingsIntent,
                            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                        )
                        nativeBuilder.addAction(Notification.Action.Builder(
                            android.graphics.drawable.Icon.createWithResource(context, R.drawable.ic_cancel), // Temporary icon
                            "알림 설정", // "Notification Settings"
                            manageSettingsPendingIntent
                        ).build())
                        Log.d(TAG, "⚙️ '알림 설정' 액션 추가됨 (Promoted Notifications 비활성화됨)")
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ '알림 설정' 액션 추가 실패: ${e.message}")
                    }
                }
```

#### 4. Samsung One UI 7 및 Android 16 Live Updates 관련 추가 분석

- **삼성 One UI 7 Live Notifications (나우 바)의 제한**: 삼성 One UI 7에 도입된 Live Notifications 및 나우 바 기능은 현재 삼성 화이트리스트 앱 또는 시스템 기능에만 허용됩니다. 일반 앱은 해당 기능을 직접 활용할 수 없습니다.
- **미디어 재생 앱 예외**: AndroidX Media3의 `MediaSessionService`를 사용하는 미디어 재생 앱은 Live Notifications 및 나우 바를 자동으로 지원합니다.
- **Android 16과의 통합**: 삼성은 Android 16의 Live Updates API가 출시되면, 이러한 기능이 플랫폼의 표준 API를 통해 자동으로 지원될 것이라고 언급했습니다. 이는 삼성 고유의 `meta-data` 및 `extras` 설정이 향후에는 필요 없거나, Android 16 기본 API에 통합될 것임을 시사합니다.
- **현재 구현의 정당성**: `NotificationHandler.kt`에서 Android 16의 `setRequestPromotedOngoing()`, `setShortCriticalText()`, `Notification.ProgressStyle` 등 표준 Live Updates API를 리플렉션을 통해 사용하는 현재의 접근 방식은 미래의 Android 표준에 부합하며, Android 16 정식 출시 시 자동으로 삼성 One UI에서도 해당 기능을 활용할 수 있게 될 것입니다. 따라서 현재로서는 삼성 One UI 7에 특화된 별도 구현은 불필요합니다.

---

## 2026-02-05 (4차): Samsung One UI 7 Live Notifications 및 Now Bar 지원 추가

> ⚠️ **부분 폐기 (2026-02-16)**: Samsung extras Bundle 자체는 유지되나,
> `setExtras()`(내부 extras 덮어쓰기 위험)는 `addExtras()`(병합)로 교체됨.

### 목표
- Samsung One UI 7의 Live Notifications 및 Now Bar 지원 추가
- Android 16 표준 API와 Samsung 전용 API를 모두 구현하여 최대 호환성 확보

### 참고 자료
- [Live Notifications and Now Bar in Samsung One UI 7: As developer](https://akexorcist.dev/live-notifications-and-now-bar-in-samsung-one-ui-7-as-developer-en/)

### 구현 내용

#### 1. AndroidManifest.xml - Samsung 지원 선언
```xml
<!-- Samsung One UI 7 Live Notifications and Now Bar 지원 -->
<meta-data android:name="com.samsung.android.support.ongoing_activity" android:value="true" />
```

#### 2. NotificationHandler.kt - Samsung extras Bundle 추가

Samsung One UI 7은 알림에 특별한 extras Bundle을 요구합니다:

```kotlin
val samsungExtras = android.os.Bundle().apply {
    // 필수: Samsung Live Notifications 활성화
    putInt("android.ongoingActivityNoti.style", 1)
    
    // Primary Info (주요 텍스트)
    putString("android.ongoingActivityNoti.primaryInfo", busNo)
    
    // Secondary Info (부가 정보)
    putString("android.ongoingActivityNoti.secondaryInfo", "$stationName: $timeStr")
    
    // Chip 설정 (상태 바 상단 칩)
    putString("android.ongoingActivityNoti.chipExpandedText", timeStr)
    putInt("android.ongoingActivityNoti.chipBgColor", busTypeColor)
    val chipIcon = android.graphics.drawable.Icon.createWithResource(context, R.drawable.ic_bus_notification)
    putParcelable("android.ongoingActivityNoti.chipIcon", chipIcon)
    
    // Progress 정보
    putInt("android.ongoingActivityNoti.progress", progress)
    putInt("android.ongoingActivityNoti.progressMax", maxMinutes)
    
    // Progress 트래커 아이콘
    val trackerIcon = android.graphics.drawable.Icon.createWithResource(context, R.drawable.ic_bus_tracker)
    putParcelable("android.ongoingActivityNoti.progressSegments.icon", trackerIcon)
    putInt("android.ongoingActivityNoti.progressSegments.progressColor", busTypeColor)
    
    // Now Bar 설정 (잠금 화면)
    putString("android.ongoingActivityNoti.nowbarPrimaryInfo", busNo)
    putString("android.ongoingActivityNoti.nowbarSecondaryInfo", timeStr)
    
    // Action 버튼 표시 설정
    putInt("android.ongoingActivityNoti.actionType", 1)
    putInt("android.ongoingActivityNoti.actionPrimarySet", 0)
}

// Notification Builder에 extras 적용
nativeBuilder.setExtras(samsungExtras)
```

### Samsung One UI 7 vs Android 16 Live Updates

#### Samsung One UI 7 (현재)
- **화이트리스트 앱만**: 삼성이 승인한 앱만 사용 가능
- **전용 API**: `android.ongoingActivityNoti.*` extras 사용
- **meta-data 필수**: AndroidManifest에 선언 필요
- **지원 기기**: Samsung Galaxy S25 등 (One UI 7)

#### Android 16 Live Updates (미래)
- **모든 앱 지원**: 표준 플랫폼 API
- **표준 API**: `setRequestPromotedOngoing()`, `setShortCriticalText()`, `ProgressStyle`
- **자동 지원**: 별도 설정 불필요
- **지원 기기**: Android 16+ 모든 기기 (출시 예정)

### 통합 전략

현재 구현은 **두 가지 방식을 모두 지원**하여 최대 호환성을 확보합니다:

1. **Samsung One UI 7 사용자**: extras Bundle을 통해 Live Notifications 지원
2. **Android 16+ 사용자**: 표준 Live Updates API 사용
3. **Samsung + Android 16**: One UI 8에서 표준 API로 자동 통합 예정

```kotlin
// 1. Samsung One UI 7 방식
val samsungExtras = Bundle().apply { /* ... */ }
nativeBuilder.setExtras(samsungExtras)

// 2. Android 16 표준 방식
nativeBuilder.setWhen(arrivalTimeMillis)
setRequestPromotedOngoingMethod.invoke(nativeBuilder, true)
setShortCriticalTextMethod.invoke(nativeBuilder, chipText)

// ProgressStyle 설정
val progressStyle = progressStyleClass.getConstructor().newInstance()
// ...
```

### 주요 차이점

| 기능 | Samsung One UI 7 | Android 16 |
|------|------------------|------------|
| **활성화 방식** | extras Bundle | Reflection API |
| **Progress** | `android.ongoingActivityNoti.progress*` | `Notification.ProgressStyle` |
| **트래커** | `progressSegments.icon` | `setProgressTrackerIcon()` |
| **상태 칩** | `chipExpandedText` | `setShortCriticalText()` |
| **Now Bar** | `nowbar*` extras | 자동 (같은 API) |

### 제한 사항

⚠️ **Samsung One UI 7 화이트리스트 제한**:
- 일반 앱은 현재 Samsung Live Notifications 사용 불가
- 삼성 내장 앱 또는 승인된 앱만 사용 가능
- **미디어 재생 앱 예외**: `MediaSessionService` 사용 시 자동 지원

✅ **Android 16 출시 시**:
- One UI 8부터 표준 API로 자동 전환 예정
- 별도의 Samsung 전용 코드 불필요
- 현재 구현한 Android 16 API가 그대로 작동

### 테스트 방법

#### Samsung One UI 7 기기:
1. Galaxy S25 등 One UI 7 기기 준비
2. 앱 설치 후 버스 알림 시작
3. 알림 드로어에서 Live Notifications 섹션 확인
4. 상태 바 상단 칩 확인
5. 잠금 화면에서 Now Bar 확인

#### Android 16+ 기기:
1. Android 16 베타/정식 기기 준비
2. 앱 설치 후 버스 알림 시작
3. Live Updates 알림 확인
4. 상태 칩 카운트다운 확인

### 로그 확인
```
📱 Samsung One UI 7 extras Bundle 생성 완료
📱 Samsung One UI 7 extras 적용 완료
⏰ setWhen 설정: 5분 후 (...)
✅ setRequestPromotedOngoing(true) 호출 성공
✅ setShortCriticalText('5분') 호출 성공
🎯 Live Update 설정 완료
```

---

## 2026-02-16: 🚨 Live Update 상태 칩 근본 수정 — NotificationCompat.Builder 전환 (핵심!)

### 🚨 문제 상황
Android 16 (API 36, Samsung Galaxy S25 Ultra / One UI 8 Beta)에서 Live Update 상태 칩의 **텍스트가 표시되지 않음**.
- 버스 아이콘은 상태 바에 보이지만, 칩 텍스트("5분" 등)가 출력 안 됨
- `hasPromotableCharacteristics()`: true 반환
- `canPostPromotedNotifications()`: true 반환
- 그런데도 상태 칩 텍스트 미표시

### 🔍 근본 원인 발견

Google 공식 샘플 (`platform-samples/samples/user-interface/live-updates`)을 분석하여 **4가지 핵심 차이점** 발견:

| 항목 | Google 공식 샘플 (작동 ✅) | 기존 코드 (미작동 ❌) |
|------|--------------------------|---------------------|
| **Builder** | `NotificationCompat.Builder` | `Notification.Builder` (네이티브) |
| **ProgressStyle** | `NotificationCompat.ProgressStyle` | `Notification.ProgressStyle` (네이티브) |
| **setShortCriticalText** | `NotificationCompat.Builder` 직접 호출 | Reflection 간접 호출 |
| **setRequestPromotedOngoing** | `NotificationCompat.Builder` 직접 호출 | Reflection 간접 호출 |
| **TrackerIcon** | `IconCompat` | `android.graphics.drawable.Icon` |
| **Settings Intent** | `ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS` | `ACTION_MANAGE_APP_PROMOTED_NOTIFICATIONS` (잘못된 값) |
| **`androidx.core:core-ktx`** | **`1.17.0`** | **`1.15.0`** ← **핵심!** |

> **결정적 원인**: `androidx.core:core-ktx:1.15.0`에는 `NotificationCompat.ProgressStyle`, `setShortCriticalText()`, `setRequestPromotedOngoing()`가 **존재하지 않음**. `1.17.0`부터 추가됨.
> 이 때문에 네이티브 `Notification.Builder`와 Reflection을 사용했지만, `NotificationCompat`의 호환성 레이어를 우회하여 Live Update 승격이 제대로 처리되지 않았음.

### ✅ 수정 내역

#### 1. 의존성 업그레이드 (3개 파일)

##### `android/gradle/wrapper/gradle-wrapper.properties`
```diff
-distributionUrl=https\://services.gradle.org/distributions/gradle-8.9-all.zip
+distributionUrl=https\://services.gradle.org/distributions/gradle-8.11.1-all.zip
```

##### `android/settings.gradle.kts`
```diff
-id("com.android.application") version "8.7.0" apply false
+id("com.android.application") version "8.9.1" apply false
```

##### `android/app/build.gradle`
```diff
-implementation 'androidx.core:core-ktx:1.15.0'
+implementation 'androidx.core:core-ktx:1.17.0'
```

**의존성 체인**: `core-ktx:1.17.0` → AGP `8.9.1` 필요 → Gradle `8.11.1` 필요

#### 2. NotificationHandler.kt — 알림 빌더 전면 교체

##### 기존 (Notification.Builder + Reflection) — 제거됨
```kotlin
// ❌ 네이티브 빌더 사용 (NotificationCompat 호환성 레이어 우회)
val nativeBuilder = Notification.Builder(context, CHANNEL_ID_ONGOING)
    .setOngoing(true)
    // ...

// ❌ Reflection으로 setRequestPromotedOngoing 호출
val method = nativeBuilder.javaClass.getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType)
method.invoke(nativeBuilder, true)

// ❌ Reflection으로 setShortCriticalText 호출
val method2 = nativeBuilder.javaClass.getMethod("setShortCriticalText", CharSequence::class.java)
method2.invoke(nativeBuilder, chipText)

// ❌ 네이티브 ProgressStyle
val progressStyle = Notification.ProgressStyle()
nativeBuilder.setStyle(progressStyle)

// ❌ 플래그 수동 조작
builtNotification.flags = builtNotification.flags or liveUpdateFlags
```

##### 변경 후 (NotificationCompat.Builder + 직접 API 호출) — Google 공식 패턴
```kotlin
// ✅ NotificationCompat.Builder 사용 (호환성 레이어 활용)
val liveBuilder = NotificationCompat.Builder(context, CHANNEL_ID_ONGOING)
    .setSmallIcon(R.drawable.ic_bus_notification)
    .setContentTitle(title)
    .setContentText(contentText)
    .setOngoing(true)
    .setRequestPromotedOngoing(true)       // ← 직접 호출!
    .setShortCriticalText(chipText)         // ← 직접 호출!
    .setCategory(Notification.CATEGORY_PROGRESS)
    .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)

// ✅ NotificationCompat.ProgressStyle 사용
val progressStyle = NotificationCompat.ProgressStyle()
    .setProgress(progress)
    .setProgressTrackerIcon(
        IconCompat.createWithResource(context, R.drawable.ic_bus_tracker) // IconCompat!
    )
    .setProgressSegments(segments)
    .setProgressPoints(points)

liveBuilder.setStyle(progressStyle)

// ✅ 카운트다운 설정
liveBuilder.setWhen(arrivalTimeMillis)
liveBuilder.setUsesChronometer(true)
liveBuilder.setChronometerCountDown(true)

// ✅ 최종 빌드 (1회) — 플래그 수동 조작 없음
val builtNotification = liveBuilder.build()
```

##### Samsung One UI extras 변경
```diff
-// setExtras — 기존 extras 전체 교체 (NotificationCompat이 설정한 내부 extras 덮어쓰기 위험!)
-nativeBuilder.setExtras(samsungExtras)
+// addExtras — 기존 extras에 병합 (NotificationCompat 내부 extras 보존)
+liveBuilder.addExtras(samsungExtras)
```

##### Settings Intent 수정
```diff
-val intent = Intent("android.settings.MANAGE_APP_PROMOTED_NOTIFICATIONS")
-    .apply { data = Uri.fromParts("package", context.packageName, null) }
+val intent = Intent(Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS)
+    .apply { putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName) }
```

### 🎓 핵심 교훈

1. **`NotificationCompat.Builder`를 사용해야 하는 이유**: 네이티브 `Notification.Builder`를 직접 사용하면 AndroidX의 호환성 레이어를 우회하여, Live Update 승격 정보가 시스템에 올바르게 전달되지 않음
2. **Reflection은 해결책이 아니다**: `androidx.core:core-ktx` 버전을 올려서 직접 API 호출이 가능한 상태로 만드는 것이 정답
3. **의존성 버전이 기능 가용성을 결정**: `1.15.0` vs `1.17.0`의 차이가 전체 기능 작동 여부를 결정
4. **`setExtras()` vs `addExtras()`**: `setExtras()`는 NotificationCompat이 내부적으로 설정한 extras를 덮어쓸 수 있어 위험. 반드시 `addExtras()` 사용

### 📋 의존성 버전 요약 (2026-02-16 기준)

| 항목 | 이전 버전 | 변경 후 |
|------|----------|---------|
| `androidx.core:core-ktx` | 1.15.0 | **1.17.0** |
| Android Gradle Plugin | 8.7.0 | **8.9.1** |
| Gradle | 8.9 | **8.11.1** |
| `compileSdk` / `targetSdk` | 36 | 36 (변경 없음) |
| Kotlin | 2.1.0 | 2.1.0 (변경 없음) |

### 참고 자료
- [Google platform-samples / live-updates](https://github.com/android/platform-samples/tree/main/samples/user-interface/live-updates/src/main)
- [NotificationCompat.ProgressStyle API](https://developer.android.com/reference/androidx/core/app/NotificationCompat.ProgressStyle)
- [실시간 업데이트 알림 만들기 | Android Developers](https://developer.android.com/develop/ui/views/notifications/progress-centric)

---

## 2026-02-20: 출퇴근 알람 TTS 및 진동 로직 개선

### 목표
자동알람의 출근(스피커 강제)/퇴근(이어폰 전용) 구분에 따라 TTS 발화 및 진동을 정확하게 분기 처리.

### 수정된 파일
1. `android/app/src/main/kotlin/com/example/daegu_bus_app/services/BusAlertService.kt`
2. `android/app/src/main/kotlin/com/example/daegu_bus_app/services/BusAlertTtsController.kt`
3. `android/app/src/main/kotlin/com/example/daegu_bus_app/services/TTSService.kt`

### 수정 내용
- 퇴근 알람(isCommuteAlarm == false)일 때 이어폰이 연결되지 않은 경우, TTS 발화를 건너뛰고 500ms(0.5초) 동안 진동 발생.
- 기존 TTS 자동알람에서 무조건 스피커가 강제되던 로직을 지우고, `autoAlarmForceSpeaker` 및 `autoAlarmForceEarphone` 인자를 추가하여 퇴근 알람 시 `STREAM_MUSIC`(이어폰 스트림)을 우선 사용하도록 교정.
- `BusAlertTtsController`를 거치는 `startTtsServiceSpeak`에서 `isAutoAlarm` 플래그를 정상적으로 `TTSService`에 전달하도록 인텐트 옵션 누락 수정.

---

## 2026-02-20: 자동 알람 CRUD 구성 및 공휴일 제외 로직 연동

### 목표
자동 알람 일정 등록, 수정, 삭제(CRUD) 기능에서 공휴일 제외 로직(`excludeHolidays`)이 정상 동작하도록 `AutoAlarm.getNextAlarmTime()` 및 서비스 연동 구현.

### 수정된 파일
1. `lib/models/auto_alarm.dart`
2. `lib/services/alarm_service.dart`
3. `lib/services/alarm/auto_alarm_engine.dart`
4. `lib/services/alarm/holiday_service.dart`
5. `lib/services/alarm/alarm_facade.dart`

### 수정 내용
- `HolidayService`에 메모리 캐싱 로직 추가 (`_cache`)를 통해 불필요한 공공데이터 포털 API 반복 호출 방지.
- `AutoAlarm.getNextAlarmTime({List<DateTime>? holidays})` 로 매개변수를 추가하여 공휴일이 전달될 경우 `excludeHolidays` 옵션에 따라 제외한 후 다음 알람 일자를 반환하도록 구현.
- `AlamFacade`에서 `HolidayService`의 `fetchHolidays` 레퍼런스를 `AutoAlarmEngine` 생성자로 전달해 분리된 모듈에서도 휴일 조회가 가능하도록 조치.
- `AutoAlarmEngine` 및 `AlarmService`에서 `getNextAlarmTime()`을 호출하기 전 현재 달과 다음 달(2개월치)의 공휴일을 `getHolidays()`로 로드한 뒤 매개변수로 전달 구현.
- AlarmScreen의 `_saveAutoAlarms()` 등에서 정상적으로 SharedPreferences를 통해 전체 CRUD 파이프라인이 구동됨을 검증 완료 (수동 중지 플래그 및 캐싱 정상 적용).

## 2026-02-20 (2차): 기능 강화 - 나만의 알람 예외 날짜 (커스텀 휴일) 설정 추가

### 목표
자주 변경되지 않는 '나만의 휴일(연차 등 특정 날짜)'을 설정 화면에서 미리 추가해두면, 자동 알람 계산 시 해당 날짜에 알람이 울리지 않도록 예외 처리.

### 수정된 파일
1. `lib/services/settings_service.dart`
2. `lib/screens/settings_screen.dart`
3. `lib/services/alarm/auto_alarm_engine.dart`
4. `lib/services/alarm_service.dart`

### 수정 내용
- `SettingsService` 내에 커스텀 예외 날짜 목록(`customExcludeDates`)을 추가하고 `SharedPreferences`를 이용해 영구 저장.
- 기존 공휴일 API의 `_getHolidays()` 호출 이후에 이 `customExcludeDates` 값을 함께 가져와 `allHolidays` 리스트에 `...customExcludeDates` 형태로 결합하여 반환하도록 조치.
- 변경된 일정이 `AutoAlarm.getNextAlarmTime()`에서 공휴일(예외 리스트)로 동일하게 처리되어 해당 날짜를 스킵.
- `SettingsScreen`에 `_buildCustomExcludeDateSelector` 메뉴 및 `_CustomExcludeDatesScreen` UI 추가하여 사용자가 "+" 플로팅 버튼을 통해 특정 날짜를 캘린더 피커(`showDatePicker`)로 직관적으로 선택하고 삭제할 수 있는 기능 추가.


---

<!-- ===== 이하: 구 AGENTS.md에서 이전한 기록 (구 GEMINI.md와 중복된 2026-01-28 1~4차 섹션은 2026-07-05에 삭제) ===== -->

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

1. (완료) 권한 거부 시 제한 모드 UX(지도 탭 제한) 적용

---

## 2026-01-29: 지도 탭 제한 모드 추가

### 목표

- 위치 권한 거부 시 지도 탭을 제한 모드로 표시
- 권한 요청/설정 이동 동선 제공

### 수정된 파일

- `lib/screens/home_screen.dart`
  - 지도 탭에서 권한 상태에 따라 제한 모드 화면 표시
  - 권한 허용/설정 이동 버튼 제공
  - 지도 탭 접근 시 권한 상태 체크 로직 추가

---

## 2026-03-15: Android 16 Live Update "실시간 정보" 토글 미표시 문제 해결

### 문제

- Google 공식 Live Updates 샘플 앱을 설치하면 설정 > 앱 > 알림에 "실시간 정보(Live Updates)" 토글이 표시됨
- 대구버스 앱에서는 동일한 설정이 표시되지 않아 `setShortCriticalText`로 상태 칩 표시 및 잠금화면 Live Update가 작동하지 않음

### 원인 분석

#### Google 샘플 앱과의 비교

- **Google 샘플**: 앱 시작 시 `NotificationChannel`을 즉시 생성 → OS가 채널을 인식하여 "실시간 정보" 토글 표시
- **대구버스 앱**: `NotificationHandler.createNotificationChannels()`가 `BusAlertService.onCreate()`에서만 호출됨 → 사용자가 버스 추적을 시작하기 전까지 `bus_tracking_ongoing` 채널이 OS에 등록되지 않음

#### 확인된 설정 (이미 올바르게 구성됨)

- `compileSdk = 36`, `targetSdk = 36` (Android 16)
- `androidx.core:core-ktx:1.17.0` (Live Update API 포함)
- `POST_PROMOTED_NOTIFICATIONS` 권한 선언 (AndroidManifest.xml)
- `IMPORTANCE_DEFAULT` 채널 중요도 (Google 샘플과 동일)
- `NotificationCompat.Builder`에 `setRequestPromotedOngoing(true)`, `setShortCriticalText()`, `ProgressStyle` 적용 완료

### 수정된 파일

#### `android/app/src/main/kotlin/com/example/daegu_bus_app/MainActivity.kt`

##### 변경: `initializeEssentialComponents()`에 채널 생성 호출 추가

```kotlin
// 수정 전
notificationHandler = NotificationHandler(this)
createAlarmNotificationChannel()

// 수정 후
notificationHandler = NotificationHandler(this)
notificationHandler.createNotificationChannels()  // ← 추가
createAlarmNotificationChannel()
```

- 앱 시작 시 `bus_tracking_ongoing` 채널이 OS에 즉시 등록됨
- OS가 채널의 promoted notification 속성을 인식하여 설정에 "실시간 정보" 토글 표시
- `BusAlertService.onCreate()`의 기존 호출은 유지 (서비스 재시작 시 채널 보장)

### 테스트 방법

1. 앱 완전 제거 후 `flutter run`으로 재설치
2. 설정 → 앱 → 대구버스 → 알림에서 "실시간 정보" 토글 표시 확인
3. 토글 활성화 후 버스 추적 시작 → 상태 칩/잠금화면 Live Update 작동 확인

### Live Update 전체 요구사항 정리 (Android 16+)

1. `targetSdk 36` + `compileSdk 36`
2. `POST_PROMOTED_NOTIFICATIONS` 권한 선언
3. `androidx.core:core-ktx:1.17.0` 이상
4. 앱 시작 시 `NotificationChannel` 생성 (IMPORTANCE_DEFAULT)
5. `setRequestPromotedOngoing(true)` - 승격 요청
6. `setShortCriticalText()` - 상태 칩 텍스트
7. `NotificationCompat.ProgressStyle` - 진행 바 스타일
8. `setOngoing(true)` - 진행 중 알림
9. `setCategory(Notification.CATEGORY_PROGRESS)` - 카테고리


---

## 2026-07-05: 지식 베이스 재구조화 + flutter analyze 이슈 전체 정리

### 문서 구조 (커밋 b481122)
- `docs/index.md`(진입점) + `docs/topics/`(live-update-notification, auto-alarm, tts-audio) 신설
- devlog 중복 제거(구 AGENTS.md 쪽 2026-01-28 1~4차) 및 폐기 엔트리 `⚠️` 플래그
- AGENTS.md에 "작업 후 devlog append + topic 갱신" 워크플로 규칙 추가

### analyze 이슈 30건 정리 (커밋 424d1ba)
- `dart fix --apply` 20건: const, 문자열 interpolation, `rethrow`, 불필요 단언/중괄호,
  unused import, `data!` → `data as T` (api_result.dart)
- `use_build_context_synchronously` 9건: 파라미터/builder로 받은 context를 State의
  `mounted` 대신 `context.mounted`로 가드 (favorites_screen, active_alarm_panel,
  unified_bus_detail_widget)
- `map_screen.dart`의 미사용 `_loadNearbyStations()` 삭제
- 검증: `flutter analyze` 0건, `flutter test` 28건 전체 통과

### 부수 정리
- 옛 경로를 가리키던 stale worktree(funny-fermat) 등록 prune, 깨진 `.git` 링크는
  `.git.disabled`로 보존 (브랜치 `claude/funny-fermat`는 미머지 WIP로 남아 있음)
- pre-commit 훅: Dart 관련 파일이 스테이징된 경우에만 `flutter analyze` 실행하도록 수정

---

## 2026-07-05 (2차): 리팩토링 — dead code 제거 + 중복 로직 통합

### 점검 결과
- lib 전체 24,952줄 중 위젯 5개 파일(~2,737줄, 11%)이 어디서도 참조되지 않는 dead code로 확인
- 알람/캐시 키 문자열 조립이 3개 파일 18곳에 중복 (과거 키 불일치 동기화 버그의 원인 패턴)
- 도착 시간 라벨 포맷이 모델(BusArrival)에 있는데도 home/favorites 화면에 중복 구현

### 수정 (커밋 3건)
1. **c038e61** dead widget 제거: active_alarm_panel, bus_arrival_list, lightweight_bus_card,
   bus_card, compact_bus_card (import·클래스명 검색으로 미사용 검증)
2. **5aad377** `lib/services/alarm/alarm_keys.dart` 신설 — alarm/cache/cancellation 키 18곳 통합
3. **7af3cc8** 도착 라벨 단일화: 화면별 `_formatArrivalTime` 삭제 →
   `BusArrival.getFirstArrivalTimeText()` 사용, `ArrivalTimeFormatter` 콜백 파라미터 제거,
   bus_arrival.dart unicode escape → 한글 리터럴 정규화, `toString()` `\$` 버그 수정,
   라벨 회귀 테스트를 모델 파일 기준으로 갱신

### 검증
- 각 단계마다 `flutter analyze` 0건 + `flutter test` 28건 통과

### 남은 리팩토링 백로그 (대형, 별도 세션 권장)
- `MainActivity.kt` 2,588줄 — 메서드 채널 핸들러 분리 필요
- `BusAlertService.kt` 2,519줄 — 2026-01-29 분리 이후에도 재비대화
- `lib/services/alarm_service.dart` 1,707줄 — alarm/ 모듈로 이관 미완 (facade와 역할 중복)
- `alarm_screen.dart` 1,630줄 / `map_screen.dart` 1,570줄 / `unified_bus_detail_widget.dart` 1,444줄

---

## 2026-07-05 (3차): alarm_service.dart → alarm/ 모듈 이관

### 목표
백로그의 "alarm_service.dart 1,707줄 — alarm/ 모듈 이관 미완" 해소.
AlarmService를 ChangeNotifier 코디네이터로 축소 (1,707 → 1,123줄, −34%).

### 이관 내역 (커밋 4건, 단계별 analyze+test 검증)
1. **d661bc7** 유틸 이관: `station_id_resolver`(정류장 이름 매핑),
   `arrival_time_parser`(도착 시간 문자열→분), `auto_alarm_validator`(필수 필드 검증)
2. **3c3e69b** `alarm_repository.dart` 신설: SharedPreferences 로드/저장 전담.
   3회 복붙돼 있던 BackgroundIsolateBinaryMessenger 초기화를 단일 헬퍼로.
   '이번달+다음달 공휴일+customExcludeDates' 블록도 `_getUpcomingExclusionDates()`로
   통합 (기존엔 알람 루프마다 재조회 → 호출당 1회로)
3. **b0fe0f6** `alarm_event_handler.dart` 신설: ~250줄 `_handleMethodCall` 이관.
   2회 통째로 중복이던 '알람 제거+캐시+추적 상태 정리'를 `_cleanupAfterRemoval`로,
   중복 이벤트 타임스탬프 윈도우를 `_isDuplicateEvent`로 추출
4. **4bf5771** `auto_alarm_arrival_parser.dart` 신설: refreshAutoAlarmBusInfo의
   ~130줄 응답 정규화(String/List/Map, arrList/bus, 노선 매칭) 이관

### 남은 구조
- AlarmService에는 추적 제어(start/stop/cancel), CRUD 진입점, TTS 오케스트레이션,
  notifyListeners만 남음. 추적 제어의 추가 분리는 선택적 후속 과제.

---

## 2026-07-06: 자동알람 신뢰성 버그 2건 수정 (공휴일 오발화·유령 알람)

### 배경 (환경별 동작 점검에서 발견)
- 공휴일 제외(excludeHolidays)가 Flutter 스케줄 경로에만 있고, 발화 후 자가 체인
  (AlarmReceiver)·재부팅 재등록(BootReceiver)은 repeatDays만 보고 재계산 → 앱을 안
  열면 공휴일에도 울림
- alarmId가 경로마다 다르게 계산됨 (Flutter: Dart String.hashCode / BootReceiver:
  Math.abs(Java hash)) → 재부팅 후 이중 등록, 삭제해도 다음 재부팅까지 계속 울리는
  유령 알람 가능
- 추가 발견: BootReceiver의 getStringSet("flutter.auto_alarms")는 플러그인이
  StringList를 인코딩된 String으로 저장하기 때문에 항상 실패 — 재부팅 재등록이
  사실상 전혀 동작하지 않고 있었음

### 수정 (커밋 3건, 상세 계약은 topics/auto-alarm.md)
1. **c271b7b** 공휴일 제외 전파: Flutter가 `excluded_dates` prefs(JSON "yyyy-MM-dd")를
   내려두고, excludeHolidays 플래그가 인텐트 extras로 왕복. findNextTargetTime이
   제외 날짜 스킵 (탐색 창 8→60일)
2. **076d2b5** alarmId 통일(`AlarmKeys.autoAlarmNativeId`, 결정적 Java-style 해시) +
   네이티브 `auto_alarm_store` 신설(스케줄 시 기록, 취소 시 제거) + BootReceiver를
   저장소 기반으로 재작성. 취소 시 legacy ID 2종 스윕, loadAutoAlarms에서 1회성
   구버전 잔여 알람 정리(legacy_alarm_ids_cleaned_v1 플래그)
3. **3c80098** 테스트를 새 계약(취소 3회 + 순서)에 맞게 갱신

### 검증
- flutter analyze 0건, flutter test 28건 통과, :app:compileDebugKotlin BUILD SUCCESSFUL

### 남은 한계 (앱에서 해결 불가·후속 과제)
- force stop·삼성 딥슬립은 플랫폼 제약 (설정 화면 안내가 최선)
- Android 12(API 31~32) canScheduleExactAlarms() 미체크, _scheduleBackupAlarm은
  로그만 찍는 가짜 구현 — 별도 수정 필요

---

## 2026-07-06 (2차): 공휴일 조회 로직 개선 (HolidayService 재설계)

### 기존 문제
- 번들 에셋(2024~2027) 최우선 → 임시공휴일 지정이 반영될 수 없음
- CDN 결과가 세션 메모리에만 캐시 → 재시작마다 재요청, 오프라인이면 유실
- 실패 시 빈 리스트가 세션 내내 negative-cache → 시작 시 오프라인이면
  공휴일 제외가 조용히 꺼짐 (excluded_dates에도 빈 값이 내려감)
- alarm_screen이 별도 인스턴스 생성 → 캐시 미공유

### 개선
- 우선순위 재설계: 메모리 → 영속 캐시(SharedPreferences, 7일 TTL) →
  CDN(성공 시 영속화) → 만료된 영속 캐시 → 번들 에셋
- 실패는 영구 캐시하지 않고 30분 백오프 후 재시도 (네트워크 복구 시 자동 회복)
- 동시 호출은 in-flight Future 합류로 CDN 1회만 요청
- 싱글턴화(facade·alarm_screen 캐시 공유), 테스트용 http.Client 주입
  (`HolidayService.internal`)
- 단위 테스트 6건 신설 (test/holiday_service_test.dart) — 캐시 우선순위·
  영속화·stale 폴백·에셋 폴백·백오프·동시 합류

### 검증
- flutter analyze 0건, flutter test 34건(기존 28 + 신규 6) 통과

---

## 2026-07-06 (3차): Android 12 exact alarm 권한 대응 + 가짜 백업 알람 제거

### 수정 (커밋 2건)
1. **a0a6f79** `AutoAlarmScheduleCalculator.scheduleExactAlarm` 공통 진입점 신설.
   API 31~32에서 정확한 알람 권한 회수 시(canScheduleExactAlarms=false 또는
   SecurityException) `setAndAllowWhileIdle`로 저하해 알람 소실 방지. 4개 호출
   지점(MainActivity, AlarmReceiver×2, BootReceiver) 모두 교체. Flutter용
   `canScheduleExactAlarms` 메서드 채널 추가 (추후 설정 UI 안내용).
   minSdk ≥ 23이므로 기존 `Build.VERSION_CODES.M` 분기는 제거.
2. **7fa3df6** alarm_scheduler.dart의 `_scheduleBackupAlarm`(로그만 찍는 가짜
   구현)과 어디서도 읽지 않는 `has_alarm_scheduling_error` 플래그 제거.
   백업 시각(target-5분)은 네이티브 trackingStartTime과 동일해 실구현 가치 없음.
   실패 시 TTS 안내만 유지(`_notifySchedulingFailure`).

### 검증
- flutter analyze 0건, flutter test 34건 통과, :app:compileDebugKotlin BUILD SUCCESSFUL

### 후속 과제 (선택)
- Android 12 사용자용 설정 화면 안내: canScheduleExactAlarms=false일 때
  `ACTION_REQUEST_SCHEDULE_EXACT_ALARM` 딥링크 버튼 노출

---

## 2026-07-06 (4차): 공휴일 데이터 보정 — 제헌절/노동절 필터 + 고정 공휴일 fallback

### 배경 ("다음해 임시공휴일 반영되나" 점검에서 발견)
- CDN 실측 결과 임시공휴일은 정상 수록(2025-01-27, 2025-06-03 확인), 연도
  롤오버도 정상. 그러나 upstream(월력요항 기반) 2026·2027 데이터에 **제헌절
  (공휴일 아님, 2008~)과 노동절**이 포함 — excludeHolidays 사용자의 출근 알람이
  평일(2026-07-17 금)에 스킵될 위험. 2025 데이터엔 없어 upstream 기준 비일관.
- CDN에 2028.json 미공개(404) — upstream 공개 전 조회 시 빈 리스트가 되어
  신정 등 확정 공휴일에도 알람 발화.

### 수정 (831e700)
- `_parse`에서 이름 기반 필터: 제헌절·노동절(근로자의 날)과 그 대체공휴일 제외.
  같은 날짜에 유효한 공휴일 이름이 겹치면 유지. 노동절 제외는 "안 울려서
  지각보다 울리는 쪽이 안전" 원칙 — 휴무 사용자는 커스텀 예외 날짜로 대응.
- 연도 데이터 완전 부재 시 빈 리스트 대신 **양력 고정 공휴일 8일** 반환
  (신정·삼일절·어린이날·현충일·광복절·개천절·한글날·성탄절). 설날·추석 등
  음력 공휴일은 계산 불가로 미포함(부분적 fallback).
- 테스트 3건 추가·1건 갱신 (총 36건 통과)

---

## 2026-07-06 (5차): fallback에 음력 공휴일(설날·추석·부처님오신날) 추가

### 배경
연도 데이터 완전 부재 시의 fallback이 양력 고정 8일뿐이라 설날·추석·부처님오신날이
누락 — 예: 2028 데이터 공개 전이면 설날 연휴에 출근 알람이 울림.

### 수정 (4795059)
- `korean_lunar_utils` 의존성 추가 (음양력 변환, 테이블 1900~2049)
- `fallbackHolidaysForYear`: 양력 고정 8일 + 음력 계산 7일(설날 연휴 3,
  부처님오신날 1, 추석 연휴 3). 테이블 범위 밖 연도는 양력만.
  대체공휴일 규칙은 fallback에서 미적용(최후 수단의 한계로 문서화).
- 변환 정확성은 2025·2026 확정 공휴일(CDN 실측값)과 교차 검증하는 테스트로 고정
- 테스트 2건 추가 (총 38건 통과)

---

## 2026-07-06 (6차): 음력 공휴일 정밀화 + 임시공휴일 발화 시점 게이트

### 발견: korean_lunar_utils는 중국력 기반
fallback 대체공휴일 규칙 구현 중 교차 검증 테스트가 2027 설날을 2/6으로 잡아냄 —
한국 설날은 2/7. 자오선 차이(UTC+8/+9)로 한중 음력이 갈라지는 해(2027 등)가 있어,
중국력 기반 변환기는 한국 공휴일에 쓸 수 없음.

### 수정 (커밋 2건)
1. **4421252** 음력 변환을 klc(한국천문연 기준 KoreanLunarCalendar 포트)로 교체 +
   「관공서의 공휴일에 관한 규정」 제3조 대체공휴일 규칙 구현:
   - 설·추석 연휴: 일요일·타공휴일 겹침 → 연휴 뒤 첫 평일
   - 어린이날·부처님오신날·성탄절: 토일·타공휴일 겹침 / 삼일절·광복절·개천절·한글날: 토일
   - 신정·현충일: 대체 없음
   fallback이 2025~2027 확정 공휴일 달력을 전수 재현함을 테스트로 검증
   (임시공휴일·선거일 제외 — 계산 불가).
2. **2e666a1** 발화 시점 공휴일 게이트(`HolidayGate`) — 스케줄 등록 후 지정된
   임시공휴일 대응. 1단계: AlarmReceiver가 저장된 excluded_dates 동기 확인 →
   해당 시 추적 생략+체인만. 2단계: BusAlertService가 FGS 시작 후 CDN 신선
   조회(3초) → 공휴일 확인 시 자동알람 중단. 조회 실패는 알람을 막지 않음
   ("울리는 쪽이 안전").

### 검증
- flutter analyze 0건, flutter test 38건 통과, :app:compileDebugKotlin BUILD SUCCESSFUL

---

## 2026-07-06 (7차): 설정 화면에 정확한 알람 권한 안내 추가

### 수정 (84ae86a)
- 설정 > 알람 섹션에 `_ExactAlarmTile` 추가 (_LiveUpdatesTile 패턴):
  API 31 미만은 숨김, 허용 시 상태 표시, 회수 시 경고 + 탭하면
  `PermissionService.requestExactAlarmPermission()`으로 시스템 권한 화면 유도
- `canScheduleExactAlarms` 메서드 채널 핸들러를 bus_api → permission 채널로 이동
  (다른 권한 조회들과 같은 위치), `PermissionService.canScheduleExactAlarms()` 추가

### 검증
- flutter analyze 0건, flutter test 38건 통과, :app:compileDebugKotlin BUILD SUCCESSFUL

---

## 2026-07-07: 리팩토링 2차 — 화면 분리·타일 공용화·알람 토글 통합

### 수정 (커밋 3건, 권장 순서 ②→④→③)
1. **51f7d9d** alarm_screen.dart(1,630줄)에서 AutoAlarmEditScreen(664줄)을
   auto_alarm_edit_screen.dart로 분리 (동작 변경 없음)
2. **c70f836** 설정 화면 _ExactAlarmTile/_LiveUpdatesTile을 공용
   `_PermissionStatusTile`(minSdk·check·request 파라미터화)로 통합 (−35줄)
3. **84816bd** 승차 알람 토글 흐름 3중 복제(home/_handleAlarmClick,
   unified_bus_detail/_handleAlarmToggle, favorites/_handleEarphoneAlarm)를
   `utils/boarding_alarm_actions.dart`(toggle/setEarphoneAlarm)로 통합.
   의도된 동작 변화: 스낵바 문구·스타일 표준화, 도착 정보가 없어도 해제는 가능.
   unified의 _setAlarm/_cancelAlarm(TTS·동일 정류장 타 버스 취소)은 별도 동작이라 유지.

### 검증
- 각 단계 flutter analyze 0건 + flutter test 38건 통과

### 남은 백로그
- **MainActivity.kt 2,622줄 — 채널 핸들러 55개 분리** (별도 세션 권장, 최우선)
- BusAlertService.kt 2,535줄 / map_screen 1,578 / unified_bus_detail_widget 1,411 /
  home_widgets 1,032 — UI 모놀리스는 위젯 테스트 보강 후 진행 권장

---

## 2026-07-07 (2차): MainActivity.kt 메서드 채널 핸들러 분리

### 수정
- MainActivity.kt **2,622줄 → 631줄**. 채널 핸들러 5개를 새 패키지
  `channels/`의 `MethodChannel.MethodCallHandler` 구현 클래스로 분리:
  - `PermissionChannelHandler` (5 케이스) / `BusApiChannelHandler` (36) /
    `TtsChannelHandler` (6) / `StationTrackingChannelHandler` (2) /
    `BusTrackingChannelHandler` (5)
- BUS_API `when`의 죽은 중복 분기 3개 제거: `startTtsTracking`·
  `setAudioOutputMode`·`setVolume`의 두 번째 정의. Kotlin `when`은 첫 분기만
  실행되므로 동작 변화 없음 (첫 정의의 시맨틱 유지)
- MainActivity 노출 변경: `busAlertService`·`busApiService`·`notificationHandler`를
  internal로, lateinit `tts`/`audioManager` 폴백은 internal 헬퍼로 추출
  (`speakFallbackTts`/`stopFallbackTts`/`isHeadphoneConnectedViaAudioManager`/
  `startAndBindBusAlertService`)
- 참조 없는 private 메서드 7개 삭제: checkAndRequestPermissions, calculateDistance,
  splitIntoSentences, setupNotificationChannel, stopBusTrackingService,
  stopSpecificTracking(private 버전), requestBatteryOptimizationExemption
- 로그 TAG가 채널별로 바뀜 (`MainActivity` → `BusApiChannel`/`TtsChannel` 등) —
  logcat 필터링 시 참고

### 검증
- `:app:compileDebugKotlin` BUILD SUCCESSFUL
- 메서드 케이스 대조(HEAD vs 신규): live 케이스 54개 전부 이관 확인, 누락 0

### 남은 백로그
- BusAlertService.kt 2,535줄 — 재비대화 분리 (다음 네이티브 후보)
- map_screen 1,578 / unified_bus_detail_widget 1,411 / home_widgets 1,032 —
  위젯 테스트 보강 후 진행

---

## 2026-07-07 (3차): Play Store 업데이트용 AAB 1.0.3+63 생성

### 수정
- Play Store에 이미 출시된 `1.0.3+62` 이후 업로드를 위해 `pubspec.yaml` 버전을
  `1.0.3+63`으로 증가.

### 이 릴리스에 함께 포함된 변경
- **route_map_screen**: 노선도의 정류장 도착 정보 시트에서 버스 행을 탭하면
  통합 버스 상세 모달(`showUnifiedBusDetailModal`)이 열림. 시트를 pop한 뒤
  `parentContext`로 모달을 띄우고, wincId→stationId 변환 결과를
  `_effectiveStationId`로 추적해 전달. (나머지 diff는 dart format 재정렬)
- **AndroidManifest**: `uses-feature required=false` 4건 추가
  (bluetooth·location·gps·network) — Play Console 기기 필터링으로 설치 제외되는
  기기가 없도록 명시
- **build_release.ps1**: `flutter build` 실패 시 `$LASTEXITCODE` 체크로 즉시
  중단 (이전에는 실패해도 완료 메시지 출력)

### 산출물
- `build/app/outputs/bundle/release/app-release.aab` 생성
- 병합 매니페스트 기준 `versionCode=63`, `versionName=1.0.3`
- SHA-256:
  `A3D14247908FA5449E0C1B50F32D17838DBE078E499F55E52760F82C653FC9FE`

### 검증
- `flutter analyze` 0건, `flutter test` 38건 통과
- `.\build_release.ps1` AAB 빌드 성공
- 실기기(SM-S938N, Android 16) release APK 설치 후 홈·설정 화면, Live Updates·
  정확한 알람 타일 정상 확인, 크래시 없음

---

## 2026-07-07 (4차): 리팩토링 실행 계획서 작성

### 추가
- `docs/refactoring-plan.md` 신설, `docs/index.md`에 등록. 남은 리팩토링 백로그
  6건(BusAlertService 분리, UI 위젯 테스트 보강, map_screen·unified_bus_detail·
  home_widgets 분리, alarm_service 잔여 이관)을 실행 에이전트가 세션 단위로
  집어들 수 있는 작업 지시서로 정리.
- 각 작업에 현재 구조 실측(줄 수·클래스/함수 위치), 단계별 커밋 단위, 검증 명령,
  함정 목록, 완료 기준 명시. 공통 원칙(verbatim 이동, 기계적 대조, 죽은 코드
  판정 기준, 금지 사항)은 MainActivity 분리(5086dad)에서 검증된 방식을 성문화.

---

## 2026-07-10: 저장된 자동 알람 OFF 상태 복원 오류 수정

### 원인
- 알람 화면은 토글 OFF 시 `isActive=false`를 저장하고 네이티브 예약을 취소했지만,
  앱 시작 및 2분 주기 새로고침에서 호출되는 `AlarmService.loadAutoAlarms()`가
  `isActive`를 확인하지 않고 저장된 모든 알람을 다시 예약했다.

### 수정
- `loadAutoAlarms()`가 비활성 알람을 내부 활성 목록과 스케줄러에서 제외한다.
- 비활성 알람에 남아 있을 수 있는 현행·레거시 네이티브 예약과
  `auto_alarm_store` 재부팅 재등록 항목도 취소 경로를 통해 정리한다.
- 비활성 저장 알람의 미등록·잔여 예약 취소를 검증하는 회귀 테스트를 추가했다.

---

## 2026-07-10 (2차): 버스 상세 배지의 노선도 진입 개선

### 수정
- 통합 버스 상세 모달의 버스 번호 오른쪽에 16dp `route_rounded` 아이콘을 추가해
  노선도 이동 가능성을 시각적으로 표시했다.
- 기존 정적 배지를 48dp 최소 높이의 `InkWell`로 변경하고, 현재 노선을 초기값으로
  `RouteMapScreen`에 전달한다. 모달은 `pushReplacement`로 교체되어 뒤로가기 시
  원래 화면으로 복귀한다.
- 툴팁과 TalkBack 라벨을 `N번 노선도 보기`로 통일했다.
- 아이콘·툴팁 표시와 탭 후 노선도 진입을 검증하는 위젯 테스트를 추가했다.

### 검증
- `flutter analyze` 문제 없음, `flutter test` 전체 40건 통과.
- `flutter build apk --release` 성공 (`app-release.apk`, 57.6MB).
- 모바일 감사 스크립트는 저장소 전체의 기존 작은 시각 아이콘을 터치 대상으로
  판정해 397건을 보고했으며, 이번 노선도 배지는 `minHeight: 48`로 기준을 충족한다.
- SM-N976N에 release APK `1.0.3+63` 신규 설치 후 홈 정류장 시트 → 501번 상세
  → `501번 노선도 보기` 배지 탭을 검증했다. 48dp 이상 터치 영역·접근성 라벨,
  501번 노선 정보와 139개 정류장 로드, 시스템 뒤로가기 홈 복귀가 모두 정상이다.

---

## 2026-07-10 (3차): 버스 상세 도착 순서 디자인 개선

### 수정
- `첫 번째 버스`와 `다음 버스`로 분리됐던 제목·카드를 하나의 `도착 예정` 목록으로
  통합하고 표시 중인 버스 수를 `N대`로 노출했다.
- 각 카드에 `먼저 도착`/`다음 도착` 순서 배지를 넣어 도착 시간, 현재 위치,
  남은 정류장을 한 흐름에서 비교하도록 정보 위계를 정리했다.
- 먼저 도착 카드는 primary 계열, 다음 카드는 중립 surface 계열로 구분하고 카드·
  시간 타일 모서리를 8dp로 정리했다.
- 승차 알람 버튼의 실제 터치 영역을 48×48dp로 고정하고 상태별 툴팁을 추가했다.
- `docs/topics/bus-detail-ui.md`에 문제 정의·현행 구조·검증 기준을 문서화하고,
  두 대 도착 정보의 새 구조를 검증하는 위젯 테스트를 추가했다.

### 검증
- `flutter analyze` 문제 없음, `flutter test` 전체 41건 통과.
- `flutter build apk --release` 성공 (`app-release.apk`, 57.6MB).
- 모바일 감사 스크립트는 저장소 전체 시각 아이콘을 터치 대상으로 간주해 기존 포함
  399건을 보고했다. 이번 카드의 실제 알람 액션은 48×48dp로 기준을 충족한다.
- SM-N976N에 업데이트 설치 후 501번 상세에서 `도착 예정 · 2대`, `먼저 도착`,
  `다음 도착` 순서와 긴 정류장명 한 줄 배치를 확인했다. 과거 `첫 번째 버스`,
  `다음 버스` 분리 제목은 노출되지 않는다.

## 2026-07-11 (1차): 급행 노선 상세 카드 색상 정합성 보정

### 수정
- 버스 상세 모달의 `먼저 도착`/`다음 도착` 상단 배지와 첫 카드 강조색이 급행 노선일 때 빨간색 route accent를 따르도록 맞췄다.
- 정류소 목록에서 이미 사용하던 급행 시각 규칙과 상세 카드의 시각 규칙을 통일해, 같은 노선 타입이 화면마다 다른 색으로 보이는 편차를 제거했다.
- 급행 노선의 카드 상단 배지가 실제로 빨간 컨테이너를 가지는지 확인하는 widget test를 추가했다.

### 검증
- 아직 `flutter analyze`와 `flutter test`는 다시 돌리지 않았다. 코드 변경 후 필수 검증으로 실행할 예정이다.


## 2026-07-12 (1차): 급행 상세 상단 배지 색상 보정

### 수정
- 급행2 상세 화면의 상단 노선도 버튼과 버스 번호 배지가 route accent를 따르도록 정리했다.
- 상세 카드 상단의 `먼저 도착` 배지와 주요 강조색도 급행일 때 빨간색으로 유지되게 맞췄다.
- 급행 노선의 상단 route 버튼 gradient와 arrival badge 색을 검증하는 widget test를 추가했다.

### 검증
- 아직 `flutter analyze`와 `flutter test`는 다시 돌리지 않았다. 코드 변경 후 필수 검증으로 실행할 예정이다.

## 2026-07-12 (2차): 급행 route accent 그림자 보정

### 수정
- 급행2 상세에서 상단 노선도 버튼의 그림자색이 기본 primary로 남아 파란 기운이 보이던 부분을 route accent red로 바꿨다.
- 급행 노선의 시각 규칙이 배지, 카드 강조, 버튼 그림자까지 같은 색 기준을 따르도록 정리했다.

### 검증
- `flutter analyze lib/widgets/unified_bus_detail_widget.dart test/unified_bus_detail_express_color_test.dart` 문제 없음.
- `flutter test test/unified_bus_detail_express_color_test.dart` 통과.

## 2026-07-12 (3차): 급행 도착 카드 배경 중립화

### 수정
- 급행 노선의 `먼저 도착` 카드가 빨간 배경으로 보이던 구성을 중립 surface 배경으로 바꿨다.
- 급행 강조는 카드 배경이 아니라 배지와 텍스트, 아이콘 수준으로 제한했다.
- 급행 카드 배경이 빨갛지 않은지와 route 버튼 gradient가 빨간지 확인하는 widget test를 갱신했다.

### 검증
- 아직 `flutter analyze`와 `flutter test`는 다시 돌리지 않았다. 코드 변경 후 필수 검증으로 실행할 예정이다.

## 2026-07-12 (4차): 급행 도착 카드 배경 중립화 정착

### 수정
- 급행 노선의 `먼저 도착` 카드 배경에서 빨간 채도를 제거하고, 카드 배경은 급행/일반 모두 중립 surface 계열로 맞췄다.
- 급행 강조는 배지, 아이콘, 텍스트처럼 국소 요소에만 남겨 카드 덩어리가 과하게 붉어 보이지 않도록 정리했다.

### 검증
- `flutter analyze lib/widgets/unified_bus_detail_widget.dart test/unified_bus_detail_express_color_test.dart` 문제 없음.
- `flutter test test/unified_bus_detail_express_color_test.dart` 통과.

## 2026-07-12 (5차): 급행 도착 시간만 임박 시 적색 강조

### 수정
- 급행2 상세의 `도착 예정` 카드에서 급행 전용 빨간 배경과 배지 강조를 제거하고, 카드 본문은 일반 노선과 같은 중립 톤으로 유지했다.
- 빨간색은 임박한 시간 숫자에만 남기고, `10분` 같은 일반 도착 시각과 `먼저 도착 / 다음 도착` 라벨은 중립으로 유지했다.
- 임박한 시간 숫자가 빨간색으로 바뀌는지와 비임박 카드가 중립인지 확인하는 widget test를 추가했다.

### 검증
- 아직 `flutter analyze`와 `flutter test`는 다시 돌리지 않았다. 코드 변경 후 필수 검증으로 실행할 예정이다.

## 2026-07-12 (6차): 급행 도착 시간만 임박 시 적색 강조 정리

### 수정
- 급행 상세의 `도착 예정` 카드에서 `10분` 같은 일반 도착 시간과 `먼저 도착`/
  `다음 도착` 라벨을 중립으로 유지하도록 다시 정리했다.
- 빨간색은 임박한 시간 숫자에만 남기고, 도착 카드 배경과 배지는 급행/일반 모두
  같은 중립 surface 톤을 쓰도록 맞췄다.
- 급행 카드가 중립이고 `2분`만 적색으로 바뀌는지 확인하는 widget test를 유지했고,
  `10분`이 중립인지 확인하는 검증을 추가했다.

### 검증
- `flutter analyze lib/widgets/unified_bus_detail_widget.dart test/unified_bus_detail_express_color_test.dart` 문제 없음.
- `flutter test test/unified_bus_detail_express_color_test.dart` 통과.
- `flutter build apk --release` 성공 (`app-release.apk`, 57.6MB).
- 연결된 기기 `R3CM70K2YZD`에 APK 재설치 후 앱 재실행 완료.

## 2026-07-12 (7차): 노선 배지 색상 공용화

### 수정
- 노선 배지와 상세 노선도 버튼의 색상 규칙을 `lib/utils/route_branding.dart`로
  공용화했다.
- `직행`은 흰 배경 + 빨간 글자/테두리, `급행`/`순환`/`간선`/`지선`/`출근`/
  `군위`/`투어`/`DRT`는 각 분류별 단색 배경 + 흰 글자로 통일했다.
- 홈 즐겨찾기 버스, 검색 결과 노선 배지, 버스 상세 모달 상단 배지, 노선도 화면
  제목이 같은 분류명을 공유하도록 맞췄다.
- 새 `route_branding` 단위 테스트와 상세 모달 회귀 테스트를 추가했다.

### 검증
- `flutter analyze` 문제 없음.
- `flutter test test/route_branding_test.dart test/unified_bus_detail_express_color_test.dart` 통과.
- `flutter build apk --release` 성공 (`app-release.apk`, 57.7MB).
- 연결된 기기 `R3CM70K2YZD`에 APK 재설치 후 앱 재실행 완료.

## 2026-07-12 (8차): 대구 버스 분류명 정리 및 출근맞춤 라벨 통일

### 수정
- `daegu_bus.md` 기준으로 노선 분류를 `직행버스`, `급행버스`, `순환버스`, `간선버스`, `지선버스`, `출근맞춤버스`로 다시 정리했다.
- 노선 배지 공통 분류 로직에서 `4010`과 `출근맞춤` 계열은 `출근맞춤` 라벨로 표시하도록 맞췄다.
- `docs/topics/route-branding.md`와 `docs/index.md`의 현재 상태 요약도 동일한 분류명으로 갱신했다.

### 검증
- `flutter analyze` 통과.
- `flutter test test/route_branding_test.dart test/unified_bus_detail_express_color_test.dart` 통과.

## 2026-07-12 (9차): 다크모드 정류장 번호 배지 대비 개선

### 수정
- 검색 결과 정류장 카드와 홈의 선택된 정류장 카드에서 정류장 번호를 공용 `StationNumberBadge`로 분리했다.
- 밝은 테마는 `primaryContainer`/`onPrimaryContainer`, 어두운 테마는 `surfaceContainerHighest`/`onSurface`를 쓰도록 바꿔 다크모드에서도 번호가 읽히게 했다.
- 정류장 UI 현재 상태 문서를 새로 추가하고 `docs/index.md`에 등록했다.

### 검증
- `flutter analyze` 통과.
- `flutter test test/station_number_badge_test.dart test/route_branding_test.dart test/unified_bus_detail_express_color_test.dart` 통과.

## 2026-07-12 (10차): 홈 즐겨찾기 버스 노선 칩 브랜드 색상 적용

### 수정
- 홈의 즐겨찾기 버스 카드 `HomeRouteItem`이 `resolveRouteBranding()`을 우선 사용해 노선 칩 배경과 텍스트 색을 함께 결정하도록 바꿨다.
- `직행`처럼 흰 배경을 쓰는 노선은 빨간 글자/테두리로 표시해 다크모드에서도 읽기 쉽게 정리했다.
- 홈 즐겨찾기 버스 카드 현재 상태 문서를 새로 추가하고 `docs/index.md`에 등록했다.

### 검증
- `flutter analyze` 통과.
- `flutter test test/home_favorite_bus_route_branding_test.dart test/station_number_badge_test.dart test/route_branding_test.dart test/unified_bus_detail_express_color_test.dart` 통과.

## 2026-07-12 (11차): 다크모드 일반노선 배지 대비 개선

- 홈 즐겨찾기 버스의 분류되지 않은 일반노선 배지가 폴백 배경 명도에 따라 검정/흰색 글자를 선택하도록 수정했다.
- 흰색 계열 배경에서 흰 글자가 겹치던 문제를 회귀 테스트로 고정했다.
- 검증: `flutter test test/home_favorite_bus_route_branding_test.dart`, `flutter analyze`.

## 2026-07-13: 홈 선택 정류장 내부 ID 표시 제거

- 홈의 선택된 정류장 패널에서 정류장명 아래에 노출되던 `stationId`를 제거했다.
- `stationId`는 버스 조회·알람 처리에는 그대로 전달하고, UI에서만 숨긴다.
- 선택 정류장명은 남고 내부 ID는 렌더링되지 않는 위젯 회귀 테스트를 추가했다.

## 2026-07-13 (2차): 지도 정류장 홈 전환 및 자동알람 사전 진동 억제

### 수정
- 지도에서 유효한 정류장 마커를 선택하면 정류장명과 `홈에서 보기` 액션 카드를 표시한다.
- 홈에 임베드된 지도는 콜백으로 홈 탭과 선택 정류장을 갱신하고, 노선도에서 push된 지도는
  `BusStop`을 Navigator 결과로 반환해 상위 화면이 홈 전환을 이어서 처리한다.
- 자동알람의 5분 전 사전 추적 구간에서는 ETA 변경만으로 진동하지 않고, 남은 정거장
  1~2개 또는 3분 이내(`곧 도착` 포함)일 때만 진동하도록 변경했다. 수동 승차 알람의
  ETA 변경 진동은 유지한다.

### 검증
- `flutter analyze` 통과.
- `flutter test` 전체 51개 통과.
- `./gradlew :app:compileDebugKotlin` 통과.
- `build_release.ps1`의 Play Store AAB 빌드 경로(서명, R8, 리소스 축소, 난독화) 성공.
- Galaxy S25 Ultra(`SM-S938N`), Android 16(API 36), One UI 8 실기기에서 다음을 확인했다.
  - 지도 마커 선택 → `홈에서 보기` → 홈 탭 전환과 정류장 도착 정보 표시 정상.
  - Android 16 Live Update와 Samsung Now Bar 정상 작동.
  - 자동알람 사전 추적/도착 임박 진동, 수동 알람 진동 회귀, TTS 출력 정상.
  - 앱 콜드 스타트와 알림·Promoted Notification·정확 알람·진동·위치·FGS 권한 정상.
- Play Console의 최신 프로덕션/내부 테스트 버전이 `62 (1.0.3)`임을 확인해 다음
  `versionCode 63`이 미사용 상태임을 확인했다. 게시되지 않은 Console 변경과 정책 문제는 없다.

## 2026-07-14: Android 15/16 edge-to-edge 권고 반영

### 수정
- `MainActivity`의 수동 `setDecorFitsSystemWindows(false)`를 AndroidX Views 권고 API인
  `WindowCompat.enableEdgeToEdge(window)`로 교체하고 `super.onCreate()` 뒤에 적용했다.
- 네이티브 Material 컴포넌트를 사용하지 않는데 포함돼 있던 Material 1.12.0 직접 의존성을
  제거해 릴리스 APK에서 `MaterialDatePicker`와 해당 지원 중단 시스템 바 호출 시작점을 제거했다.
- edge-to-edge 설정 회귀 테스트와 현재 상태 문서를 추가했다.

### 확인된 상위 의존성 한계
- Play Console 버전 62의 발견 항목은 `setNavigationBarDividerColor`, `setStatusBarColor`,
  `setNavigationBarColor`이다.
- 새 APK에도 Flutter 3.35.6 Android 임베딩 및 AndroidX 하위 버전 호환 코드의 API 참조는
  남는다. 앱 코드의 직접 호출은 아니므로 Console 경고 해소 여부는 새 APK 업로드 분석 후 확인한다.

### 검증
- `flutter test test/edge_to_edge_config_test.dart` 2개 통과.
- `flutter analyze` 통과.
- `./gradlew :app:compileDebugKotlin` 통과.
- `build_release.ps1 -Apk` 성공: `1.0.3+63`, AAB 미생성.
- 새 릴리스 APK에서 `MaterialDatePicker` 부재를 `apkanalyzer`로 확인했다.

## 2026-07-14 (2차): 지도 도착정보 액션 중복 정리

- 버스핀 팝업과 하단 카드에 정류장명이 이중 표시되던 구조를 정리해, 정류장 정보는
  버스핀에만 표시하고 하단에는 `도착정보 보기` CTA와 닫기만 남겼다.
- 시각적 정류장명을 제거해도 `_actionStation`으로 홈 전환 대상은 유지되며, TalkBack용
  의미 레이블에는 선택한 정류장명과 행동을 함께 제공한다.
- CTA와 닫기 버튼의 터치 영역을 각각 48dp 이상으로 고정했다.
- `flutter test test/map_station_action_card_test.dart` 2개 통과.
- Galaxy S25 Ultra(`SM-S938N`), Android 16 실기기에 `1.0.3+63` 릴리스 APK를
  덮어써 설치한 뒤, 버스핀의 정류장·도착 정보와 하단 `도착정보 보기` CTA가 중복 없이
  표시되고 홈 전환이 정상 작동함을 ADB로 확인했다.
- `flutter analyze` 및 `build_release.ps1 -Apk` 통과. AAB는 생성하지 않았다.

## 2026-07-14 (3차): 지도 도착정보 버튼 크기 조정

> ⚠️ 폐기됨 (2026-07-14): 폭 80% 제한은 실기기에서 레이블을 두 줄로 만들어 제거했다.

- 하단 `도착정보 보기` 버튼 폭을 기존의 80%로 줄이고 시각 높이를 48dp에서 40dp로
  조정했다.
- Material의 패딩된 터치 영역을 적용해 시각 크기와 별개로 최소 48dp 터치 높이는
  유지했다.
- 위젯 테스트에서 377dp 카드 기준 버튼 폭 234.4dp, 시각 높이 40dp, 터치 높이 48dp
  이상을 검증했다.
- `flutter test test/map_station_action_card_test.dart` 2개 및 `flutter analyze` 통과.

## 2026-07-14 (4차): 내부 테스트용 1.0.4 버전 준비

> ⚠️ 폐기됨 (2026-07-14): 아래 SHA-256의 첫 AAB는 지도 CTA 수정본으로 교체됐다.

- 이전 내부 테스트 번들 `1.0.3+63` 이후 사용자 표시 버전을 `1.0.4`로 올렸다.
- 동일 applicationId의 Android `versionCode`는 감소하거나 재사용할 수 없으므로 빌드
  번호를 `1`로 초기화하지 않고 다음 값인 `64`를 적용해 `1.0.4+64`로 설정했다.
- Play Console 관리용 릴리스 이름은 필요하면 `1.0.4 (1)`을 사용할 수 있지만, AAB의
  실제 버전은 `versionName=1.0.4`, `versionCode=64`다.
- `.\build_release.ps1`로 서명·R8 난독화·리소스 축소된 AAB 빌드에 성공했다.
  - 산출물: `build/app/outputs/bundle/release/app-release.aab` (48,478,216 bytes)
  - SHA-256: `BBC416BFC1B23F51889D7E7723196F0AC9886452D67BD5931E1A063618BE7604`
  - 패키징 manifest: `com.devground.daegubus`, `versionName=1.0.4`, `versionCode=64`
- `flutter analyze` 통과.

## 2026-07-14 (5차): 지도 도착정보 CTA 한 줄·높이 개선

> ⚠️ 폐기됨 (2026-07-15): 내부 FilledButton과 4dp 카드 패딩 구조를 단일 48dp 카드로 교체했다.

- Galaxy S25 Ultra(`SM-S938N`, Android 16, 화면 밀도 560dpi)에서 80% 폭으로 줄인
  `도착정보 보기`가 `도착정보 보` / `기` 두 줄로 표시되는 현상을 ADB 캡처로 재현했다.
- 원인인 `FractionallySizedBox(widthFactor: 0.8)`를 제거해 CTA가 남는 폭을 사용하도록
  하고, 레이블을 명시적으로 한 줄 처리했다.
- 카드 상하 패딩을 12dp에서 4dp로 줄이고 X 아이콘을 20dp로 낮췄다. CTA와 닫기
  버튼의 실제 터치 높이/영역은 각각 48dp 이상을 유지한다.
- 위젯 테스트 2개와 `flutter analyze`가 통과했다.
- 로컬 릴리스 APK는 Play 배포 앱과 서명이 달라 실기기 덮어쓰기가 거부됐다. 앱 삭제는
  하지 않아 사용자 데이터를 보존했으며, 내부 테스트 배포 후 실기기 확인이 필요하다.
- 수정본 `1.0.4+64` AAB 빌드 성공:
  - 크기: 48,477,767 bytes
  - SHA-256: `E5F8210A1E4ED78F282865627CAE8A133844BAD852FFFA03EBC096A6DE5A1626`

## 2026-07-15: 내부 테스트 AAB versionCode 65 준비

- `pubspec.yaml`을 `1.0.4+65`로 올려 다음 Google Play 내부 테스트 업로드를 준비했다.
- `flutter analyze` 통과.
- `.\build_release.ps1` AAB 빌드 성공:
  - 패키지: `com.devground.daegubus`
  - `versionName=1.0.4`, `versionCode=65`
  - 크기: 48,477,748 bytes
  - SHA-256: `4095982196912368AA093057E279EA627270E5CCCB49B5B3A63C0601CDCE46DC`
- 빌드 중 Android Studio와 command-line tools 간 SDK XML 버전 불일치 경고가 1건
  출력됐으나 Gradle 작업과 AAB 생성은 성공했다.

## 2026-07-15 (2차): 지도 도착정보 액션 단일 카드화

- 하단 액션의 바깥 카드 안에 있던 `FilledButton`을 제거해 중첩 상자 표현을 없앴다.
- 바깥 카드 높이를 48dp로 줄이고, 왼쪽 액션은 `InkWell` 리플과 TalkBack 의미 레이블을
  유지했다. 오른쪽 닫기 버튼도 독립된 48dp 터치 영역을 유지한다.
- 두 액션 사이에는 얇은 세로 구분선만 남겨 단일 표면 안에서 역할을 구분한다.
- `flutter test test/map_station_action_card_test.dart` 2개 및 `flutter analyze` 통과.

## 2026-07-15 (2차): 배포·검증 후속 상태 문서화

- `1.0.4+65`는 로컬 AAB 빌드 완료 상태이며, Play Console 업로드·내부 테스트 배포·
  Play 배포본 실기기 검증이 완료됐다고 간주하지 않도록 릴리스 상태 단계를 문서화했다.
- 지도 CTA의 최신 한 줄 레이아웃은 위젯 테스트까지 확인됐고, Play 배포본에서의
  실기기 확인은 후속 항목으로 분리했다.
- Play Console 지원 중단 API 재분석과 SDK XML 버전 불일치 경고 해소도 현재 후속
  확인 항목으로 모았다.
- `docs/topics/follow-up-status.md`를 추가하고 문서 색인에 등록했다.

## 2026-07-15 (3차): versionCode 65 배포 확인 및 66 준비

- 사용자 확인으로 `1.0.4+65`의 Google Play 전체 출시가 완료됐고, 지도에서 홈 화면으로
  정류장 도착 정보를 여는 흐름과 홈 정류장 즐겨찾기 별표가 정상 표시됨을 기록했다.
- 내부 FilledButton을 제거한 단일 48dp 지도 액션 카드 변경을 다음 배포에 포함하기 위해
  `pubspec.yaml`을 `1.0.4+66`으로 올렸다.
- `flutter test test/map_station_action_card_test.dart` 2개와 `flutter analyze` 통과.
- `.\build_release.ps1` AAB 빌드 성공:
  - 패키지: `com.devground.daegubus`
  - `versionName=1.0.4`, `versionCode=66`
  - 크기: 48,477,294 bytes
  - SHA-256: `AE6D71EB19546A98B9EB17089837FE94F5D2E7FF4473D3B8A5FF1797F6901EB5`

## 2026-07-25: 1.0.4+66 로컬 sideload 실기기 검증

- Galaxy Note10+(`SM-N976N`, adb 시리얼 `R3CM70K2YZD`)에 `.\build_release.ps1 -Apk`로
  만든 `1.0.4+66` 릴리스 서명 APK를 `adb install -r`로 덮어썼다. 기존 설치본
  (`1.0.3+63`)과 서명이 동일해 데이터 손실 없이 업데이트됐다 — 서명이 다르면
  `INSTALL_FAILED_UPDATE_INCOMPATIBLE` 오류가 나며, 그 경우 사용자 데이터 보존을
  위해 `uninstall`은 하지 않기로 했다 (2026-07-14 (5차) 항목과 동일한 판단).
- `adb shell input tap`과 `uiautomator dump`로 지도 마커 탭 → 팝업(정류장명+도착정보)
  → 하단 단일 CTA → CTA 탭 → 홈 탭 전환까지 전체 흐름을 재현해 확인했다.
  - 하단 CTA의 접근성 레이블이 `"<정류장명> 도착정보 보기"`(예: `칠성고가도로하단
    도착정보 보기`)로 확인돼, 시각적으로는 정류장명을 반복하지 않지만 TalkBack
    레이블에는 포함된다는 문서 서술과 일치함을 확인했다.
  - CTA 탭 후 홈 탭이 활성화되고 "근처 정류장" 목록에서 해당 정류장이 하이라이트되며
    하단에 도착정보 카드가 펼쳐지는 것을 스크린샷으로 확인했다.
  - WebView 기반 지도 마커라 좌표 추정만으로는 JS↔Flutter 브릿지 이벤트가 재발화되지
    않는 경우가 있었다(이미 선택된 마커 재탭 시). `uiautomator dump`로 정확한
    bounds를 구해 새 마커를 탭하는 방식으로 우회했다 — 앱 버그는 아니고 조사 방법의
    한계였다.
- `adb logcat -d *:E`에 `daegubus`/`FATAL` 관련 항목 없음, 조작 도중 프로세스가
  계속 실행 중임(`pidof`)을 확인해 크래시가 없었음을 확인했다.
- **이 검증은 로컬 sideload 기준이며 Play 배포본 검증이 아니다.**
  `docs/topics/release-versioning.md`의 "검증됨" 단계(Play 배포본 실기기 확인)는
  아직 미충족 상태다.

## 2026-07-25: BusAlertService.kt 분리 — 1단계 (명령 파싱 분리)

`docs/refactoring-plan.md` 작업 1의 1단계(명령 파싱 분리)만 진행했다.

### 수정
- `sealed class ServiceCommand`와 `parseCommand()`를 `BusAlertCommandParser.kt`(신규,
  같은 `services` 패키지)로 이동했다. `intent.getStringExtra` 등 Intent extras만
  읽는 순수 함수라 Context/서비스 상태 의존이 없어 계획서가 권장한 첫 단계였다.
- verbatim 이동: 본문은 들여쓰기 차이와 로컬 `ACTION_*` 별칭 대신 `BusActions.*`를
  직접 참조하는 것만 다르고 로직은 동일함을 `diff`로 대조했다.
- `ServiceCommand`가 같은 패키지의 top-level 선언이 되면서 `BusAlertService.kt` 쪽의
  `parseCommand(intent)` 호출부와 `is ServiceCommand.X` 사용부는 수정 없이 그대로
  컴파일된다 (Kotlin이 멤버 함수 제거 후 패키지 top-level 함수로 자동 해석).
- `BusAlertService.kt`: 2,535 → 2,469줄.

### 남은 작업 (작업 1의 2~4단계, 다음 세션)
- 2단계 `stopSpecificTracking`(642~853행)/`stopAllTracking`/`stopTrackingForRoute`
  통합 이동은 `this`(Context/Service), `isInForeground`, `stopForeground`/`stopSelf`,
  WorkManager, 브로드캐스트, 여러 HashMap 상태에 강하게 결합돼 있어 1단계보다
  훨씬 위험도가 높다. 실기기 스모크 없이 한 세션에서 밀어붙이지 않기로 하고
  여기서 멈췄다.
- 3단계(자동알람 경량 모드 이동), 4단계(알림 조립 이동)는 아직 손대지 않음.

### 검증
- `.\gradlew.bat :app:compileDebugKotlin`이 저장소에 커밋돼 있지 않아(`.gitignore`
  대상) `C:\Users\sh953\.gradle\wrapper\dists\gradle-8.11.1-bin\...\bin\gradle.bat
  --project-dir android :app:compileDebugKotlin`로 대체 실행해 통과를 확인했다.
  (Flutter가 최초 빌드 시 `gradlew`/`gradlew.bat`를 생성해준다 — 이후 세션에서는
  일반 `.\gradlew.bat` 사용 가능할 것.)
- `git show HEAD:...` 원본과 신규 파일을 `diff`로 대조해 이관 누락이 없음을 확인.

## 2026-07-25 (2차): BusAlertService.kt 분리 — 2단계 축소 (stopTrackingForRoute만 이동)

계획서 작업 1의 2단계("중지 로직 통합": `stopSpecificTracking`/`stopAllTracking`/
`stopTrackingForRoute`)를 시도했으나, 세 함수를 한 번에 옮기기엔 위험도가 너무
높다고 판단해 `stopTrackingForRoute` 하나만 이동하고 멈췄다.

### 조사 결과 — 왜 세 함수를 한 번에 옮기지 않았나
- `stopTrackingForRoute`(53행)는 이미 public API(채널 핸들러가 직접 호출)이고,
  이미 `BusAlertTrackingManager` 생성자에 콜백으로 주입되어 자기 자신을 되부르는
  구조였다 — 옮기면 오히려 간접 호출 한 겹이 없어진다. 필요한 의존성도
  `Service` 참조 + 컬렉션 4개 + 콜백 3개로 국한된다.
- 반면 `stopSpecificTracking`(212행)과 `stopAllTracking`(171행)은 서비스
  라이프사이클 상태(`isServiceActive`, `instance`(companion), `isManuallyStoppedByUser`,
  `lastManualStopTime`, `isAutoAlarmMode`, `autoAlarmStartTime`)를 직접 쓰고,
  `stopSpecificTracking`이 `stopAllTracking()`을 내부에서 호출하는 등 서로 얽혀
  있다. WorkManager 태그 취소, `checkAndStopServiceIfNeeded`/
  `sendCancellationBroadcast`/`sendAllCancellationBroadcast`/`stopMonitoringTimer`/
  `stopTtsTracking` 같은 private 헬퍼도 다른 코드 경로(예: `checkArrivalAndNotify`,
  `updateForegroundNotification`)와 공유돼 있어, 옮기려면 생성자 콜백을 10개
  이상 더 추가해야 했다.
- 이 정도 규모의 상태 이관은 계획서가 명시한 함정(포그라운드 서비스 타이밍,
  코루틴 스코프 소유권)이 실제로 발생할 수 있는 지점이고, 실기기 스모크
  없이는 `stopSelf()`/`stopForeground()` 순서가 꼬여도 컴파일만으로는 못 잡는다.
  그래서 여기서 멈추고 다음 세션(실기기 접근 가능할 때)으로 미뤘다.

### 수정
- `BusAlertTrackingManager`가 `service: Service`, `monitoredRoutes`,
  `arrivingSoonNotified`, `hasNotifiedTts`, `hasNotifiedArrival`,
  `generateNotificationId`(콜백), `setInForeground`(콜백), `ongoingNotificationId`를
  생성자로 받도록 확장하고 `stopTrackingForRoute`를 그 안으로 이동했다.
  `BusAlertNotificationUpdater`가 이미 쓰고 있던 "Service 참조를 직접 주입"
  패턴을 그대로 따랐다.
- verbatim 이동: 본문 차이는 `getSystemService`/`stopForeground`/`stopSelf`
  앞에 `service.`를 붙인 것과 `isInForeground = false` → `setInForeground(false)`,
  `ONGOING_NOTIFICATION_ID` → `ongoingNotificationId` 뿐임을 `diff`로 확인.
- `BusAlertTrackingManager.startTrackingInternal`의 자체 오류 복구 경로(2곳)에서
  이전엔 생성자 콜백 `stopTrackingForRoute(routeId, true)`를 호출했는데, 실제
  함수 시그니처의 두 번째 파라미터는 `stationId`이므로 `cancelNotification = true`
  named argument로 고쳐 호출했다 (기계적 치환이 아니라 의미를 보존하기 위한
  필수 수정).
- `BusAlertService.stopTrackingForRoute`의 public 시그니처는 그대로 두고 본문만
  `trackingManager.stopTrackingForRoute(...)` 위임으로 교체했다.
- `BusAlertService.kt`: 2,469 → 2,430줄.

### 남은 작업 (작업 1의 2단계 나머지 + 3~4단계)
- `stopSpecificTracking`/`stopAllTracking` 통합 이동은 다음 세션에서, 가능하면
  실기기 스모크(승차 알람 중지, 자동알람 중지, 모든 추적 중지 후 서비스 종료)를
  준비해두고 진행할 것.
- 3단계(자동알람 경량 모드 이동), 4단계(알림 조립 이동)는 아직 손대지 않음.

### 검증
- `gradle.bat --project-dir android :app:compileDebugKotlin` 통과.
- `git show HEAD:...` 원본과 신규 위치를 `diff`로 대조해 의도한 치환 외
  변경이 없음을 확인 (위 "수정" 항목의 치환 목록과 diff 결과가 일치).

## 2026-07-25 (3차): BusAlertService.kt 분리 — 작업 1 완료 (2단계 나머지 + 3~4단계)

사용자가 이전 세션의 진행분(1~2단계 일부)을 main에 머지·컴파일 확인한 뒤, 실기기
검증은 오케스트레이터가 adb로 별도 진행하기로 하고 이 세션에서 나머지 단계를 계속
진행하도록 요청했다. `docs/refactoring-plan.md` 작업 1의 2단계 나머지
(`stopSpecificTracking`/`stopAllTracking`)와 3~4단계(자동알람 경량 모드, 알림 조립)를
모두 완료했다. 커밋 3개, 매 단계 컴파일 + `git show HEAD:...` diff 대조로 verbatim
이동만 있었음을 확인했다.

### 2단계 나머지: stopSpecificTracking/stopAllTracking → BusAlertTrackingManager
- 두 함수 모두 **동기 함수**(코루틴을 스폰하지 않음)라는 걸 실제로 읽고 확인 —
  이전 세션에서 우려했던 코루틴 스코프 소유권 문제는 애초에 해당 없었다.
- `BusAlertTrackingManager` 생성자에 `isServiceActive`/`isManuallyStoppedByUser`
  등 서비스 라이프사이클 상태의 getter/setter 콜백 15개, `cachedBusInfo`,
  `autoAlarmNotificationId`를 추가했다.
- `sendCancellationBroadcast`(+ 백업 캐시 `sentCancellationEvents`/`eventTimeouts`)는
  호출부가 이 두 함수뿐이라 (grep 확인) 같이 이관 — 안 옮기면 죽은 코드로 남을
  뻔했다.
- 두 함수 모두 `private`였고 외부(다른 파일) 호출부가 없어 public 위임 스텁 없이
  호출부(`onStartCommand` 디스패치 2곳, `stopBusTracking`/`stopAllBusTracking`
  래퍼, `onDestroy`)를 `trackingManager.stopX()`로 직접 바꿨다.
- `BusAlertService.kt`: 2,430 → 2,021줄.

### 3단계: 자동알람 경량 모드 → BusAlertAutoAlarmNotifier
- `BusAlertAutoAlarmNotifier`는 이미 `service: BusAlertService` 전체 참조를 갖고
  있었다(콜백 주입이 아님) — `service.isInForeground`/`service.serviceScope`를
  이미 직접 읽고 쓰는 걸 확인하고 같은 패턴을 따랐다.
- 필요한 `private` 멤버 18개(`mainHandler`, `notificationHandler`,
  `ttsController`, `monitoringJobs`, `activeTrackings`, `pendingAutoAlarms`,
  `monitoredRoutes`, `cachedBusInfo`, `autoAlarmTimeoutRunnable`,
  `isAutoAlarmMode`, `autoAlarmStartTime`, `autoAlarmTimeoutMs`,
  `alarmSoundPlayer`, `currentAutoAlarmBusNo/StationName/RouteId`,
  `startTracking()`, `updateForegroundNotification()`)를 `internal`로 넓혔다.
- **함정**: 이동한 함수들의 `Log.d(TAG, ...)`가 원래 `BusAlertService`의
  `TAG="BusAlertService"`를 가리켰는데, `BusAlertAutoAlarmNotifier`는 자기 TAG가
  `"BusAlertAutoAlarmNotifier"`다. 그대로 옮기면 실기기 logcat 필터링이 조용히
  깨질 뻔했다 — 리터럴 `"BusAlertService"`로 치환해 원래 태그를 보존했다.
- `updateAutoAlarmBusInfo`는 저장소 전체 grep으로 외부 호출부가 0건임을 확인했지만
  `public`이라 위임 스텁을 남겼다 (계획서의 죽은 코드 삭제 기준은 `private`
  한정이라 삭제하지 않음).
- `BusAlertService.kt`: 2,021 → 1,803줄.

### 4단계: 알림 조립 → BusAlertNotificationUpdater
- `BusAlertNotificationUpdater`의 생성자 타입을 `service: Service` →
  `service: BusAlertService`로 넓혔다(호출부는 이미 `this`를 넘기고 있어서
  호출부 수정 0건). 3단계와 같은 "전체 참조 + internal 멤버" 패턴을 재사용.
- `resolveStationIdIfNeeded`(다른 호출부가 남아 있어 이관하지 않고 `internal`로만
  전환)와 `CHANNEL_ID_ALERT`도 `internal`로 넓혔다.
- `showOngoingBusTracking`/`updateTrackingNotification`은 `BusTrackingChannelHandler`가
  직접 호출하므로 public 위임 스텁 유지. `showBusArrivingSoon`은 외부 호출부
  0건이지만(grep) public이라 스텁 유지.
- `BusAlertService.kt` 내부 호출부 7곳(`onCreate`/`initialize`의 `showOngoing`
  콜백 2곳, 자동알람/도착 확인 알림 경로, `showNotification` 오버로드)을
  `notificationUpdater.showOngoingBusTracking(...)`로 갱신.
- `BusAlertService.kt`: 1,803 → 1,620줄.

### 패턴 정리 (다음에 비슷한 이동을 할 때)
2단계(콜백 주입)보다 3~4단계(협력 클래스가 `service: BusAlertService` 전체 참조를
갖고 필요한 멤버를 `internal`로 넓히는 방식)가 diff가 훨씬 작고 실수 여지가
적었다. **다음 유사 이동은 콜백 주입보다 이 패턴을 먼저 고려할 것.**

### 최종 결과
`BusAlertService.kt`: 2,535 → 1,620줄. 계획서 목표였던 ~1,200줄에는 못 미쳤지만
4단계 모두 완료. 남은 1,620줄은 대부분 서비스 라이프사이클 자체와 여러 협력
클래스를 넘나드는 조정 로직이라, 더 줄이려면 이 작업의 범위를 넘어서는 새로운
설계 판단이 필요하다 — 별도 작업으로 백로그에 남긴다.

### 실기기(adb) 검증 필요 항목 — 오케스트레이터가 이어서 확인
아래는 코드 검토·컴파일·diff 대조만으로는 확신할 수 없는, 실기기에서 반드시
확인해야 하는 시나리오다 (각 커밋 메시지에도 동일 내용 기록):

- **수동 알람 중지** (`stopSpecificTracking`): 알람 리스트 삭제 경로와
  리스트 유지(TTS만 중지) 경로 모두, 올바른 알림 ID가 취소되고 마지막 추적이면
  포그라운드 서비스가 실제로 중지되는지.
- **전체 알람 중지** (`stopAllTracking`): UI에서 호출, `ACTION_STOP_TRACKING`
  브로드캐스트, 앱 스와이프 종료(`onDestroy`) 세 경로 모두 알림/WorkManager
  작업이 완전히 정리되고 서비스가 고아 포그라운드 서비스로 남지 않는지.
- **자동알람 시작** (토글 기반 + Flutter 트리거 양쪽): 5초 제한 안에 포그라운드
  서비스가 실제로 시작되는지, 공휴일 게이트/TTS-vs-사운드 분기가 정상 동작하는지.
- **자동알람 타임아웃**: `mainHandler.postDelayed`로 예약된 타임아웃 Runnable이
  설정된 시간 후 실제로 발화해 알람을 정리하는지.
- **자동알람 중복 트리거 방지** (`pendingAutoAlarms`): 같은 노선을 짧은 간격으로
  두 번 트리거해도 중복 시작되지 않는지.
- **자동알람 중지** (수동/타임아웃/공휴일 감지 3가지 경로): 알림 취소, 추적 맵
  정리, 다른 추적이 없으면 포그라운드 서비스가 idle로 전환되는지.
- **알림 렌더링**: 수동/자동 알람 모두 버스 번호·정류장·ETA가 올바르게 표시되고,
  ETA/위치 갱신 시 알림이 새로 생기지 않고 같은 알림이 갱신되는지.
- **stationId 보정 재시도 경로** (`effectiveStationId`가 비어있거나 짧을 때):
  보정 후 알림이 실제로 갱신되는지 (조용히 누락되지 않는지).
- **1초 후 백업 `notify()`**: 알림이 눈에 띄게 깜빡이지 않으면서 안전망으로
  동작하는지.
- **알림에서 취소 탭 연타**: `sentCancellationEvents`/`eventTimeouts`(이동됨)
  기반 중복 방지가 여전히 중복 취소 이벤트를 막는지.

## 2026-07-28: BusAlertService.kt 추가 축소 — 1b-1 완료 (하단 유틸/확장 함수 분리)

`docs/refactoring-plan.md` 작업 1b의 1b-1 단계를 완료했다. `NotificationDismissReceiver`,
`isSamsungOneUi()`, `getNotificationChannels()`, `StationArrivalOutput`/`RouteStation`/
`BusInfo`(모델)/`StationArrivalOutput.BusInfo`의 `toMap()` 확장 함수 4개 — 전부
서비스 인스턴스 상태에 의존하지 않는 top-level 선언이라 계획서대로 새 파일
`BusAlertModels.kt`(같은 `services` 패키지)로 verbatim 이동했다.

- 이동 대상은 파일 맨 끝(1562~1620행)이라 잘라내기가 단순했다. `git show HEAD:...`로
  원본 블록과 새 파일 본문을 diff 대조해 이동 외 변경이 없음을 확인했다(새로 추가한
  `import com.devground.daegubus.models.BusInfo` 한 줄 제외 — `BusAlertService.kt`는
  이미 이 import를 갖고 있었지만 새 파일은 독립 파일이라 필요).
- `StationArrivalOutput`/`RouteStation`은 `BusApiService.kt`(같은 `services` 패키지)에
  정의돼 있어 import 없이 그대로 참조 가능했다.
- **함정 확인 결과**: `getNotificationChannels`는 저장소 전체에서 정의부 외 호출부가
  0건(grep 확인) — 계획서가 우려했던 "다른 파일에서 채널 생성 로직이 호출"하는
  경우는 실제로는 없었다. `isSamsungOneUi()`는 `BusAlertAutoAlarmNotifier.kt`(같은
  패키지)에서 호출 중 — 같은 패키지라 import 없이 그대로 컴파일됨.
  `NotificationDismissReceiver`도 저장소 어디서도(매니페스트 포함) 참조되지 않는
  걸 확인했으나, 계획 범위가 "이동"이지 "삭제 판단"이 아니므로 그대로 옮겼다(죽은
  코드 삭제는 `private` 한정이라는 계획서 기준에도 해당 안 됨 — public 클래스).
- 검증: `gradlew`가 저장소에 없어(`.gitignore` 대상) 캐시된 Gradle 8.11.1 배포판을
  `--project-dir android`로 직접 호출해 `:app:compileDebugKotlin` 통과 확인.
- `BusAlertService.kt`: 1,620 → 1,563줄 (계획서 완료 기준 "≤ ~1,565줄" 충족).
  `BusAlertModels.kt` 신규 69줄. 커밋 `9bf8b2d`.
- 다음 세션은 1b-2(취소 로직 → `BusAlertTrackingManager`, ~130줄)로 진행하면 된다.

## 2026-07-28 (2차): BusAlertService.kt 추가 축소 — 1b-2 완료 (취소 로직 → BusAlertTrackingManager)

`docs/refactoring-plan.md` 작업 1b의 1b-2 단계를 완료했다. `cancelOngoingTracking`/
`cancelNotification`/`cancelAllNotifications`/`stopTrackingIfIdle`/
`sendAllCancellationBroadcast`를 `BusAlertTrackingManager`로 이관했다.

- **새 콜백 0개로 끝남**: 이동 대상 5개 함수가 필요로 하는 의존성(`service`,
  `activeTrackings`/`monitoredRoutes`/`monitoringJobs`,
  `isInForegroundProvider`/`setInForeground`, `ongoingNotificationId`/
  `autoAlarmNotificationId`, `checkAndStopServiceIfNeeded`)이 작업 1의 2단계에서
  이미 생성자에 다 들어가 있었다 — 계획서가 우려한 "콜백 10개 이상 추가" 신호는
  발생하지 않았다.
- `sendAllCancellationBroadcast`는 기존에 콜백 파라미터(`sendAllCancellationBroadcast:
  () -> Unit`)로 주입되고 있었는데, 함수 본체를 `BusAlertTrackingManager` 안으로
  옮기면서 그 콜백 파라미터 자체를 제거했다 — 클래스 내부 호출(`stopAllTracking()`
  안의 601행)은 이제 로컬 멤버 함수로 자동 resolve되어 diff 없이 그대로 컴파일됨.
  생성자 호출부 2곳(`onCreate`/`initialize`)에서 `::sendAllCancellationBroadcast`
  인자만 제거.
- **함정 확인 결과**: `cancelOngoingTracking`은 `BusApiChannelHandler.stopBusTracking`이
  `activity.busAlertService?.cancelOngoingTracking()`로 외부 호출 중이라(grep 확인)
  공개 시그니처를 유지하고 위임 스텁만 남겼다. `cancelNotification`/
  `cancelAllNotifications`는 계획서가 우려한 대로 public이지만, 실제로는 채널
  핸들러의 동명 메서드(`cancelOngoingTracking(result)`/`cancelAllNotifications(result)`)가
  이 서비스 메서드를 호출하는 게 아니라 `stopAllBusTracking()`을 직접 호출하고
  있어서 — 외부 호출부는 0건이었다. 그래도 작업 1의 선례(외부 호출부 0건인 public
  메서드도 삭제 대신 위임 스텁 유지)를 따라 스텁을 남겼다.
- `stopTrackingIfIdle`/`sendAllCancellationBroadcast`는 원래 `private`였고 서비스
  내부 호출부만 있어서(각각 2곳) 스텁 없이 호출부를 `trackingManager.X()`로 직접
  바꿨다. 두 함수 모두 매니저 안에서는 `internal`로 선언 — cross-class 호출은
  여전히 필요하지만 앱 외부에 노출할 이유는 없어서.
- **죽은 코드 발견**: 계획서 대상 목록의 `checkAndStopService()`(1212행, `checkAndStopServiceIfNeeded`와는
  별개 함수)가 저장소 전체에서 정의부 외 호출부 0건임을 grep으로 확인했다 — `private`
  + 참조 0건이라 공통 원칙의 죽은 코드 삭제 기준에 정확히 해당한다. 계획서는 이
  함수를 "이관 대상"으로 적어뒀지만, 이관 대신 삭제했다(이관은 사용되지 않는
  로직을 그대로 다른 파일로 옮기는 것뿐이라 가치가 없음). 삭제 사실을 커밋 메시지에
  명시했다.
- 검증: `git show HEAD:...`로 원본 5개 함수 본문과 새 위치를 정규화(참조 치환 역변환)
  후 diff 대조 — 이동 외 변경 없음 확인. `:app:compileDebugKotlin` 통과.
- `BusAlertService.kt`: 1,563 → 1,444줄 (계획서 완료 기준 "≤ ~1,435줄"에는 9줄
  못 미쳤음 — 이관 코드에 붙인 "어디서 이관됐는지" 주석 몇 줄 때문. 실질적 로직
  이동은 계획대로 끝났다). `BusAlertTrackingManager.kt`: 705 → 822줄. 커밋 `9c35604`.
- 다음 세션은 1b-3(도착 확인/추적정보 갱신 클러스터 → 신규 협력 클래스, ~340줄,
  실기기 검증 중요)로 진행하면 된다.

## 2026-07-28 (3차): BusAlertService.kt 추가 축소 — 1b-3 완료 (도착 확인/추적정보 갱신 클러스터 → BusAlertTrackingManager)

`docs/refactoring-plan.md` 작업 1b의 1b-3 단계를 완료했다. `updateBusInfo`/
`updateBusInfoFromFlutter`/`checkNextBusAndNotify`/`checkArrivalAndNotify`/
`updateTrackingInfoFromFlutter`를 이관했다.

- **신규 파일 대신 기존 클래스 확장**: 계획서가 지시한 대로 "겹치는 협력 클래스가
  있는지" 먼저 확인했더니, 이동 대상 5개 중 3개(`updateBusInfo`,
  `checkArrivalAndNotify`, `checkNextBusAndNotify`)가 이미 `BusAlertTrackingManager`의
  추적 루프(`startTrackingInternal`) 안에서 콜백(`::updateBusInfo` 등)으로 호출되고
  있었다 — `BusAlertArrivalMonitor.kt`라는 새 파일 대신 `BusAlertTrackingManager`를
  확장하는 게 명백히 맞는 선택이었다.
- **콜백 3개 제거, 4개 신설**: 이동 대상 함수들이 이미 생성자에 있던 콜백
  (`updateBusInfo`/`checkArrivalAndNotify`/`checkNextBusAndNotify` 콜백 자체)을
  이관 후 셀프 호출로 대체할 수 있어 제거했다(1b-2의 `sendAllCancellationBroadcast`와
  같은 패턴). 대신 이전까지 서비스 밖으로 나갈 통로가 없던 의존성 4개를 새로
  추가했다: `notificationHandler`(`buildOngoingNotification` 호출용),
  `restartPreventionDurationMs`, `lastManualStopTimeProvider`(기존엔 setter만
  있고 getter가 없었음), `alertOnArrivalOnlyProvider`. 순증가 1개로 계획서가
  경계했던 "콜백 10개 이상" 신호와는 거리가 멀었다.
- `MAX_CONSECUTIVE_ERRORS` 상수(companion object, `private`)가 `updateBusInfo`의
  유일한 사용처였다 — 이관하면서 `BusAlertTrackingManager`의 companion object에
  새로 선언하고 `BusAlertService`에서는 삭제했다.
- Public 메서드(`updateBusInfoFromFlutter`/`updateTrackingInfoFromFlutter`)는
  각각 `BusApiChannelHandler`/`BusTrackingChannelHandler`가 외부에서 호출하므로
  위임 스텁 유지. `updateTrackingInfoFromFlutter`의 서비스 내부 호출부 2곳은
  이미 public 스텁을 그대로 호출하는 형태라 수정 불필요했다. `updateBusInfo`는
  `private`였고 내부 호출부가 `onStartCommand` 안에 1곳 있어 `trackingManager.
  updateBusInfo(...)`로 직접 교체(스텁 없음, 1b-2와 같은 판단).
- 검증: `git show HEAD:...`로 원본 5개 함수 본문과 새 위치를 정규화(참조 치환
  역변환) 후 diff 대조 — private→fun 가시성 변경, 콜백/프로바이더 치환, trailing
  공백 정리 외에는 차이 없음 확인. `:app:compileDebugKotlin` 통과.
- `BusAlertService.kt`: 1,444 → 1,101줄 (계획서 완료 기준 "≤ ~1,095줄"에는 6줄
  못 미쳤음 — 1b-1/1b-2와 같은 이유, 이관 출처 주석). `BusAlertTrackingManager.kt`:
  822 → 1,195줄. 커밋 `50f6095`.
- **실기기 미검증**: 이 클러스터는 TTS 발화와 알림 갱신을 실제로 트리거하는
  지점이라 devlog 2026-07-25 (3차)가 남긴 확인 목록("알림 렌더링", "stationId
  보정 재시도", "1초 후 백업 notify()")이 여전히 유효하다. 오케스트레이터가 adb로
  이어서 확인하기로 하고, 이 세션은 코드 이동 완료를 기준으로 넘어간다.
- 다음 세션은 1b-4(onStartCommand 디스패치 본문 축소, ~390줄, 고위험) 진행 여부를
  판단하면 된다 — 1b-1~3 합계로 목표(~1,200줄)를 이미 달성했으므로(1,101줄),
  계획서에 따르면 1b-4는 필수가 아니다.

## 2026-07-28 (4차): 작업 1b — 1b-4 보류 확정 (사용자 확인)

사용자가 1b-4(onStartCommand 디스패치 본문 축소)를 스킵하기로 확인했다 — 1b-1~3
완료로 목표(~1,200줄)를 이미 달성(1,101줄)했고, foreground 서비스 시작 타이밍에
직결된 가장 위험한 변경을 지금 굳이 할 이유가 없다는 판단. `refactoring-plan.md`
1b-4 체크박스는 미완료로 남기고(예정에 없음), 상단 작업 목록의 "작업 1b" 한 줄만
갱신했다.

## 2026-07-28 (5차): BusAlertService.kt 1b 실기기 검증 (수동 알람 시작/중지)

`1.0.4+66` 릴리스 서명 APK(main, 1b-1~3 병합 후)를 Galaxy Note10+(`R3CM70K2YZD`)에
sideload 설치해 devlog 2026-07-25 (3차)에 남긴 실기기 검증 목록 중 두 항목을
확인했다.

### 방법
- 즐겨찾기 버스 623번 행의 알람 종(🔔) 아이콘을 탭해 수동 승차 알람 시작 →
  같은 아이콘을 다시 탭해 중지.
- `adb shell dumpsys notification --noredact`로 알림 내용과 취소 여부,
  `adb shell dumpsys activity services`로 서비스 foreground 상태,
  `adb logcat -d *:E`로 크래시 여부를 확인.

### 결과
- **알림 렌더링**: 시작 직후 `bus_tracking_ongoing` 채널에 `title="623번 8분"`,
  `text="새동네아파트앞 · 8분 [성북시장앞]"`, 액션 "추적 중지" 알림이 정상
  게시됨 (`updateBusInfo`/`checkArrivalAndNotify`/`updateTrackingInfoFromFlutter`
  클러스터가 1b-3에서 `BusAlertTrackingManager`로 이동한 뒤에도 정상 동작).
- **수동 알람 중지** (`stopSpecificTracking`, 1b-2에서 이동): 종 아이콘 재탭 →
  "623번 승차 알람이 해제되었습니다" 토스트, `dumpsys notification`에서 id=1
  알림이 활성 목록에서 사라지고 `mArchive`에만 남음(정상 취소) 확인.
- **고아 포그라운드 서비스 아님**: 중지 후 `dumpsys activity services`에서
  `BusAlertService`가 `startRequested=false`로, `MainActivity`의 일반
  `bindService` 연결만 남고 foreground 상태가 아님을 확인.
- `adb logcat -d *:E`에 `daegubus` 관련 FATAL/에러 없음(SELinux audit·광고 SDK
  경고만 있었고 무관함).

### 아직 안 함
- 전체 알람 중지(브로드캐스트/앱 스와이프 종료 경로), 자동알람 시작·타임아웃·
  중복방지·중지, stationId 보정 재시도, 1초 후 백업 `notify()`, 취소 탭 연타
  — devlog 2026-07-25 (3차) 목록에서 이 항목들은 여전히 미확인 상태다.

## 2026-07-28 (6차): BusAlertService.kt 1b 실기기 검증 — 전체 중지·취소 연타·앱 종료

`1.0.4+66`(1b-1~3 병합본) sideload 상태에서 devlog 2026-07-25 (3차) 목록의
잔여 항목 일부를 Galaxy Note10+(`R3CM70K2YZD`)에서 추가로 확인했다.

### 전체 알람 중지 (다중 추적 → 알림 액션 경유)
- 623번·304번 두 알람을 동시에 걸어 `bus_tracking_ongoing` 알림 1개에
  InboxStyle 2줄(`623 (새동네아파트앞): 22분 [...]`, `304 (새동네아파트앞): 26분
  [...]`)로 병합 표시됨을 확인 — `updateBusInfo`류 클러스터가 다중 노선을
  올바르게 합산한다.
- 알림의 "추적 중지" 액션(단일 버튼, `stopAllTracking()` 경유)을 탭해 두 알람이
  한 번에 정리됨을 확인: `dumpsys notification`에서 id=1 알림 0건,
  `dumpsys activity services`에서 `BusAlertService`가 `startRequested=false`로
  전환(고아 포그라운드 없음), `logcat -d *:E`에 관련 에러 없음.

### 취소 액션 연타
- 알림의 "추적 중지"를 좌표 재탭(빠른 연속 2회)한 뒤 에러 없음, 알림도 정상
  0건으로 정리됨을 확인. `sentCancellationEvents`/`eventTimeouts` 기반 dedup이
  로그에 직접 잡히진 않았지만 부작용(중복 에러, 알림 잔류)은 관찰되지 않았다.

### 앱 스와이프 종료 — 체크리스트 항목 자체가 틀렸었다
- 알람 진행 중 최근 앱 화면에서 앱 카드를 위로 스와이프해 태스크를 제거한 뒤에도
  알림(`id=1`)이 그대로 남아있고, `BusAlertService`가 동일 PID(`30520`)로 계속
  foreground 상태(`startForegroundCount` 증가, `PROC_STATE_TOP` 아님에도 유지)임을
  확인했다.
- `BusAlertService.kt`/`MainActivity.kt` 전체에 `onTaskRemoved` 오버라이드가
  없음을 grep으로 확인 — 앱을 스와이프해도 추적을 멈추는 코드 경로 자체가
  없다. 이는 버그가 아니라 "앱을 닫아도 실시간 추적 알림은 계속된다"는 의도된
  동작(음악 재생 앱과 동일한 패턴)이다.
- **정정**: devlog 2026-07-25 (3차)와 refactoring-plan.md 1b-3 섹션에 적힌
  "앱 스와이프 종료(onDestroy) 경로"는 실제로 존재하지 않는 경로에 대한 잘못된
  가정이었다. `stopAllTracking`의 실제 호출 경로는 (a) UI/알림 액션 (b) 향후
  `ACTION_STOP_TRACKING` 인텐트(같은 앱 프로세스 내부에서만, 서비스가
  `exported=false`라 adb로 직접 트리거는 불가) 2가지뿐이며, "앱 종료"는
  트리거가 아니다.

### 아직 안 함
- 자동알람 시작·타임아웃·중복방지·중지: 기존 자동알람이 17:25(당일 기준 약
  1시간 이상 뒤) 예약이라 실제 트리거를 기다리는 대신 스킵했다. 다음에 실기기
  검증을 이어가려면 트리거 임박한 시각의 자동알람을 새로 등록하거나, 자동알람
  트리거 시각에 세션을 맞출 것.
- stationId 보정 재시도 경로: 재현할 특정 엣지케이스 정류장을 특정하지 못해
  스킵. 1초 후 백업 `notify()`는 육안으로 깜빡임 없음을 육안 확인했으나 로그
  기반 확증은 아니다.

## 2026-07-28 (7차): BusAlertService.kt 1b 실기기 검증 — 자동알람 시작/도착임박/중지

새 자동알람을 등록하려던 중, 기존에 등록돼 있던 623번(평일 17:25, 출근/스피커)
자동알람이 화면상 라벨과 무관하게 **실시간 ETA 기준으로 16:32에 동적으로
발동**하는 것을 실시간으로 관찰해 그대로 검증에 활용했다.

### "설정된 자동 알림이 없습니다"는 데이터 손실이 아니었다
- 발동 직후 `버스 알람` 탭이 빈 목록으로 바뀌어 처음엔 데이터 유실(리팩토링
  회귀)을 의심했다. `adb shell dumpsys notification`/`dumpsys activity
  services`로 확인한 결과, 실제로는 `id=1` 추적 알림과 `TTSService`(`id=1002`)가
  모두 정상 기동 중이었다 — 즉 알람이 "예약 대기" 상태에서 "활성 추적" 상태로
  전환되면서 설정 목록에서 빠진 것뿐이었다. `BusAlertService.kt`/
  `MainActivity.kt`에 데이터 삭제 로직은 없다.

### 자동알람 시작
- `SamsungAlarmManager`가 `com.devground.daegubus.AUTO_ALARM`을 16:32:22에
  발송 → `AlarmReceiver` 수신 → `BusAlertService` foreground 시작
  (`startForegroundCount` 4→6) 확인. `logcat -d *:E`에 관련 에러 없고
  `ForegroundServiceDidNotStartInTimeException`/ANR도 없어 5초 제한 안에
  정상 기동했다고 판단.
- 알림 `title="623번 5분"`, `text="새동네아파트앞 · 5분 [대구시산격청사건너1]"`,
  동시에 `tts_service_channel` 알림도 함께 떠 "출근(스피커)" 모드의 TTS 분기가
  정상 진입함을 확인.
- 홈 화면 배너/벨 아이콘에는 반영되지 않았다 — `handleAutoAlarmLightweight`라는
  이름이 시사하듯 자동알람은 네이티브 전용 경량 추적이라 Flutter UI 상태와
  동기화하지 않는 설계로 보인다(버그로 보지 않음, 다음에 Flutter 쪽 코드로
  교차 확인 권장).

### 도착 임박 TTS 트리거
- 몇 분 뒤 알림이 `"623번 곧 도착"`으로 갱신되고 별도의 `"자동알람 음성 안내"`
  알림(`자동알람 음성 안내 중`)이 뜨는 것을 확인 — `checkArrivalAndNotify`
  (1b-3에서 `BusAlertTrackingManager`로 이동) 기반 도착임박 트리거가 정상
  작동한다.

### 자동알람 중지
- 알림의 "추적 중지"를 탭하자 `com.devground.daegubus.action.STOP_TRACKING`
  인텐트가 `BusAlertService`에 전달됐고(logcat 확인), `id=1` 추적 알림은
  즉시 정상 취소됐다. `startRequested=false`로 전환도 확인.

### 범위 밖 관찰 — TTS 반복 안내 서비스 잔류 (이번 리팩토링과 무관)
- `id=1002` TTS 알림("자동알람 음성 안내 중")은 추적 중지 후 30초 넘게
  사라지지 않았다. `dumpsys activity services`로 보면 `TTSService`가
  `intent={act=REPEAT_TTS_ALERT ...}`로 여전히 foreground 상태였다 — 도착임박
  음성 안내를 반복 재생하는 별도 서비스/타이머가 `BusAlertService`의 추적 중지
  신호를 받지 않는 것으로 보인다.
- `TTSService.kt`는 작업 1/1b 어느 단계에서도 옮기거나 수정하지 않은 파일이라,
  이번 리팩토링이 만든 회귀는 아닐 가능성이 높다(사전 존재 이슈 추정). 확인을
  위해 `adb shell am force-stop com.devground.daegubus`로 기기 상태를
  정리했다.
- **후속 조사 필요**: `TTSService`의 `REPEAT_TTS_ALERT` 스케줄이
  `stopSpecificTracking`/`stopAllTracking`과 별도로 취소돼야 하는지 코드
  검토 필요. `docs/topics/tts-audio.md`와 `TTSService.kt`를 다음 세션에서
  확인할 것.

### 남은 미검증 항목
- 자동알람 타임아웃(무응답 시 자동 정리), 중복 트리거 방지(`pendingAutoAlarms`),
  stationId 보정 재시도는 여전히 미확인.
