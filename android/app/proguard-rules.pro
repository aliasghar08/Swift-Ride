# ProGuard / R8 Rules for SwiftRide
# Protects against startup crashes on OEM devices (Infinix, Xiaomi, Tecno)

# 1. Flutter Engine & Plugins
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class com.dartnexuslab.swiftride.** { *; }

# 2. Google Mobile Ads (AdMob)
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**
-keep class com.google.android.gms.internal.ads.** { *; }
-dontwarn com.google.android.gms.internal.ads.**
-keep public class com.google.android.gms.ads.initialization.InitializationStatus { *; }
-keep public class com.google.android.gms.ads.initialization.OnInitializationCompleteListener { *; }

# 3. Google Play Services (Maps, Location, App Check)
-keep class com.google.android.gms.maps.** { *; }
-dontwarn com.google.android.gms.maps.**
-keep class com.google.android.gms.location.** { *; }
-dontwarn com.google.android.gms.location.**
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.android.gms.common.**
-keep class com.google.android.gms.tasks.** { *; }
-dontwarn com.google.android.gms.tasks.**

# 4. Firebase SDKs
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# 5. Reflection & Annotations
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod
