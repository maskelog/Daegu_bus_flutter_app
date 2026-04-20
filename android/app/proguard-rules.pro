# Flutter 엔진 전체를 keep 하면 사용하지 않는 deferred-components 경로까지
# 살아남아 옛 Play Core 참조가 릴리스 번들에 남는다.
# 이 앱은 deferred components를 사용하지 않으므로 R8이 미사용 경로를 제거하게 둔다.
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# WebView Flutter 플러그인 - JS↔Flutter 브릿지 보존
# mapEvent.postMessage() 등 JS→Flutter 채널이 릴리즈에서 끊기는 것 방지
-keep class io.flutter.plugins.webviewflutter.** { *; }
-keep class androidx.webkit.** { *; }
-keep class android.webkit.** { *; }
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# 메소드 채널 보존
-keepclassmembers class * {
    @io.flutter.plugin.common.MethodChannel.Method *;
}

# JSON 및 파싱 관련 클래스
-keep class org.json.** { *; }
# com.google.gson: v2.11.0+ 자체 consumer rules 포함 + 모든 data class에 @SerializedName 적용 → 수동 규칙 불필요
-keep class org.jsoup.** { *; }

# 네트워크 라이브러리
# okhttp3, retrofit2, okio: v2.9.0+/4.x 이상 자체 consumer rules 포함 → 수동 규칙 불필요

# 노티피케이션 관련 클래스
# androidx.core.app: AndroidX 자체 consumer rules 포함 → 수동 규칙 불필요

# Kotlin 관련 규칙
# kotlin.**, kotlinx.**: 자체 consumer rules 포함 → 수동 규칙 불필요

# Enums 클래스 보존
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# 안드로이드 컴포넌트
# Activity, Service, BroadcastReceiver: AndroidManifest.xml에 선언된 컴포넌트는
# AAPT2가 자동으로 keep → 수동 규칙 불필요

# Window Extensions 관련 클래스 (오류 해결)
-dontwarn androidx.window.extensions.**
-dontwarn androidx.window.sidecar.**

# SSL/TLS 관련 라이브러리
-dontwarn org.bouncycastle.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# 속성 보존
-keepattributes Exceptions,InnerClasses,Signature,Deprecated,SourceFile,LineNumberTable,*Annotation*,EnclosingMethod

# 릴리스에서는 Android Log 호출을 제거해 디버그 로그가 번들에 남지 않게 한다.
-assumenosideeffects class android.util.Log {
    public static int d(...);
    public static int v(...);
    public static int i(...);
    public static int w(...);
    public static int e(...);
}
