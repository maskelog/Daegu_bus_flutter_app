---
name: android-notifications
description: Android 알림 시스템 전문 스킬. Live Updates, ProgressStyle, Foreground Service 알림 구현. Android 16+ 신기능과 하위 버전 호환성 처리.
---

# Android Notifications Skill

Android 알림 시스템 구현 가이드.

## When to Use
- Foreground Service 알림 구현
- Live Update 알림 (Android 16+)
- Progress 알림
- 알림 채널 관리
- 하위 버전 호환성 처리

## Android 16 Live Updates

### 핵심 API (Reflection 사용)
```kotlin
// ProgressStyle - 진행 바 위 아이콘 이동
val progressStyleClass = Class.forName("android.app.Notification\$ProgressStyle")
val progressStyle = progressStyleClass.getConstructor().newInstance()

// setProgressTrackerIcon - 트래커 아이콘
val busIcon = Icon.createWithResource(context, R.drawable.ic_bus_tracker)
progressStyleClass.getMethod("setProgressTrackerIcon", Icon::class.java)
    .invoke(progressStyle, busIcon)

// setProgress - 진행도
progressStyleClass.getMethod("setProgress", Int::class.javaPrimitiveType)
    .invoke(progressStyle, progress)

// setRequestPromotedOngoing - Live Update 활성화
nativeBuilder.javaClass.getMethod("setRequestPromotedOngoing", Boolean::class.javaPrimitiveType)
    .invoke(nativeBuilder, true)

// setShortCriticalText - 상태 칩 텍스트
nativeBuilder.javaClass.getMethod("setShortCriticalText", CharSequence::class.java)
    .invoke(nativeBuilder, "5분")
```

### 하위 버전 호환성
```kotlin
val notification = if (Build.VERSION.SDK_INT >= 36) {
    // Android 16+: ProgressStyle + Live Update
    try {
        // ProgressStyle 사용
    } catch (e: ClassNotFoundException) {
        // Fallback: 일반 진행 바
        nativeBuilder.setProgress(max, progress, false)
    }
} else {
    // Android 15 이하: NotificationCompat
    NotificationCompat.Builder(context, CHANNEL_ID)
        .setProgress(max, progress, false)
        .build()
}
```

## Foreground Service 알림

```kotlin
// Android 14+ 타입 지정 필수
if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
    startForeground(NOTIFICATION_ID, notification,
        ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION)
} else {
    startForeground(NOTIFICATION_ID, notification)
}
```

## 알림 채널

```kotlin
val channel = NotificationChannel(
    CHANNEL_ID,
    "버스 추적",
    NotificationManager.IMPORTANCE_DEFAULT
).apply {
    description = "실시간 버스 추적"
    enableVibration(false)
    lockscreenVisibility = Notification.VISIBILITY_PUBLIC
}
```

## Guidelines
- SDK 버전 체크 필수
- Reflection 사용 시 예외 처리
- 하위 버전 fallback 항상 구현
- 알림 채널은 앱 시작 시 생성
