allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// AGP 9 built-in Kotlin 과도기 대응.
// android_alarm_manager_plus 5.1.1은 AGP major >= 9이면 kotlin-android 적용을 건너뛰고
// built-in Kotlin이 등록하는 KotlinAndroidProjectExtension을 곧바로 사용한다.
// 반면 device_info_plus / flutter_tts / package_info_plus / wakelock_plus /
// shared_preferences_android / webview_flutter_android 는 kotlin-android를 무조건 적용해
// built-in Kotlin과 충돌한다. 그래서 전역은 android.builtInKotlin=false로 두고
// 이 모듈에만 선택적으로 built-in Kotlin을 적용한다.
// 플러그인들이 모두 이전을 마치면 이 블록과 gradle.properties의 opt-out을 함께 제거할 것.
subprojects {
    if (name == "android_alarm_manager_plus") {
        apply(plugin = "com.android.built-in-kotlin")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
