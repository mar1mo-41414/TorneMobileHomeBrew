import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: credentials live outside the repository. Set the
// TMHB_KEY_PROPERTIES environment variable to a properties file with
// storeFile / storePassword / keyAlias / keyPassword entries to sign
// with the distribution key. Without it, the release build falls back
// to the debug key so the project still builds from a plain clone.
val tmhbKeyProperties = Properties()
val tmhbKeyPropertiesPath = System.getenv("TMHB_KEY_PROPERTIES")
val tmhbSigningAvailable =
    tmhbKeyPropertiesPath != null && file(tmhbKeyPropertiesPath).exists()
if (tmhbSigningAvailable) {
    FileInputStream(file(tmhbKeyPropertiesPath)).use { tmhbKeyProperties.load(it) }
}

android {
    namespace = "com.markun.tmhb"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    // libtmhb_fcntl: the JNI fcntl(2) bridge used by FcntlCompat in
    // MainActivity.kt (Os.fcntlInt is API 30+ only).
    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    if (tmhbSigningAvailable) {
        signingConfigs {
            create("release") {
                storeFile = file(tmhbKeyProperties.getProperty("storeFile"))
                storePassword = tmhbKeyProperties.getProperty("storePassword")
                keyAlias = tmhbKeyProperties.getProperty("keyAlias")
                keyPassword = tmhbKeyProperties.getProperty("keyPassword")
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.markun.tmhb"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // The standard edition's floor. The "tv" product flavor
        // below overrides it with its own lower value.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-apk-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Editions of the app (product flavors). "standard" is the
    // long-standing build — the values in defaultConfig above,
    // unchanged. "tv" is the Android TV / Fire TV edition: its
    // own applicationId (so the two editions can coexist on one
    // device), the TV entry point (build with
    // `flutter build apk --flavor tv -t lib/main_tv.dart`), and a
    // lower minSdk so Fire OS 6 / Android TV hardware below API
    // 29 can install it. 24 is the floor: the Flutter tool
    // migrates lower values back to flutter.minSdkVersion (24 in
    // Flutter 3.50), and flutter_secure_storage /
    // flutter_plugin_android_lifecycle also declare 24.
    flavorDimensions += "edition"

    productFlavors {
        create("standard") {
            dimension = "edition"
        }

        create("tv") {
            dimension = "edition"
            applicationId = "com.markun.tmhb.tv"
            minSdk = 24
        }
    }

    buildTypes {
        release {
            // Keeps the JNI entry point name in FcntlCompat resolvable
            // when R8 runs (see proguard-rules.pro).
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            // Sign with the distribution key when TMHB_KEY_PROPERTIES is
            // provided; otherwise fall back to the debug keys so that
            // `flutter run --release` works from a plain clone.
            signingConfig =
                if (tmhbSigningAvailable) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
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
