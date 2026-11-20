# ProGuard / R8 Optimization Rules for SwiftRide
# Fine-tuned for maximum DEX shrinking, obfuscation, and performance

# 1. SwiftRide Native Platform Entry Points (JNI & MethodChannels)
-keep class com.dartnexuslab.swiftride.MainActivity { *; }
-keep class com.dartnexuslab.swiftride.NativeMapViewFactory { *; }
-keep class com.dartnexuslab.swiftride.NativeMapView { *; }
-keep class com.dartnexuslab.swiftride.NativeLocationService { *; }
-keep class com.dartnexuslab.swiftride.NativeMapService { *; }

# 2. Aggressive R8 Optimization & Repackaging
-allowaccessmodification
-repackageclasses ''

# 3. Google Mobile Ads (AdMob)
-keep public class com.google.android.gms.ads.initialization.InitializationStatus { *; }
-keep public class com.google.android.gms.ads.initialization.OnInitializationCompleteListener { *; }
-dontwarn com.google.android.gms.ads.**
-dontwarn com.google.android.gms.internal.ads.**

# 4. TensorFlow Lite
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.lite.**

# 5. Google Play Core / Deferred Components
-dontwarn com.google.android.play.core.**

# 6. Reflection & Crashlytics Line Numbers
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes Signature
-keepattributes InnerClasses
-keepattributes EnclosingMethod



