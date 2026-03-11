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
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.20.1")
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.20.0")
}

// Ensure prebuilt AI native library is packaged: copy any built libeasync_ai.so
// from the project's `lib/ai/build` into the module jniLibs for the ABI we target.
val copyAIBinaries by tasks.registering(Copy::class) {
    val aiBuildDir = file("../../lib/ai/build")
    from(aiBuildDir) {
        include("**/libeasync_ai.so")
    }
    into(file("src/main/jniLibs/arm64-v8a"))
    doFirst {
        println("copyAIBinaries: copying libeasync_ai.so from $aiBuildDir to src/main/jniLibs/arm64-v8a")
    }
}

tasks.named("preBuild").configure {
    dependsOn(copyAIBinaries)
}
