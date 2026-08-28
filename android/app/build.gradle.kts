plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.otin.time_tracker"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.otin.time_tracker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Flutter's own default is 24. androidx.wear.watchface:watchface-complications-data-source
        // declares 26 (Wear OS 2.0) and the manifest merger refuses to lower it —
        // raising it here is a real, visible trade, not a suppression of that
        // check: one unflavoured APK means this floor now applies to the phone
        // build too, so Android 7.x devices (API 24-25) can no longer install.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Wear Data Layer (MessageClient / CapabilityClient), used by WearBridge on
    // both form factors — one APK serves the phone and the watch.
    implementation("com.google.android.gms:play-services-wearable:18.1.0")
    // Lets the bridge `await()` the Play Services Tasks instead of nesting
    // callbacks.
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.7.3")
    // Wear OS watch-face complication: ComplicationDataSourceService and
    // TimeDifferenceComplicationText, the mechanism that lets the watch face
    // render elapsed time itself instead of the app pushing one every tick.
    implementation("androidx.wear.watchface:watchface-complications-data-source:1.2.1")
}
