plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeystorePath = System.getenv("SLOWLIGHT_ANDROID_KEYSTORE_PATH")
val releaseKeyAlias = System.getenv("SLOWLIGHT_ANDROID_KEY_ALIAS")
val releaseStorePassword = System.getenv("SLOWLIGHT_ANDROID_STORE_PASSWORD")
val releaseKeyPassword = System.getenv("SLOWLIGHT_ANDROID_KEY_PASSWORD")
val hasReleaseSigning = listOf(
    releaseKeystorePath,
    releaseKeyAlias,
    releaseStorePassword,
    releaseKeyPassword,
).all { !it.isNullOrBlank() }

android {
    namespace = "site.z7ping.slowlight"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "site.z7ping.slowlight"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(releaseKeystorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Android 平台图标是已经人工验收并提交的最终静态资产；Release 构建直接保留原 PNG，
            // 避免 AAPT2 对已定稿 PNG 再次 crunch 时出现资源编译异常。
            isCrunchPngs = false

            // 本地没有配置发行密钥时仍允许开发者自构建；官方狗粮/Release Workflow
            // 会在构建前强制校验固定签名 Secret，避免不同 Runner 产生不可覆盖升级的 APK。
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}
