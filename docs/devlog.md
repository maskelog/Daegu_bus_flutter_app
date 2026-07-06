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
