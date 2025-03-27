# androidx.window 관련
-keep class androidx.window.** { *; }
-keep class androidx.window.extensions.** { *; }
-keep class androidx.window.sidecar.** { *; }
-dontwarn androidx.window.**

# Play Core 라이브러리 관련
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# 보안 라이브러리 관련
-keep class org.bouncycastle.** { *; }
-keep class org.conscrypt.** { *; }
-keep class org.openjsse.** { *; }

# OkHttp 관련 규칙
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# Retrofit 관련
-keep class retrofit2.** { *; }
-keepattributes Signature
-keepattributes Exceptions

# Gson 관련
-keep class com.google.code.gson.** { *; }
-keep class com.example.daegu_bus_app.** { *; } # 앱 고유 패키지 유지
-keepclassmembers class com.example.daegu_bus_app.** {
    <fields>;
    <methods>;
}

# Jsoup 관련
-keep class org.jsoup.** { *; }

# SQLite 관련
-keep class android.database.sqlite.** { *; }

# 코루틴 관련
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# Flutter 관련
-keep class io.flutter.** { *; }
-keep class dev.fluttercommunity.plus.androidalarmmanager.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# 일반적인 Android 앱 규칙
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable

# Gson 관련 추가 규칙
# 제네릭 타입 서명을 유지 (이미 일부 규칙이 있으나, 명시적으로 TypeToken도 유지)
-keepattributes Signature
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class com.google.gson.** { *; }

# Gson으로 사용하는 데이터 모델 클래스들도 난독화되지 않도록 유지
-keep class com.example.daegu_bus_app.** { *; }
-keep class com.example.daegu_bus_app.**.model.** { *; }

# 예외 클래스 유지
-keep public class * extends java.lang.Exception

# 빌드 성능 개선 설정
-optimizations !code/simplification/arithmetic,!code/simplification/cast,!field/*,!class/merging/*
-optimizationpasses 5
-allowaccessmodification

# JavascriptInterface 어노테이션이 있는 메서드 보존
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# 앱 패키지의 모든 public 멤버 보존
-keepclassmembers class com.example.daegu_bus_app.** {
    public *;
}

# 필수 속성 보존
-keepattributes Signature,*Annotation*,SourceFile,LineNumberTable,Exceptions,InnerClasses

# 모델 클래스 명시적 보존 (추가)
-keep class com.example.daegu_bus_app.models.** { *; }
-keep class com.example.daegu_bus_app.** { *; }
-keepattributes Signature, *Annotation*

# R8 및 Proguard 최적화 조정
-dontobfuscate
-dontoptimize

-keep class com.example.daegu_bus_app.models.** { *; }
-keep class com.example.daegu_bus_app.** { *; }
