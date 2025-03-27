# ===== Flutter 관련 규칙 =====
-keep class io.flutter.** { *; }
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }

# ===== 메서드 채널 및 앱 패키지 보존 =====
# 앱 패키지 전체 보존
-keep class com.example.daegu_bus_app.** { *; }

# 특히 중요한 클래스들 명시적 보존
-keep class com.example.daegu_bus_app.MainActivity { *; }
-keep class com.example.daegu_bus_app.BusAlertService { *; }
-keep class com.example.daegu_bus_app.NotificationDismissReceiver { *; }
-keep class com.example.daegu_bus_app.BusApiService { *; }
-keep class com.example.daegu_bus_app.DatabaseHelper { *; }

# 모델 클래스 보존 (이미 앱 패키지 전체 보존에 포함되지만 명시적으로 추가)
-keep class com.example.daegu_bus_app.models.** { *; }

# MethodChannel 클래스 보존
-keep class io.flutter.plugin.common.MethodChannel { *; }
-keep class io.flutter.plugin.common.MethodChannel$* { *; }
-keep class io.flutter.plugin.common.MethodCall { *; }
-keep class io.flutter.plugin.common.MethodCodec { *; }
-keep class io.flutter.plugin.common.StandardMethodCodec { *; }

# ===== 외부 라이브러리 보존 규칙 =====
# androidx.window
-keep class androidx.window.** { *; }
-dontwarn androidx.window.**

# Play Core
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# 보안 라이브러리
-keep class org.bouncycastle.** { *; }
-keep class org.conscrypt.** { *; }
-keep class org.openjsse.** { *; }
-dontwarn org.bouncycastle.jsse.**
-dontwarn org.conscrypt.**
-dontwarn org.openjsse.**

# OkHttp 및 Retrofit
-keep class okhttp3.** { *; }
-keep class okio.** { *; }
-keep class retrofit2.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# OkHttp 관련 규칙
-keepattributes Signature
-keepattributes *Annotation*
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Gson
-keep class com.google.gson.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }

# Jsoup
-keep class org.jsoup.** { *; }
-keep class org.jsoup.parser.** { *; }
-keep class org.jsoup.nodes.** { *; }
-keep class org.jsoup.select.** { *; }

# Jsoup 관련 규칙
-keep public class org.jsoup.** {
    public *;
}

# JSON 파싱 관련 규칙
-keep class org.json.** { *; }

# OkHttp/Retrofit 관련 규칙
-keepattributes Signature
-keepattributes *Annotation*
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**

# Gson 관련 규칙
-keep class com.google.gson.** { *; }

# 앱 모델 클래스 보존
-keep class com.example.daegu_bus_app.** { *; }

# JSON 파싱 관련 규칙
-keep class org.json.** { *; }

# SQLite
-keep class android.database.sqlite.** { *; }

# 코루틴
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**

# WorkManager
-keep class androidx.work.** { *; }

# AlarmManager
-keep class dev.fluttercommunity.plus.androidalarmmanager.** { *; }

# ===== 특수 규칙 =====
# 네이티브 메서드 보존
-keepclasseswithmembernames class * {
    native <methods>;
}

# JavaScript 인터페이스 보존
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Serializable 클래스 보존
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    !private <fields>;
    !private <methods>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# ===== 속성 및 최적화 설정 =====
# 중요 속성 보존
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes InnerClasses
-keepattributes Exceptions

# 코드 최적화 설정
-optimizations !code/simplification/arithmetic,!code/simplification/cast,!field/*,!class/merging/*
-optimizationpasses 5
-allowaccessmodification
-renamesourcefileattribute SourceFile

# 네트워크 관련 추가 보존 규칙
-keepclassmembers class com.example.daegu_bus_app.BusApiService {
    public * searchStations(java.lang.String);
    private * parseJsonBusRoutes(java.lang.String);
    private * convertToBusArrival(*, *);
}

# EUC-KR 인코딩 관련 클래스 보존
-keep class java.nio.charset.** { *; }
-keep class sun.nio.cs.** { *; }