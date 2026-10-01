# SwiftRide — iOS Build & App Store Submission Guide

This comprehensive guide covers everything required to build, sign, and submit **Swift Ride** (`com.dartnexuslab.swiftri`) to the Apple App Store and TestFlight.

---

## 1. Project Identity & Configuration Summary

| Property | Value | Notes |
|---|---|---|
| **App Display Name** | `Swift Ride` | Rendered on iOS Home Screen (`CFBundleDisplayName`) |
| **App Name** | `Swft Ride` / `Swift Ride` | Set in `CFBundleName` and App Store Connect record |
| **iOS Bundle Identifier** | `com.dartnexuslab.swiftri` | Configured in Xcode project, `GoogleService-Info.plist`, and `ExportOptions.plist` |
| **Android Application ID** | `com.dartnexuslab.swiftri` | Kept in exact 1-to-1 sync across platforms |
| **Minimum iOS Target** | `iOS 15.0` | Configured in `project.pbxproj` and `Podfile` |
| **App Icon Master Asset** | `assets/Gemini_Generated_Image_5pjlpe5pjlpe5pjl.jpeg` | Automatically converted to all 15 iOS icon sizes in `Assets.xcassets/AppIcon.appiconset` |
| **Privacy Manifest** | `ios/Runner/PrivacyInfo.xcprivacy` | Apple Mandatory requirement (effective February 2025/2026, ITMS-91061) |

---

## 2. Prerequisites & Environment Setup

