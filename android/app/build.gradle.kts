import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.seshly"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.seshly"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            // Priority 1: Environment Variables (GitHub Actions)
            // Priority 2: key.properties file (Local PC)
            keyAlias = System.getenv("KEY_ALIAS") ?: (keystoreProperties["keyAlias"] as String?)
            keyPassword = System.getenv("KEY_PASSWORD") ?: (keystoreProperties["keyPassword"] as String?)
            storePassword = System.getenv("KEYSTORE_PASSWORD") ?: (keystoreProperties["storePassword"] as String?)
            
            val storePath = System.getenv("KEYSTORE_FILE") ?: (keystoreProperties["storeFile"] as String?)
            if (storePath != null) {
                storeFile = file(storePath)
            }
        }
    }

    buildTypes {
        getByName("release") {
            // Connects the build type to the signing config defined above
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}