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
    target = "lib/ui/main.dart"
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

android.applicationVariants.configureEach {
    val abiList = listOf("arm64-v8a", "armeabi-v7a", "x86_64")

    abiList.forEach { abi ->
        val abiName = abi.replace("-", "").replaceFirstChar { c -> c.uppercase() }
        val variantName = name.replaceFirstChar { c -> c.uppercase() }

        val buildDepsTask = tasks.register(
            "buildNativeDepsFor${abiName}${variantName}",
            Exec::class
        ) {
            group = "build"
            description = "Build native dependencies for $abi"
            workingDir = file("../../lib")
            commandLine = listOf("bash", "build.sh", "android", abi)
        }

        tasks.named("externalNativeBuild${variantName}").configure {
            dependsOn(buildDepsTask)
        }
    }
}

dependencies {}