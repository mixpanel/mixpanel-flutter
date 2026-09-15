import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension

plugins {
    id("com.android.library")
}

// See the analytics plugin: AGP 9 rejects org.jetbrains.kotlin.android, and
// android.builtInKotlin=false opts back out of AGP's built-in Kotlin.
val agpMajor = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.substringBefore('.').toInt()
val builtInKotlin = agpMajor >= 9 &&
    project.findProperty("android.builtInKotlin")?.toString() != "false"
if (!builtInKotlin) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

android {
    namespace = "com.mixpanel.flutter_session_replay"
    compileSdk = 36

    defaultConfig {
        minSdk = 21
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

}

// Configured through the extension container rather than the generated `kotlin { }` accessor:
// that accessor only exists when the Kotlin plugin is declared in the `plugins { }` block, and
// on AGP 8 we apply it imperatively above, so the accessor is not generated.
extensions.configure(KotlinAndroidProjectExtension::class.java) {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_11)
    }
}
