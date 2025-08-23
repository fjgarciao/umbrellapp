import java.util.Properties
import java.io.FileInputStream

// 1. Cargar key.properties de forma segura
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { fis ->
        keystoreProperties.load(fis)
    }
}

// 2. Plugins típicos de app Flutter
plugins {
    id("com.android.application")
    kotlin("android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 3. Config Android (ajusta namespace y versions si ya las tienes)
android {
    namespace = "com.fjgarciao.umbrellapp"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.fjgarciao.umbrellapp"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 4. Firma (Kotlin DSL)
    signingConfigs {
        create("release") {
            // Las props pueden venir de key.properties o de variables de entorno
            val storeFilePath = (keystoreProperties["storeFile"] as String?)
                ?: System.getenv("UMBRELLAPP_STORE_FILE")
            val storePwd = (keystoreProperties["storePassword"] as String?)
                ?: System.getenv("UMBRELLAPP_STORE_PASSWORD")
            val keyAliasVal = (keystoreProperties["keyAlias"] as String?)
                ?: System.getenv("UMBRELLAPP_KEY_ALIAS")
            val keyPwd = (keystoreProperties["keyPassword"] as String?)
                ?: System.getenv("UMBRELLAPP_KEY_PASSWORD")

            // Solo configura si hay datos (evita fallar en CI/Debug)
            if (!storeFilePath.isNullOrBlank()) {
                storeFile = file(storeFilePath)
            }
            storePassword = storePwd
            keyAlias = keyAliasVal
            keyPassword = keyPwd
        }
    }

    buildTypes {
        getByName("debug") {
            // Debug no necesita firma release
            isMinifyEnabled = false
        }
        getByName("release") {
            // 5. Vincula la firma release
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true

            // Si usas ProGuard/R8 custom:
            // proguardFiles(
            //     getDefaultProguardFile("proguard-android-optimize.txt"),
            //     "proguard-rules.pro"
            // )
        }
    }

    // (Opcional) Si tu proyecto Flutter requiere Java 17 explícito:
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

flutter {
    source = "../.."
}

// Dependencias típicas generadas por Flutter; respeta las que ya tengas
dependencies {
    implementation(kotlin("stdlib"))
}
