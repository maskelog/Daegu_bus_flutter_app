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