### 2.1 Apple Developer Program Enrollment
1. Go to [Apple Developer Program Enrollment](https://developer.apple.com/programs/enroll/).
2. Sign in with your Apple ID (Two-Factor Authentication is required).
3. Choose your entity type:
   - **Individual:** $99 USD/year. Requires legal name and personal credit card.
   - **Organization:** $99 USD/year. Requires legal entity status, authority to bind the company, and a valid **D-U-N-S Number** (obtained free via Dun & Bradstreet).
4. Complete purchase and wait for confirmation email (typically 24–48 hours).

### 2.2 macOS & Xcode Setup
Ensure Xcode and command line tools are installed:

```bash
# Verify Xcode active path
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch

# Agree to license
sudo xcodebuild -license accept

# Verify CocoaPods installation
pod --version
# If missing: brew install cocoapods
```

Verify your Flutter toolchain:
```bash
flutter doctor -v
```
All checks for **Flutter**, **Xcode**, and **CocoaPods** must report green checkmarks `[✓]`.

---

## 3. App Store Connect & Bundle Registration

### 3.1 Register Bundle Identifier
1. Sign in to [Apple Developer Certificates, Identifiers & Profiles](https://developer.apple.com/account/resources/identifiers/list).
2. Click the **+** button next to Identifiers.
3. Select **App IDs** > **App**, then click **Continue**.
4. Configure:
   - **Description:** `Swift Ride iOS`
   - **Bundle ID:** Select **Explicit** and enter `com.dartnexuslab.swiftri`
5. Under **Capabilities**, enable:
   - ✅ **Push Notifications**
   - ✅ **Background Modes** (Remote notifications)
   - ✅ **Sign in with Apple** (optional / if enabled)
6. Click **Register**.

### 3.2 Create App Record in App Store Connect
1. Sign in to [App Store Connect](https://appstoreconnect.apple.com/).
2. Navigate to **Apps** > click **+** > **New App**.
3. Fill in:
   - **Platforms:** iOS
   - **Name:** `Swift Ride`
   - **Primary Language:** English (US)
   - **Bundle ID:** Select `com.dartnexuslab.swiftri`
   - **SKU:** `swiftride-ios-2026`
   - **User Access:** Full Access
4. Click **Create**.

---

## 4. Firebase iOS Configuration

### 4.1 Register iOS App in Firebase Console
1. Open the [Firebase Console](https://console.firebase.google.com/) > select `swift-ride-5ab75`.
2. Under **Project Settings** > **General** > **Your apps** > click **Add app** > **iOS**.
3. Enter iOS bundle ID: `com.dartnexuslab.swiftri`.
4. App nickname: `Swift Ride iOS`.
5. Download `GoogleService-Info.plist` and confirm it is placed at:
   ```
   ios/Runner/GoogleService-Info.plist
   ```
6. Verify that `BUNDLE_ID` in `GoogleService-Info.plist` contains `com.dartnexuslab.swiftri`.

### 4.2 APNs Push Notifications Setup
1. In the [Apple Developer Member Center](https://developer.apple.com/account/resources/authkeys/list), create an **APNs Key** (`.p8` file).
2. In the Firebase Console > **Project Settings** > **Cloud Messaging** > **Apple app configuration**:
   - Upload your `.p8` APNs Authentication Key.
   - Enter your **Key ID** (10-character string from Apple) and **Team ID** (`PWQP27LSAK`).

### 4.3 Firebase App Check (iOS DeviceCheck / App Attest)
Firebase AI Logic requires App Check:
1. In the Firebase Console, navigate to **App Check** > **Apps** tab.
2. Select `com.dartnexuslab.swiftri`.
3. Under **DeviceCheck**: Upload your Apple Developer `.p8` private key and Team ID.
4. Token TTL is set to **1 hour**.
5. Client activation is pre-configured in `lib/main.dart` with `AppleDeviceCheckProvider`.

---

## 5. iOS Permissions & Background Modes (`Info.plist`)

All usage descriptions in `ios/Runner/Info.plist` provide transparent, user-centric explanations required for App Store review:

```xml
<!-- Location Tracking -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>Swift Ride needs your location to show nearby drivers and track your ride in real time.</string>
<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>Swift Ride needs background location access to track your ride even when the app is in the background.</string>
<key>NSLocationAlwaysUsageDescription</key>
<string>Swift Ride needs background location access for ride tracking.</string>

<!-- Vehicle & Document Verification -->
<key>NSCameraUsageDescription</key>
<string>Swift Ride needs camera access to photograph your vehicle and upload required verification documents.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Swift Ride needs photo library access to upload your driver documents and vehicle photos.</string>
<key>NSPhotoLibraryAddUsageDescription</key>
<string>Swift Ride needs permission to save trip receipts and photos to your library.</string>

<!-- Voice AI & Audio -->
<key>NSMicrophoneUsageDescription</key>
<string>Swift Ride needs microphone access for in-app voice chat and the AI assistant.</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Swift Ride uses speech recognition to let you talk to the AI assistant hands-free.</string>

<!-- Motion & Safety Check-In -->
<key>NSMotionUsageDescription</key>
<string>Swift Ride uses motion data for crash detection and safety monitoring during rides.</string>

<!-- Trusted Contacts -->
<key>NSContactsUsageDescription</key>
<string>Swift Ride needs contacts access to let you quickly add trusted contacts for trip sharing and SOS alerts.</string>

<!-- Background Modes -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
    <string>location</string>
</array>
```

---

## 6. Apple Privacy Manifest (`PrivacyInfo.xcprivacy`)

Starting February 2025/2026, submissions without a privacy manifest fail with `ITMS-91061`.
SwiftRide includes `ios/Runner/PrivacyInfo.xcprivacy` declaring:
- **Tracking:** `NSPrivacyTracking` = `false`
- **Collected Data:** Precise Location, Coarse Location, User ID, and Crash Data linked to App Functionality.
- **Required Reason APIs:**
  - `UserDefaults` (`CA92.1` — app preferences and theme states)
  - `FileTimestamp` (`C617.1` — cache management)
  - `SystemBootTime` (`35F9.1` — trip duration telemetry)
  - `DiskSpace` (`E174.1` — map tile cache limits)

---

## 7. App Icons Generation

The master branding asset `assets/Gemini_Generated_Image_5pjlpe5pjlpe5pjl.jpeg` (2048x2048) has been processed into the complete iOS icon set in `ios/Runner/Assets.xcassets/AppIcon.appiconset/`:

- `Icon-App-1024x1024@1x.png` (App Store Marketing)
- `Icon-App-60x60@2x.png` (120x120 iPhone)
- `Icon-App-60x60@3x.png` (180x180 iPhone Pro/Max)
- `Icon-App-76x76@1x.png` & `@2x.png` (iPad)
- `Icon-App-83.5x83.5@2x.png` (iPad Pro)
- Small notification and spotlight icons (20x20, 29x29, 40x40 at 1x, 2x, 3x)

To regenerate or update icons at any time:
```bash
python3 -c "
import subprocess
src = 'assets/Gemini_Generated_Image_5pjlpe5pjlpe5pjl.jpeg'
icons = [
    ('Icon-App-20x20@1x.png', 20), ('Icon-App-20x20@2x.png', 40), ('Icon-App-20x20@3x.png', 60),
    ('Icon-App-29x29@1x.png', 29), ('Icon-App-29x29@2x.png', 58), ('Icon-App-29x29@3x.png', 87),
    ('Icon-App-40x40@1x.png', 40), ('Icon-App-40x40@2x.png', 80), ('Icon-App-40x40@3x.png', 120),
    ('Icon-App-60x60@2x.png', 120), ('Icon-App-60x60@3x.png', 180),
    ('Icon-App-76x76@1x.png', 76), ('Icon-App-76x76@2x.png', 152),
    ('Icon-App-83.5x83.5@2x.png', 167), ('Icon-App-1024x1024@1x.png', 1024)
]
for name, s in icons:
    subprocess.run(['sips', '-s', 'format', 'png', '-z', str(s), str(s), src, '--out', f'ios/Runner/Assets.xcassets/AppIcon.appiconset/{name}'], check=True)
"
```

---

## 8. Build, Archive & Export Commands

### 8.1 Local Test on iOS Simulator
```bash
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter run -d "iPhone 17"
```

### 8.2 Building the Release IPA
```bash
# 1. Clean and install dependencies
flutter clean
flutter pub get
cd ios && pod install && cd ..

# 2. Compile release IPA using ExportOptions.plist
flutter build ipa --release \
  --export-options-plist=ios/ExportOptions.plist \
  --build-name=1.0.0 \
  --build-number=1
```

The resulting files will be created at:
- **Xcode Archive:** `build/ios/archive/Runner.xcarchive`
- **Distribution IPA:** `build/ios/ipa/Runner.ipa`

### 8.3 Uploading to App Store Connect / TestFlight

#### Option A: Using Transporter App (Recommended for Manual Uploads)
1. Download **Transporter** from the Mac App Store.
2. Sign in with your Apple ID.
3. Drag and drop `build/ios/ipa/Runner.ipa` into Transporter.
4. Click **Deliver**.

#### Option B: Using Command-Line `altool` / `xcrun`
```bash
xcrun altool --upload-app \
  --type ios \
  --file build/ios/ipa/Runner.ipa \
  --apiKey YOUR_API_KEY_ID \
  --apiIssuer YOUR_ISSUER_UUID
```

#### Option C: Automated CI/CD
Push a git tag `v1.0.0` to trigger the GitHub Actions workflow in `.github/workflows/ios-release.yml`.

---

## 9. App Store Review Information

In App Store Connect under **App Review Information**, provide the following notes for Apple's review team:

- **Sign-in Required:** Yes
- **Rider Demo Credentials:**
  - Phone: `+1 555-010-0001`
  - SMS OTP: `123456`
- **Driver Demo Credentials:**
  - Phone: `+1 555-010-0002`
  - SMS OTP: `123456`
- **Notes for Reviewer:**
  > "SwiftRide is a zero-commission ride-hailing app. During Year 1, 100% of the negotiated fare goes directly to the driver with zero platform cut. 
  > 
  > To test the flow:
  > 1. Sign in with Rider credentials to view nearby simulated drivers and request a trip.
  > 2. Use the in-app AI assistant (tap 'Ask AI') to ask questions regarding safety, earnings, or trip tracking.
  > 3. The emergency RideCheck and SOS features simulate haptic and contact alerts without dispatching actual emergency services in test mode."
