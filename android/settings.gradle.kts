pluginManagement {
    fun toWslPath(path: String): String {
        val normalized = path
            .replace("\\", "/")
            .replace(Regex("/+"), "/")

        return if (normalized.matches(Regex("(?i)^[a-z]:/.*"))) {
            "/mnt/${normalized.substring(0, 1).lowercase()}/${normalized.substring(3)}"
        } else {
            normalized
        }
    }

    val flutterSdkPath = run {
        val properties = java.util.Properties()
        file("local.properties").inputStream().use { properties.load(it) }
        val flutterSdkPath = properties.getProperty("flutter.sdk")
        require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }

        val normalized = toWslPath(flutterSdkPath)
        val fallbackPath = flutterSdkPath.replace("\\", "/").trim().trimEnd('/')

        val candidatePaths = listOf(normalized, fallbackPath)
            .map { it.trim().trimEnd('/') }
            .filter { it.isNotBlank() }
            .distinct()

        val selectedPath = candidatePaths.firstOrNull { path ->
            val pluginLoader = "$path/packages/flutter_tools/gradle/src/main/scripts/native_plugin_loader.gradle.kts"
            file(pluginLoader).exists()
        } ?: candidatePaths.first()

        selectedPath
    }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    // 루트 build.gradle.kts에서 특정 모듈에만 선택 적용하기 위해 클래스패스에만 올린다.
    id("com.android.built-in-kotlin") version "9.0.1" apply false
    // AGP 9는 KGP 2.2.10에 런타임 의존한다. 낮은 버전을 선언하면 Gradle이 자동 승격하므로
    // 명시적으로 맞춰 둔다.
    id("org.jetbrains.kotlin.android") version "2.2.10" apply false
}

include(":app")
