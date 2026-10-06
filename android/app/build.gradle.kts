import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ------------------------------------------------------------------------------
// Google Maps Android API key — read from (in priority order):
//   1. android/local.properties   (git-ignored, local dev)  -> GOOGLE_MAPS_ANDROID_API_KEY
//   2. Environment variable       (CI, e.g. Codemagic)      -> GOOGLE_MAPS_ANDROID_API_KEY
// Injected into AndroidManifest.xml via the ${googleMapsApiKey} placeholder.
// Never hardcode the key in the manifest: it is version-controlled.
// ------------------------------------------------------------------------------
val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { load(it) }
    }
}

val googleMapsApiKey: String =
    localProperties.getProperty("GOOGLE_MAPS_ANDROID_API_KEY")
        ?: System.getenv("GOOGLE_MAPS_ANDROID_API_KEY")
        ?: ""

if (googleMapsApiKey.isEmpty()) {
    logger.warn(
        "[SwiftRide] GOOGLE_MAPS_ANDROID_API_KEY is not set. Google Maps will render " +
            "a blank canvas on Android. Add it to android/local.properties or the " +
            "environment. The in-app map engine toggle falls back to OpenStreetMap tiles."
    )
}

android {
    namespace = "com.dartnexuslab.swiftride"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Unique Application ID matching iOS bundle identifier
        applicationId = "com.dartnexuslab.swiftride"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Resolved above from android/local.properties or the environment.
        // Kept out of version control on purpose.
        manifestPlaceholders["googleMapsApiKey"] = googleMapsApiKey
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
    implementation("com.google.firebase:firebase-appcheck-playintegrity:18.0.0")
}
