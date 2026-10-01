# SwiftRide — iOS App Store Pre-Submission Checklist

Complete every item in this checklist before submitting **Swift Ride** (`com.dartnexuslab.swiftri`) to TestFlight and the Apple App Store.

---

## 1. Identity & Bundle Registration
- [x] **App Display Name:** `Swift Ride` configured in `ios/Runner/Info.plist` (`CFBundleDisplayName`)
- [x] **Bundle Identifier:** `com.dartnexuslab.swiftri` registered in Apple Developer Account and configured in `project.pbxproj`
- [x] **Minimum iOS Version:** iOS 15.0 set in `project.pbxproj` and `ios/Podfile`
- [x] **App Icons:** High-resolution icons (1024x1024 marketing + all device scales) generated into `Assets.xcassets/AppIcon.appiconset` from master asset `assets/Gemini_Generated_Image_5pjlpe5pjlpe5pjl.jpeg`
- [ ] **App Store Connect Record:** Created under Apple ID with SKU (e.g. `swiftride-ios-2026`) and Bundle ID `com.dartnexuslab.swiftri`

---

## 2. Privacy & Compliance (Mandatory 2025/2026 Apple Standards)
- [x] **Privacy Manifest:** `ios/Runner/PrivacyInfo.xcprivacy` created declaring:
  - Precise Location (`NSPrivacyCollectedDataTypePreciseLocation`)
  - Coarse Location (`NSPrivacyCollectedDataTypeLocation`)
  - User ID (`NSPrivacyCollectedDataTypeUserID`)
  - Crash Diagnostics (`NSPrivacyCollectedDataTypeCrashData`)
  - Required Reason APIs: `UserDefaults` (`CA92.1`), `FileTimestamp` (`C617.1`), `SystemBootTime` (`35F9.1`), `DiskSpace` (`E174.1`)
- [x] **Export Compliance:** `ITSAppUsesNonExemptEncryption` set to `<false/>` in `Info.plist` to avoid export compliance questionnaire delays
- [ ] **Privacy Policy URL:** Publicly reachable HTTPS URL prepared (e.g., `https://swiftride.app/privacy`)
- [ ] **Terms of Service URL:** Publicly reachable HTTPS URL prepared (e.g., `https://swiftride.app/terms`)

---

## 3. Permissions & System Descriptions (`Info.plist`)
- [x] **Location (When In Use):** `NSLocationWhenInUseUsageDescription`
- [x] **Location (Always & Background):** `NSLocationAlwaysAndWhenInUseUsageDescription` & `NSLocationAlwaysUsageDescription`
- [x] **Background Modes:** `location`, `fetch`, `remote-notification` configured in `UIBackgroundModes`
- [x] **Camera:** `NSCameraUsageDescription` (Vehicle and verification document capture)
- [x] **Photo Library:** `NSPhotoLibraryUsageDescription` & `NSPhotoLibraryAddUsageDescription` (Document upload and receipt saving)
- [x] **Microphone & Speech:** `NSMicrophoneUsageDescription` & `NSSpeechRecognitionUsageDescription` (AI Assistant hands-free speech input)
- [x] **Motion & Sensors:** `NSMotionUsageDescription` (RideCheck crash detection and hard brake sensing)
- [x] **Contacts:** `NSContactsUsageDescription` (Emergency contacts / Share My Trip)
- [x] **Bluetooth:** `NSBluetoothAlwaysUsageDescription` (In-car peripheral connection)
- [x] **Google Maps Platform:** `GMSApiKey` key defined in `Info.plist`

---

## 4. Firebase & Backend Infrastructure
- [x] **GoogleService-Info.plist:** Configured with `BUNDLE_ID` = `com.dartnexuslab.swiftri` and reverse client ID
- [x] **Firebase App Check:** iOS `DeviceCheckProvider` activated in `main.dart` and `AppDelegate.swift`
- [ ] **APNs Authentication Key:** Auth Key (`.p8`) uploaded to Firebase Console under Cloud Messaging
- [ ] **Push Notification Capability:** Enabled in Xcode under Signing & Capabilities

---

## 5. Code Signing & Release Archive
- [x] **ExportOptions.plist:** Configured for `app-store` distribution with automatic/manual signing fallback
- [ ] **Apple Distribution Certificate:** Active iOS Distribution Certificate created in Apple Developer Portal
- [ ] **App Store Provisioning Profile:** Provisioning profile linked to `com.dartnexuslab.swiftri`
- [ ] **Clean Build Verification:** `flutter clean && flutter pub get && cd ios && pod install`
- [ ] **IPA Compilation:** `flutter build ipa --release --export-options-plist=ios/ExportOptions.plist`

---

## 6. App Review Preparation
- [ ] **Demo Accounts:** Provide 1 Rider account and 1 Driver account with verified phone numbers or bypass OTP in review notes
- [ ] **Reviewer Instructions:** Provide steps explaining:
  - Zero-commission model
  - Ride negotiation flow
  - Safety check-in and SOS demonstration
  - Stripe / Apple Pay test mode
