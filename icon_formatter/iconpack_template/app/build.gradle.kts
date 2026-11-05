plugins {
    id("com.android.application")
}

// Filled in by Icon Formatter (gradle -P...):
val packId = (project.findProperty("packId") as String?) ?: "com.iconformatter.pack.generated"
val packName = (project.findProperty("packName") as String?) ?: "Icon Formatter Pack"
val packVersionCode = ((project.findProperty("packVersionCode") as String?) ?: "1").toInt()
val packVersionName = (project.findProperty("packVersionName") as String?) ?: "1.0"
val packAccent = (project.findProperty("packAccent") as String?) ?: "#BA4CD4"

android {
    namespace = "com.iconformatter.pack"
    compileSdk = 36

    defaultConfig {
        applicationId = packId
        minSdk = 24
        targetSdk = 36
        versionCode = packVersionCode
        versionName = packVersionName
        resValue("string", "app_name", packName)
        // accent colour of Icon Formatter (Impostazioni › Aspetto)
        resValue("string", "accent", packAccent)
    }

    buildFeatures {
        resValues = true
        buildConfig = false
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // resources must keep their names: launchers look icons up by name
            isShrinkResources = false
            // signed with the local debug key: installable by side-loading
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    androidResources {
        // launchers read appfilter.xml from assets/ as plain text
        noCompress += listOf("xml", "json")
    }
}
