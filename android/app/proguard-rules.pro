# Flutter 및 플러그인 관련 클래스 보존
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }

# 메소드 채널 보존
-keepclassmembers class * {
    @io.flutter.plugin.common.MethodChannel.Method *;
}

# 앱 코드 보존
-keep class com.example.daegu_bus_app.** { *; }

# 모델 클래스 보존
-keep class com.example.daegu_bus_app.models.** { *; }
-keep class com.example.daegu_bus_app.BusApiService { *; }
-keep class com.example.daegu_bus_app.BusAlertService { *; }
-keep class com.example.daegu_bus_app.DatabaseHelper { *; }

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