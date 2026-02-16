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
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
