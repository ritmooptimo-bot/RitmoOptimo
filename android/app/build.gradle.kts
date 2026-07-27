plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.antigravity.ritmooptimo_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Requerido por flutter_local_notifications v17 (zonedSchedule/exact alarms).
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.antigravity.ritmooptimo_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // flutter_local_notifications persiste con Gson y R8 le borra las firmas
            // genéricas → TypeToken crash en el ScheduledNotificationBootReceiver →
            // la app NO cargaba tras actualizar (MY_PACKAGE_REPLACED) o reiniciar
            // (BOOT_COMPLETED). Desactivamos R8 en release (el proyecto ya compila con
            // --no-shrink en CI, así que no shrinkear es aceptable). NO usar
            // proguard-android-optimize: rompe la init de la app (se cuelga en el splash).
            // Alternativa futura: re-activar minify con proguard-rules.pro
            // (keeps de com.dexterous.** + Signature + TypeToken de Gson).
            isMinifyEnabled = false
            // Shrink de recursos requiere code-shrinking → al apagar R8 hay que
            // apagarlo también (si no, Gradle falla en la configuración).
            isShrinkResources = false
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
