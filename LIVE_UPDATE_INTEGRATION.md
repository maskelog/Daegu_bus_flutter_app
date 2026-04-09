# Android 16 Live Update / 상태칩 적용 가이드

이 문서는 **Android 16(API 36)의 Live Update(= promoted ongoing notification)** 와
**상태칩(`setShortCriticalText`)** 을 다른 앱에서도 재사용할 수 있도록 정리한 범용 가이드다.

버스, 배달, 운동 추적, 타이머, 내비게이션처럼 **지속적으로 진행 상태를 보여줘야 하는 앱**에 그대로 응용할 수 있다.

---

## 1. 핵심 개념

Android 16 Live Update가 제대로 보이려면 아래 3가지를 함께 만족해야 한다.

1. **알림이 ongoing 상태**여야 함
2. **promoted ongoing 승격 요청**이 들어가야 함
3. **OS가 승격 가능한 알림이라고 판단**해야 함

상태칩은 그 위에 추가로,

- `setShortCriticalText("5분")`
- 짧고 즉시 이해 가능한 텍스트

가 필요하다.

---

## 2. 언제 쓰면 좋은가

추천 시나리오:

- 배달 도착까지 남은 시간
- 버스 / 지하철 / 택시 추적
- 주행 / 러닝 / 운동 진행 상태
- 타이머 / 카운트다운
- 파일 업로드 / 다운로드 진행 상황

비추천 시나리오:

- 단발성 알림
- 장기 보관용 일반 공지
- 실시간성이 약한 이벤트

---

## 3. 필수 준비 사항

### SDK / 라이브러리

- `compileSdk = 36`
- `targetSdk = 36`
- `androidx.core:core-ktx`는 Android 16 notification API를 지원하는 버전 사용
  - 실전에서는 `1.17.0+` 권장

### Manifest 권한

```xml
<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
<uses-permission android:name="android.permission.POST_PROMOTED_NOTIFICATIONS" />
```

설명:

- `POST_NOTIFICATIONS`: Android 13+ 일반 알림 권한
- `POST_PROMOTED_NOTIFICATIONS`: Android 16 Live Update 승격용 권한 선언

---

## 4. 가장 중요한 포인트: 채널을 앱 시작 시 미리 생성

이 부분이 빠지면 앱 설정의 알림 메뉴에서 **"실시간 정보(Live Updates)" 토글이 안 보일 수 있다.**

즉, **서비스 시작 시점이 아니라 앱 시작 시점**에 Live Update 채널을 먼저 생성하는 것이 안전하다.

```kotlin
private const val LIVE_UPDATE_CHANNEL_ID = "live_updates"

fun Context.ensureLiveUpdateChannel() {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

    val manager = getSystemService(NotificationManager::class.java)
    val channel = NotificationChannel(
        LIVE_UPDATE_CHANNEL_ID,
        "Live updates",
        NotificationManager.IMPORTANCE_DEFAULT,
    ).apply {
        description = "Shows real-time ongoing progress and status chip."
        lockscreenVisibility = Notification.VISIBILITY_PUBLIC
        setShowBadge(false)
    }

    manager.createNotificationChannel(channel)
}
```

권장 위치:

- `Application.onCreate()`
- 또는 `MainActivity.onCreate()` 초기화 루틴

---

## 5. 런타임 권한 / 승격 가능 여부 확인

```kotlin
fun Context.canPostNotifications(): Boolean {
    return if (Build.VERSION.SDK_INT >= 33) {
        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    } else {
        true
    }
}

fun Context.canPostPromotedNotifications(): Boolean {
    return NotificationManagerCompat.from(this).canPostPromotedNotifications()
}
```

확인 포인트:

- `POST_NOTIFICATIONS` 런타임 허용 여부
- `canPostPromotedNotifications()` 결과
- 기기 설정에서 앱별 Live Update 허용 여부

---

## 6. Live Update 알림 작성 템플릿

아래 예제는 **다른 앱에서도 재사용 가능한 최소 템플릿**이다.

