# ProGuard / R8 Optimization Rules for SwiftRide
# Fine-tuned for maximum DEX shrinking, obfuscation, and 100% Flutter engine stability

# 1. Flutter Engine, Embedding & Plugins (JNI & PlatformViews)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# 2. SwiftRide Native Platform Entry Points (JNI & MethodChannels)
-keep class com.dartnexuslab.swiftride.** { *; }

# 3. AndroidX Startup, Room & WorkManager (Required by Google Mobile Ads / AdMob)
# Note: Do NOT use -repackageclasses because Room and WorkManager use reflection
# to look up generated *_Impl database classes by package and class name.
-keep class androidx.startup.** { *; }
-keep class * extends androidx.startup.Initializer { *; }

-keep class * extends androidx.room.RoomDatabase { *; }
-keep class androidx.room.** { *; }
-keep class **_Impl extends androidx.room.RoomDatabase {
    public <init>(...);
}
-dontwarn androidx.room.paging.**

-keep class androidx.work.** { *; }
-keep class androidx.work.impl.** { *; }
-keep class androidx.work.impl.WorkDatabase { *; }
-keep class androidx.work.impl.WorkDatabase_Impl {
    public <init>(...);
}
-keep class * extends androidx.work.Worker { *; }
-keep class * extends androidx.work.ListenableWorker { *; }
-keep class * extends androidx.work.InputMerger { *; }
-keep class androidx.work.WorkManagerInitializer { *; }

# 4. Google Mobile Ads (AdMob) & UMP Consent SDK
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.ads.** { *; }
-keep class com.google.android.ump.** { *; }
-dontwarn com.google.android.gms.ads.**
-dontwarn com.google.android.gms.internal.ads.**
-dontwarn com.google.android.ump.**

# 5. TensorFlow Lite
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# 6. Google Play Core / Deferred Components
-dontwarn com.google.android.play.core.**

# 7. Reflection & Crashlytics Line Numbers
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod




