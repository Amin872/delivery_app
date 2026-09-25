import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Google Maps SDK for Android key, read from the untracked
// android/local.properties (MAPS_API_KEY=...) so it never enters git. Falls
// back to a placeholder so the project still builds without one (map tiles
// then stay blank). The value is only substituted into the manifest; it's
// never logged.
val mapsApiKey: String = Properties().run {
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { load(it) }
    getProperty("MAPS_API_KEY")?.takeIf { it.isNotBlank() } ?: "YOUR_MAPS_API_KEY_HERE"
}

// Release signing. Non-secret settings (storeFile, keyAlias) come from the
// gitignored android/key.properties; the passwords come ONLY from the
// DELIVERY_APP_STORE_PASSWORD / DELIVERY_APP_KEY_PASSWORD environment
// variables, never from a file in the repository. The keystore itself lives
// outside the repository. Without all four values there is no release
// signing config, and release tasks fail (see the check at the end of this
// file) instead of falling back to the debug key.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val releaseStoreFile: String? = keystoreProperties.getProperty("storeFile")?.takeIf { it.isNotBlank() }
val releaseKeyAlias: String? = keystoreProperties.getProperty("keyAlias")?.takeIf { it.isNotBlank() }
val releaseStorePassword: String? = System.getenv("DELIVERY_APP_STORE_PASSWORD")?.takeIf { it.isNotEmpty() }
val releaseKeyPassword: String? = System.getenv("DELIVERY_APP_KEY_PASSWORD")?.takeIf { it.isNotEmpty() }
val hasReleaseSigning = releaseStoreFile != null && releaseKeyAlias != null &&
    releaseStorePassword != null && releaseKeyPassword != null

android {
    namespace = "com.deliveryapp.delivery_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.deliveryapp.delivery_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            // Only ever the release key — no debug-key fallback.
            signingConfig = if (hasReleaseSigning) signingConfigs.getByName("release") else null
        }
    }
}

flutter {
    source = "../.."
}

// Fail closed: any Release task (flutter build appbundle/apk --release,
// flutter run --release) stops with a clear error when release signing isn't
// configured, rather than producing a debug-signed or unsigned artifact.
// Debug and test builds never schedule Release tasks, so they're unaffected.
gradle.taskGraph.whenReady {
    if (!hasReleaseSigning && allTasks.any { it.name.contains("Release") }) {
        throw GradleException(
            "Release signing is not configured. Create the gitignored android/key.properties " +
                "(storeFile=<keystore path outside the repo>, keyAlias=<alias>) and set the " +
                "DELIVERY_APP_STORE_PASSWORD and DELIVERY_APP_KEY_PASSWORD environment variables."
        )
    }
}
