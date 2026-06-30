import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
  keystoreProperties.load(keystorePropertiesFile.inputStream())
}

val envProperties = Properties()
val envFile = project.file("../../.env")
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
    ?: envProperties.getProperty("GOOGLE_MAP_API_KEY")
    ?: ""

android {
    namespace = "online.uppi.rider"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    // jvmTarget is set at the bottom via KotlinCompile task configuration

    defaultConfig {
        applicationId = "online.uppi.rider"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAP_API_KEY"] = googleMapApiKey
    }

    signingConfigs {
        create("release") {
            val keyAliasStr = keystoreProperties["keyAlias"] as? String
            val keyPasswordStr = keystoreProperties["keyPassword"] as? String
            val storeFileStr = keystoreProperties["storeFile"] as? String
            val storePasswordStr = keystoreProperties["storePassword"] as? String

            if (!keyAliasStr.isNullOrEmpty() && !keyPasswordStr.isNullOrEmpty() && !storeFileStr.isNullOrEmpty() && !storePasswordStr.isNullOrEmpty()) {
                this.keyAlias = keyAliasStr
                this.keyPassword = keyPasswordStr
                this.storeFile = file(storeFileStr)
                this.storePassword = storePasswordStr
            }
        }
    }

    buildTypes {
        getByName("debug") {
            // Utiliza o debug.keystore padrão local cujas credenciais (SHA-1 44:C8:BA:...) 
            // já estão cadastradas e autorizadas no Firebase.
            // if (!keystoreProperties["storeFile"].toString().isNullOrEmpty()) {
            //     signingConfig = signingConfigs.getByName("release")
            // }
        }
        release {
            if (!keystoreProperties["storeFile"].toString().isNullOrEmpty()) {
                signingConfig = signingConfigs.getByName("release")
            }
            // 🔒 SEGURANÇA: Ativar R8 (ProGuard) + shrinkResources para dificultar engenharia reversa
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        // jniLibs {
        //     keepDebugSymbols += setOf("**/*.so")
        // }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
    implementation("androidx.credentials:credentials:1.3.0")
    implementation("androidx.credentials:credentials-play-services-auth:1.3.0")
    implementation("com.google.android.libraries.identity.googleid:googleid:1.1.1")
}

tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}