```kotlin
@Suppress("NewApi")
fun Context.buildLiveUpdateNotification(
    title: String,
    body: String,
    chipText: String,
    progress: Int,
    contentIntent: PendingIntent,
): Notification {
    val style = Notification.ProgressStyle()
        .setProgress(progress)
        .setStyledByProgress(true)
        .setProgressSegments(
            listOf(
                Notification.ProgressStyle.Segment(progress).setColor(0xFF1976D2.toInt()),
                Notification.ProgressStyle.Segment((100 - progress).coerceAtLeast(0))
                    .setColor(0xFFE0E0E0.toInt()),
            ),
        )
        .setProgressPoints(
            listOf(
                Notification.ProgressStyle.Point(1).setColor(0xFF4CAF50.toInt()),
                Notification.ProgressStyle.Point(99).setColor(0xFFFF5722.toInt()),
            ),
        )

    return Notification.Builder(this, LIVE_UPDATE_CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_notification)
        .setContentTitle(title)
        .setContentText(body)
        .setContentIntent(contentIntent)
        .setOnlyAlertOnce(true)
        .setOngoing(true)
        .setCategory(Notification.CATEGORY_PROGRESS)
        .setVisibility(Notification.VISIBILITY_PUBLIC)
        .setStyle(style)
        .setProgress(100, progress, false)
        .setShortCriticalText(chipText)
        .setRequestPromotedOngoing(true)
        .build()
}
```

게시:

```kotlin
fun Context.postLiveUpdate(notificationId: Int, notification: Notification) {
    NotificationManagerCompat.from(this).notify(notificationId, notification)
}
```

---

## 7. 상태칩 텍스트 작성 규칙

상태칩 텍스트는 **아주 짧고 즉시 이해 가능**해야 한다.

좋은 예:

- `5분`
- `2정거장`
- `도착`
- `배송중`
- `3km`

주의:

- 너무 길면 잘리거나 표시 우선순위가 떨어질 수 있음
- 설명문 대신 핵심 상태만 넣는 것이 좋음
- 제목/본문에 상세 설명을 중복 제공하는 것이 안전함

예시 상태 모델:

```kotlin
enum class LiveState(
    val title: String,
    val body: String,
    val chipText: String,
    val progress: Int,
) {
    START("주행 시작", "목적지까지 이동 중입니다.", "시작", 5),
    MID("목적지까지 5분", "현재 정상 이동 중입니다.", "5분", 60),
    NEAR("곧 도착", "잠시 후 도착합니다.", "도착임박", 90),
    DONE("도착 완료", "이동이 완료되었습니다.", "도착", 100),
}
```

---

## 8. 실전에서 놓치기 쉬운 함정

### 8-1. `setColorized(true)` 사용 금지

실전에서 가장 많이 놓치는 부분 중 하나다.

`colorized` 알림은 Android 16에서 Live Update / 상태칩 승격 자격을 잃을 수 있다.

즉, 아래 코드는 피하는 것이 좋다.

```kotlin
.setColorized(true) // 사용하지 않는 것을 권장
```

### 8-2. 채널을 늦게 만들면 "실시간 정보" 토글이 안 보일 수 있음

- 서비스가 시작될 때만 채널 생성
- 사용자가 앱 설정에 먼저 진입

이 순서면 OS가 promoted channel을 아직 모르기 때문에 토글이 안 뜰 수 있다.

### 8-3. `IMPORTANCE_MIN` 사용 금지

채널 중요도가 너무 낮으면 승격 대상이 되지 않을 수 있다.

권장:

- `IMPORTANCE_DEFAULT`
- 또는 필요 시 `IMPORTANCE_HIGH`

### 8-4. `setOnlyAlertOnce(true)` 권장

Live Update는 자주 업데이트되므로 매번 소리/진동이 울리면 UX가 나빠진다.

### 8-5. `setOngoing(true)` 빠뜨리면 Live Update 취지와 맞지 않음

이 옵션이 빠지면 OS가 일반 알림처럼 취급할 가능성이 높다.

---

## 9. ProgressStyle 활용 팁

`Notification.ProgressStyle`은 진행률 기반 UI가 필요한 앱에 특히 적합하다.

