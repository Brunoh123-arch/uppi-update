import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val envProperties = Properties()
// Tenta obter o .env do diretório local do admin
var envFile = project.file("../../.env")
if (!envFile.exists()) {
    // Tenta obter o .env raiz como fallback
    envFile = project.file("../../../.env")
}

if (envFile.exists()) {
    envFile.bufferedReader().use { reader ->
        reader.forEachLine { line ->
            val trimmed = line.trim()
            if (trimmed.isNotEmpty() && !trimmed.startsWith("#")) {
                val parts = trimmed.split("=", limit = 2)
                if (parts.size == 2) {
                    val key = parts[0].trim()
                    val value = parts[1].trim().removeSurrounding("\"").removeSurrounding("'")
                    envProperties[key] = value
                }
            }
        }
    }
}

val googleMapApiKey = System.getenv("GOOGLE_MAP_API_KEY")
    ?: System.getenv("GOOGLE_MAPS_API_KEY")
    ?: envProperties.getProperty("GOOGLE_MAP_API_KEY")
    ?: envProperties.getProperty("GOOGLE_MAPS_API_KEY")
    ?: ""

android {
    namespace = "com.example.admin_panel"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.admin_panel"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAP_API_KEY"] = googleMapApiKey
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
