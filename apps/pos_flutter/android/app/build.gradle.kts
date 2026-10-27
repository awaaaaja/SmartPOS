plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Secret signing hanya dari environment lokal/CI, bukan source atau debug key.
val releaseStore = providers.environmentVariable("MEJENG_KEYSTORE_PATH").orNull

android {
    namespace = "com.waroengmejeng.pos_flutter"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.waroengmejeng.pos_flutter"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStore != null) {
            create("release") {
                storeFile = file(releaseStore)
                storePassword = providers.environmentVariable("MEJENG_STORE_PASSWORD").get()
                keyAlias = providers.environmentVariable("MEJENG_KEY_ALIAS").get()
                keyPassword = providers.environmentVariable("MEJENG_KEY_PASSWORD").get()
            }
        }
    }

    buildTypes {
        release {
            // Tanpa keystore hasilnya UNSIGNED: untuk verifikasi build, bukan instalasi.
            signingConfig = if (releaseStore != null) signingConfigs.getByName("release") else null
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
