import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.isFile) file.inputStream().use { load(it) }
}
fun signingValue(property: String, variable: String): String? =
    (System.getenv(variable) ?: signingProperties.getProperty(property))?.takeIf { it.isNotBlank() }

val reviewSigning = System.getenv("TAMREEDY_ANDROID_REVIEW_SIGNING") == "true"
val releaseRequested = gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }
val signingPath = signingValue("storeFile", "TAMREEDY_ANDROID_KEYSTORE")
val releaseFile = signingPath?.let { rootProject.file(it) }
val releaseStorePassword = signingValue("storePassword", "TAMREEDY_ANDROID_STORE_PASSWORD")
val releaseKeyPassword = signingValue("keyPassword", "TAMREEDY_ANDROID_KEY_PASSWORD")
val releaseAlias = signingValue("keyAlias", "TAMREEDY_ANDROID_KEY_ALIAS")
val hasStoreSigning = releaseFile?.isFile == true && releaseStorePassword != null &&
    releaseKeyPassword != null && releaseAlias != null
if (releaseRequested && !reviewSigning && !hasStoreSigning) {
    throw GradleException("Store release requires a valid external keystore and signing credentials. Use explicit review signing for internal testing only.")
}

android {
    namespace = "com.tamreedy.tamreedy_patient_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.tamreedy.patient"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasStoreSigning && !reviewSigning) {
            create("storeRelease") {
                storeFile = releaseFile
                storePassword = releaseStorePassword
                keyAlias = releaseAlias
                keyPassword = releaseKeyPassword
            }
        }
    }
    buildTypes {
        release {
            signingConfig = when {
                reviewSigning -> signingConfigs.getByName("debug")
                hasStoreSigning -> signingConfigs.getByName("storeRelease")
                else -> null
            }
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

// Firebase (push + analytics) activates only when the config file is present.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