추천 패턴:

- 진행 완료 구간: 브랜드 색상
- 남은 구간: 회색
- 시작점 / 도착점: 포인트로 강조
- 트래커 아이콘: 이동체(버스, 택배, 러너 등)에 맞는 아이콘 사용

활용 예:

- 버스: 출발 ~ 도착 사이 이동
- 배달: 픽업 ~ 배송 완료
- 운동: 목표 거리 진행률
- 파일 업로드: 전송률 표시

---

## 10. 설정 화면으로 이동시키기

사용자가 앱별 promotion 설정을 직접 열 수 있게 두면 디버깅과 UX에 도움이 된다.

```kotlin
fun Activity.openPromotionSettings() {
    val intent = Intent("android.settings.MANAGE_APP_PROMOTED_NOTIFICATIONS").apply {
        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
    }
    val fallback = Intent(Settings.ACTION_APP_NOTIFICATION_PROMOTION_SETTINGS).apply {
        putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
    }

    try {
        startActivity(intent)
    } catch (_: ActivityNotFoundException) {
        startActivity(fallback)
    }
}
```

---

## 11. 삼성 / 제조사 커스텀 OS에서 확인할 점

Samsung One UI 같은 커스텀 OS에서는 아래를 함께 봐야 한다.

- 앱 알림 권한 허용
- 앱별 `실시간 정보` 허용
- 개발자 옵션의 Live information 관련 토글

즉, **코드가 맞아도 기기 설정 때문에 상태칩이 숨겨질 수 있다.**

---

## 12. 구현 순서 추천

1. `compileSdk`, `targetSdk`를 36으로 올린다.
2. `POST_NOTIFICATIONS`, `POST_PROMOTED_NOTIFICATIONS`를 선언한다.
3. 앱 시작 시 Live Update 채널을 생성한다.
4. 권한 요청 및 `canPostPromotedNotifications()` 체크를 붙인다.
5. `Notification.Builder` + `ProgressStyle`로 ongoing 알림을 만든다.
6. `setShortCriticalText()`로 상태칩 텍스트를 넣는다.
7. `setRequestPromotedOngoing(true)`를 호출한다.
8. `setColorized(true)`는 넣지 않는다.
9. 실기기에서 설정 > 앱 > 알림 > `실시간 정보` 토글 노출 여부를 확인한다.
10. 상태칩, 잠금화면, 알림 카드가 모두 기대대로 갱신되는지 테스트한다.

---

## 13. 최종 체크리스트

- [ ] `compileSdk = 36`
- [ ] `targetSdk = 36`
- [ ] `POST_NOTIFICATIONS` 선언 및 허용
- [ ] `POST_PROMOTED_NOTIFICATIONS` 선언
- [ ] 앱 시작 시 NotificationChannel 생성
- [ ] 채널 중요도 `DEFAULT` 이상
- [ ] `setOngoing(true)`
- [ ] `setOnlyAlertOnce(true)`
- [ ] `setCategory(Notification.CATEGORY_PROGRESS)`
- [ ] `setVisibility(Notification.VISIBILITY_PUBLIC)`
- [ ] `setProgress(...)` 또는 `ProgressStyle` 적용
- [ ] `setShortCriticalText(...)`
- [ ] `setRequestPromotedOngoing(true)`
- [ ] `setColorized(true)` 미사용
- [ ] 실기기에서 앱별 `실시간 정보` 토글 확인

---

## 14. 운영 팁

- 상태칩이 안 보여도 알림 카드만으로 핵심 정보를 이해할 수 있게 설계한다.
- 상태칩 텍스트는 **짧게**, 본문은 **친절하게** 작성한다.
- 업데이트 주기가 짧은 경우 `setOnlyAlertOnce(true)`를 기본값처럼 생각하는 것이 좋다.
- 디버깅 시에는 권한, 채널 생성 시점, 제조사 설정을 먼저 확인한다.

이 가이드를 기반으로 하면 버스 앱뿐 아니라, **배달 / 이동 / 운동 / 진행률 기반 앱**에도 Live Update와 상태칩을 안정적으로 적용할 수 있다.
