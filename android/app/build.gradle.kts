plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseStorePath = providers.gradleProperty("DUKAAN_KEYSTORE_PATH")
    .orElse(providers.environmentVariable("DUKAAN_KEYSTORE_PATH")).orNull
val releaseStorePassword = providers.gradleProperty("DUKAAN_KEYSTORE_PASSWORD")
    .orElse(providers.environmentVariable("DUKAAN_KEYSTORE_PASSWORD")).orNull
val releaseKeyAlias = providers.gradleProperty("DUKAAN_KEY_ALIAS")
    .orElse(providers.environmentVariable("DUKAAN_KEY_ALIAS")).orNull
val releaseKeyPassword = providers.gradleProperty("DUKAAN_KEY_PASSWORD")
    .orElse(providers.environmentVariable("DUKAAN_KEY_PASSWORD")).orNull
val hasReleaseSigning = listOf(
    releaseStorePath, releaseStorePassword, releaseKeyAlias, releaseKeyPassword
).all { !it.isNullOrBlank() }

android {
    namespace = "com.dukaanpro.dukaan_pro"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.dukaanpro.dukaan_pro"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStorePath!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release", ignoreCase = true) } && !hasReleaseSigning) {
        throw GradleException(
            "Production signing is missing. Set DUKAAN_KEYSTORE_PATH, " +
                "DUKAAN_KEYSTORE_PASSWORD, DUKAAN_KEY_ALIAS and DUKAAN_KEY_PASSWORD " +
                "as environment variables or Gradle properties."
        )
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
