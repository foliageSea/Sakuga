import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val actionsSigning = System.getenv("GITHUB_ACTIONS") == "true"
val signingEnvironment = mapOf(
    "storeFile" to "ANDROID_KEYSTORE_PATH",
    "storePassword" to "ANDROID_KEYSTORE_PASSWORD",
    "keyAlias" to "ANDROID_KEY_ALIAS",
    "keyPassword" to "ANDROID_KEY_PASSWORD",
)
val keystoreProperties = Properties().apply {
    if (actionsSigning) {
        signingEnvironment.forEach { (property, variable) ->
            System.getenv(variable)?.let { setProperty(property, it) }
        }
    } else if (keystorePropertiesFile.isFile) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

// Keep debug builds available without credentials, but never publish an unsigned release.
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    doFirst {
        signingEnvironment.forEach { (property, variable) ->
            check(!keystoreProperties.getProperty(property).isNullOrBlank()) {
                if (actionsSigning) "Missing release signing variable: $variable"
                else "Missing release signing property: $property in android/key.properties"
            }
        }
        check(rootProject.file(keystoreProperties.getProperty("storeFile")).isFile) {
            if (actionsSigning) "Release keystore does not exist at ANDROID_KEYSTORE_PATH."
            else "Release keystore does not exist. Check storeFile in android/key.properties."
        }
    }
}

android {
    namespace = "com.foliage.sakuga"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.foliage.sakuga"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { rootProject.file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
