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

# 예외 클래스 유지
-keep public class * extends java.lang.Exception