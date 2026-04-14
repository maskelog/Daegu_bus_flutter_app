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
-keep class com.google.gson.** { *; }
-keep class org.jsoup.** { *; }

# 네트워크 라이브러리
-keep class okhttp3.** { *; }
-keep class retrofit2.** { *; }
-keep class okio.** { *; }

# 노티피케이션 관련 클래스
-keep class androidx.core.app.** { *; }

# Kotlin 관련 규칙
-keep class kotlin.** { *; }
-keep class kotlinx.** { *; }
-keepclassmembers class **$WhenMappings {
    <fields>;
}
-keepclassmembers class kotlin.Metadata {
    public <methods>;
}

# Enums 클래스 보존
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# 안드로이드 컴포넌트
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver

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
