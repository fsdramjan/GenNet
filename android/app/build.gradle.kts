plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.apptrack.app"

    compileSdk = 35
    ndkVersion = "28.2.13676358"

    defaultConfig {
        applicationId = "com.apptrack.app"

        minSdk = flutter.minSdkVersion
        targetSdk = 35

        versionCode = 1
        versionName = "1.0.0"
    }

 

sourceSets {
    getByName("main") {
        jniLibs.srcDirs("src/main/jniLibs")
    }
}

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    kotlinOptions {
        jvmTarget = "21"
    }

    kotlin {
        jvmToolchain(21)
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")

            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}



flutter {
    source = "../.."
}