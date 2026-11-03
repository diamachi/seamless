import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val localSigningProperties = Properties()
val localSigningFile = rootProject.file("../.tools/android-signing.properties")
if (localSigningFile.exists()) {
    localSigningFile.inputStream().use { localSigningProperties.load(it) }
}
fun signingValue(environmentName: String, propertyName: String): String? {
    val environmentValue = System.getenv(environmentName)
    if (!environmentValue.isNullOrBlank()) return environmentValue
    return localSigningProperties.getProperty(propertyName)
}
val distributionKeystore = signingValue("SEAMLESS_ANDROID_KEYSTORE", "storeFile")

android {
    namespace = "dev.seamless.companion"
    compileSdk = 36

    defaultConfig {
        applicationId = "dev.seamless.companion"
        minSdk = 24
        targetSdk = 36
        versionCode = 23
        versionName = "0.6.13"
    }
    signingConfigs {
        if (distributionKeystore != null) {
            create("distribution") {
                storeFile = file(distributionKeystore)
                storePassword = signingValue("SEAMLESS_ANDROID_STORE_PASSWORD", "storePassword")
                keyAlias = signingValue("SEAMLESS_ANDROID_KEY_ALIAS", "keyAlias")
                keyPassword = signingValue("SEAMLESS_ANDROID_KEY_PASSWORD", "keyPassword")
            }
        }
    }
    buildTypes {
        debug { versionNameSuffix = "-dev" }
        release {
            isMinifyEnabled = false
            if (distributionKeystore != null) signingConfig = signingConfigs.getByName("distribution")
        }
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
kotlin {
    jvmToolchain(21)
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.10.01"))
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("com.google.zxing:core:3.5.4")
    implementation("androidx.camera:camera-camera2:1.6.2")
    implementation("androidx.camera:camera-lifecycle:1.6.2")
    implementation("androidx.camera:camera-view:1.6.2")
    testImplementation("junit:junit:4.13.2")
}
