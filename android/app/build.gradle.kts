import java.io.FileInputStream
import java.util.Properties

// Written by build_android.sh from the TP_KEYSTORE_* environment variables and
// deleted again afterwards, so the signing secrets never live in the repo.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "de.chrbayer.trip_planner"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "de.chrbayer.trip_planner"
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
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Falls back to the debug key so `flutter run --release` keeps
            // working without a keystore. Anything installed that way cannot
            // later be updated by a properly signed build - Android refuses a
            // signature change - so set TP_KEYSTORE_PATH before handing the
            // app to anyone.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

// Version codes for the universal APK and the APKs split by ABI
// (`flutter build apk --split-per-abi`): pubspec code * 10 plus a digit,
// 0 for the universal APK and 1-3 per ABI. A device picks the highest code it
// can run, so the digits climb with capability, and every later version
// outranks every variant of an earlier one - whichever APK is installed, the
// next release installs over it.
//
// Flutter would put abi * 1000 in front instead; the property turns that off
// so there is exactly one scheme.
extra["force-version-code-ignoring-abi"] = "true"

val abiDigits = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)

@Suppress("DEPRECATION")
(extensions.getByName("android") as com.android.build.gradle.AppExtension)
    .applicationVariants.all {
        val baseCode = versionCode
        outputs.all {
            val output = this as com.android.build.gradle.api.ApkVariantOutput
            val abi = output.getFilter(com.android.build.VariantOutput.FilterType.ABI)
            output.versionCodeOverride = baseCode * 10 + (abiDigits[abi] ?: 0)
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
