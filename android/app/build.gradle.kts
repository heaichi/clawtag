import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.heaichi.pet_diary"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.heaichi.pet_diary"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Load signing config from key.properties
    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    val signRelease = keystorePropertiesFile.exists()
    if (signRelease) {
        keystoreProperties.load(keystorePropertiesFile.inputStream())
    }

    // 统一使用正式上传签名：debug 和 release 保持同一把钥匙，
    // 这样 flutter run 的 debug 也能覆盖安装到真机并保留数据。
    val uploadSigningConfig = if (signRelease) {
        signingConfigs.create("upload") {
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
        }
    } else {
        null
    }

    buildTypes {
        debug {
            if (uploadSigningConfig != null) {
                signingConfig = uploadSigningConfig
            }
        }
        release {
            // 本应用依赖「运行期按名字查找资源」（flutter_local_notifications 的图标、
            // 插件渠道图标等），资源裁剪/优化会把它们当成未使用资源删掉 →
            // 真机上表现为 invalid_icon、所有提醒都不响。这里显式关掉，宁大一点。
            isShrinkResources = false
            if (uploadSigningConfig != null) {
                signingConfig = uploadSigningConfig
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
