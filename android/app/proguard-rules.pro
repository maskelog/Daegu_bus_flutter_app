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
# okhttp3, okio: 자체 consumer rules 포함 → 수동 규칙 불필요
#
# retrofit2 2.9.0의 consumer rules에는 R8 full mode 전용 규칙 3개가 빠져 있다
# (Retrofit 2.10.0에서 추가됨). BusInfoApi는 전부 suspend 함수라 마지막 파라미터가
# Continuation<? super BusArrivalResponse> 이고, full mode에서 이 타입들이 제거되면
# 제네릭 시그니처가 지워져 런타임에 도착정보 파싱이 통째로 실패한다.
# Retrofit 2.11+로 올리면 이 블록은 삭제 가능.
-keep,allowobfuscation,allowshrinking interface retrofit2.Call
-keep,allowobfuscation,allowshrinking class retrofit2.Response
-keep,allowobfuscation,allowshrinking class kotlin.coroutines.Continuation

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

# 릴리스에서는 verbose/debug/info 로그만 제거한다.
# Log.w(경고), Log.e(오류)는 릴리스에서도 유지하여 크래시 추적을 가능하게 한다.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
