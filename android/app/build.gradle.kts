plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.easync"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.nortify.easync"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a")
        }

        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DANDROID_STL=c++_shared"
                )
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../lib/CMakeLists.txt")
        }
    }
}

flutter {
    source = "../.."
    // Use the app's actual Flutter entrypoint
    target = "lib/ui/main.dart"
}

dependencies {
    // No Java-level ONNX Runtime dependency required; native code links against
    // the ONNX Runtime libraries provided via `ORT_ROOT` for native builds.
}

// If you need to package a prebuilt `libeasync_ai.so`, add a copy task here.
// Currently the native library is built via CMake (externalNativeBuild), so
// pre-copying is disabled to avoid duplicate native libs during packaging.
