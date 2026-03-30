plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.nortify.easync"
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

        manifestPlaceholders["largeHeap"] = "true"

        ndk {
            abiFilters += listOf("arm64-v8a")
        }

        externalNativeBuild {
            cmake {
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                    "-DORT_ROOT=${rootDir}/../../lib/thirdParty/onnxruntime-android-1.20.1"
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

    // Inclui libonnxruntime.so no APK para que o app encontre em runtime
    sourceSets {
        getByName("main") {
            jniLibs.srcDirs(
                listOf("../../lib/thirdParty/onnxruntime-android-1.20.1/jni")
            )
        }
    }
}

flutter {
    source = "../.."
    target = "lib/ui/main.dart"
}

dependencies {}