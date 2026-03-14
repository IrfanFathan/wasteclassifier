plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Read optional opencv.sdk.path from local.properties so the developer
// can configure the OpenCV Android SDK path without touching this file.
val localProperties = java.util.Properties().also { props ->
    val f = rootProject.file("local.properties")
    if (f.exists()) f.inputStream().use(props::load)
}
val opencvSdkPath: String =
    localProperties.getProperty("opencv.sdk.path")
        ?: file("${rootDir}/../opencv").absolutePath

android {
    namespace = "com.example.wasteclassifier"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.wasteclassifier"
        // TFLite + camera requires at least API 21
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Only build for the two mainstream 64/32-bit ARM ABIs.
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }

        // Pass the OpenCV SDK path to CMake so CMakeLists.txt can locate
        // the OpenCV Android JNI headers and prebuilt .so files.
        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                arguments += "-DANDROID_STL=c++_shared"
                arguments += "-DOPENCV_SDK_DIR=${opencvSdkPath}"
            }
        }
    }

    // Required for TFLite: prevent native .so files from being compressed
    // so the runtime linker can load them directly from the APK.
    aaptOptions {
        noCompress += "tflite"
    }

    // Point to the CMakeLists.txt that builds libyolo_preprocess.so.
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

