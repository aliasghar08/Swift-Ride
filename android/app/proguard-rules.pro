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

# 3. Aggressive R8 Optimization & Repackaging for Third-Party Dependencies
-allowaccessmodification
-repackageclasses ''

# 4. Google Mobile Ads (AdMob)
-keep public class com.google.android.gms.ads.initialization.InitializationStatus { *; }
-keep public class com.google.android.gms.ads.initialization.OnInitializationCompleteListener { *; }
-dontwarn com.google.android.gms.ads.**
-dontwarn com.google.android.gms.internal.ads.**

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




