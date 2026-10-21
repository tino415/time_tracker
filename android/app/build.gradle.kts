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

    testOptions {
        // Robolectric reads the merged resources: the widget layout it inflates,
        // widget_nothing_tracked, and the capability array WearContractTest
        // checks against WearBridge.CAPABILITY.
        unitTests.isIncludeAndroidResources = true
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

    testImplementation("junit:junit:4.13.2")
    // Supplies a real org.json and real resources: the android.jar on the unit
    // test classpath is stubs that throw, and half this module is JSON parsing.
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("androidx.test:core:1.6.1")
    // The Data Layer clients are abstract classes with non-public constructors,
    // so they cannot be hand-faked. Their Tasks are real ones from Tasks.for*.
    testImplementation("io.mockk:mockk:1.13.13")
    // Dispatchers.setMain, so WearBridge's Main-dispatcher scope runs inline.
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.7.3")

    constraints {
        // Robolectric pulls Conscrypt in transitively, and the version it asks
        // for ships no linux-aarch_64 native, which every test needs here.
        // 2.7.0 is the first that does — a floor, not a dependency of ours.
        testImplementation("org.conscrypt:conscrypt-openjdk-uber:2.7.0")
    }
}

// Robolectric downloads its Android runtime from inside the test JVM, where
// Conscrypt's aarch64 TLS fails the handshake. Gradle fetches it instead, and
// the tests run offline against that copy.
// Every test loads both: the sdk= pinned in src/test/resources/robolectric.properties,
// and the newest SDK this Robolectric knows.
val robolectricRuntimeVersions = listOf("14-robolectric-10818077-i7", "15-robolectric-12650502-i7")

val robolectricRuntimeDir = layout.buildDirectory.dir("robolectric-runtime")

val syncRobolectricRuntime by tasks.registering(Sync::class) {
    robolectricRuntimeVersions.forEach { version ->
        from(configurations.detachedConfiguration(dependencies.create("org.robolectric:android-all-instrumented:$version")))
    }
    into(robolectricRuntimeDir)
}

tasks.withType<Test>().configureEach {
    dependsOn(syncRobolectricRuntime)
    systemProperty("robolectric.offline", "true")
    systemProperty("robolectric.dependency.dir", robolectricRuntimeDir.get().asFile.absolutePath)
}
