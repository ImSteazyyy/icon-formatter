pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    // same AGP as Icon Formatter's own Android build (already in the Gradle cache)
    id("com.android.application") version "9.1.0" apply false
}

rootProject.name = "IconFormatterPack"
include(":app")
