# ─────────────────────────────────────────────────────────────
#  android/app/proguard-rules.pro
#  PhaseOut — R8/ProGuard rules for release builds
# ─────────────────────────────────────────────────────────────

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.**

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# Firebase Crashlytics
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception
-keep class com.crashlytics.** { *; }
-dontwarn com.crashlytics.**

# TensorFlow Lite
-keep class org.tensorflow.** { *; }
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.**

# flutter_background_service
-keep class id.flutter.flutter_background_service.** { *; }
-dontwarn id.flutter.flutter_background_service.**

# flutter_local_notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-dontwarn com.dexterous.flutterlocalnotifications.**

# battery_plus
-keep class dev.fluttercommunity.plus.battery.** { *; }

# app_usage
-keep class io.github.willblaschko.android.appusage.** { *; }

# permission_handler
-keep class com.baseflow.permissionhandler.** { *; }

# sqflite
-keep class com.tekartik.sqflite.** { *; }

# Keep all model classes (prevent field stripping)
-keep class com.brightdev.phaseout.** { *; }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# Kotlin coroutines
-keepnames class kotlinx.coroutines.internal.MainDispatcherFactory {}
-keepnames class kotlinx.coroutines.CoroutineExceptionHandler {}
-dontwarn kotlinx.coroutines.**

# General Android
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions

