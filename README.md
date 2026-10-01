<div align="center">

# 🚖 Swift Ride (Swft Ride)
### Next-Generation Zero-Commission Ride-Hailing Platform with Gemini AI

[![Flutter](https://img.shields.io/badge/Flutter-3.47.5-02569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Gen_2-FFCA28?style=for-the-badge&logo=firebase&logoColor=black)](https://firebase.google.com)
[![Gemini AI](https://img.shields.io/badge/Gemini-3.8_Flash-4285F4?style=for-the-badge&logo=google&logoColor=white)](https://ai.google.dev)
[![App Check](https://img.shields.io/badge/App_Check-Enforced-34A853?style=for-the-badge&logo=googleplay&logoColor=white)](https://firebase.google.com/docs/app-check)
[![Codemagic](https://img.shields.io/badge/Codemagic-CI%2FCD-F44336?style=for-the-badge&logo=codemagic&logoColor=white)](https://codemagic.io)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge)](./LICENSE.md)

<p align="center">
  <b>Package ID / Bundle Identifier:</b> <code>com.dartnexuslab.swiftri</code><br>
  <b>Platforms:</b> iOS 15.0+ • Android 8.0+ (API 26+) • Web Admin
</p>

</div>

---

## 🌟 Overview

**Swift Ride** is an autonomous, full-stack, production-grade ride-hailing ecosystem built with **Flutter 3.x** and **Firebase Gen 2 (Cloud Functions, Firestore, Realtime Database)**, supercharged with an integrated **Gemini AI** layer (`gemini-3.8-flash`) via **Firebase AI Logic**.

Unlike legacy ride-hailing incumbents (Uber, Lyft) that charge 15–30% platform cuts, SwiftRide offers **0% commission for riders and drivers in Year 1**. Drivers keep 100% of their negotiated fares, riders enjoy fair pricing, and both parties benefit from proactive AI-powered safety and earnings advisory intelligence.

---

## 🏛️ Architectural Overview

```
                          ┌─────────────────────────────────────────┐
                          │            Flutter Mobile App           │
                          │        (Rider • Driver • Admin)         │
                          │   • Frosted Glassmorphic Design         │
                          │   • Cascading Staggered Micro-Motion    │
                          │   • Pure Reactive State Management      │
                          └────────────────────┬────────────────────┘
                                               │
                    ┌──────────────────────────┴──────────────────────────┐
                    │                                                     │
        (State, Bids & Transactions)                             (Live Telemetry & GPS)
                    │                                                     │
                    ▼                                                     ▼
      ┌───────────────────────────┐                         ┌───────────────────────────┐
      │      Cloud Firestore      │                         │     Realtime Database     │
      │  • Users & Profiles       │                         │  • driver_locations (2s)  │
      │  • Rides, Bids & Offers   │                         │  • live_ride_tracking     │
      │  • ai_insights (24h cache)│                         │  • low-latency GPS stream │
      └─────────────┬─────────────┘                         └─────────────┬─────────────┘
                    │                                                     │
                    └──────────────────────────┬──────────────────────────┘
                                               │
                                               ▼
                              ┌─────────────────────────────────┐
                              │      Cloud Functions Gen 2      │
                              │         (TypeScript 5.6)        │
                              │  • inDrive Bidding Engine       │
                              │  • Geohash Spatial Driver Match │
                              │  • Stripe Connect Express       │
                              │  • RideCheck Telemetry Monitor  │
                              └────────────────┬────────────────┘
                                               │
                                               ▼
                              ┌─────────────────────────────────┐
                              │      Gemini AI Intelligence     │
                              │     (Firebase AI Logic SDK)     │
                              │  • Model: gemini-3.8-flash      │
                              │  • App Check Enforced           │
                              │  • Daily Earnings Advisor       │
                              │  • Proactive Safety Check-in    │
                              │  • Fleet Maintenance Predictor  │
                              └─────────────────────────────────┘
```

---

## 💎 Core Differentiators & Features

### 1. 0% Commission & Fair Price Negotiation
- **Zero Platform Cut**: In Year 1, drivers keep 100% of trip fares.
- **inDrive Bidding Mechanism**: Riders propose fares; nearby drivers counter-bid with instant `+$1`, `+$2`, or custom offers.
- **Suggested Fare Formula**: `Base ($2.00) + ($0.50/km) + ($0.10/min)`.

### 2. Built-in Gemini AI Layer (`gemini-3.8-flash`)
- **Daily Earnings Advisor**: Automated 6:00 AM analysis of the driver's past 7 days, local demand hotspots, weather, and events with 3 actionable tips (cached 24h in Firestore).
- **Proactive Safety Check-In**: Instant calm, natural-language check-in message dispatched to both parties whenever RideCheck flags anomalies (extended stop, route deviation).
- **In-App Conversational Assistant**: Streaming role-aware chatbot (Rider vs Driver) with intent routing for `track_ride`, `show_earnings`, and `trigger_sos`.
- **Predictive Fleet Maintenance**: Weekly Monday vehicle wear analysis forecasting brake, tire, and oil service urgency (`LOW`, `MEDIUM`, `HIGH`).
- **Cost-Controlled & Secure**: Strict token budgets (`256` chat / `512` insights) with low thinking level and Firebase Remote Config emergency kill-switches.

### 3. Comprehensive Passenger & Driver Safety
- **4-Digit PIN Verification**: Eliminates wrong-car entries; drivers cannot start trips without passenger PIN verification.
- **RideCheck Anomaly Detection**: Monitors speed, route deviation, and stationary duration in real time.
- **Share My Trip**: Web tracking URLs (`/track?token=...`) allowing family to track active rides without installing the app.
- **One-Tap Emergency SOS**: Triggers native siren vibrations, emergency SMS dispatches, and emergency contact broadcasts.

### 4. Native iOS & Android Integration
- **Apple Pay & PassKit**: Native payment processing via method channels.
- **Screen WakeLock & Haptics**: Native screen lock control and sensory feedback.
- **Background Location**: Background GPS streaming for accurate ride tracking.

### 5. Production Google Maps SDK & Cloud Proxies
- **Native Vector SDK**: Direct integration with `google_maps_flutter` on iOS and Android with customized dark mode styling.
- **Multi-Mode Map Canvas**: Interactive pin-picker with 350ms reverse geocoding debouncing, navigation mode, and live driver tracking with rotated heading markers.
- **Secure Backend Proxies**: Routes Preferred, Places Autocomplete, and Geocoding APIs proxied via Cloud Functions secured with Firebase App Check.

---

## 📂 Project Structure

```
SwiftRide/
├── .github/workflows/          # GitHub Actions CI/CD (iOS Release & TestFlight)
├── android/                    # Android Project (com.dartnexuslab.swiftri)
├── assets/                     # Master Branding Assets & App Icons
├── codemagic.yaml              # Codemagic CI/CD Pipeline (iOS, Android, PR checks)
├── functions/                  # Cloud Functions Gen 2 (TypeScript)
│   ├── src/
│   │   ├── config/             # Gemini AI, Firebase, and Logger configs
│   │   ├── modules/ai/         # Earnings, Safety, Chat, Maintenance Cloud Functions
│   │   ├── modules/maps/       # Routes, Autocomplete, Place Details, Geocoding Proxies
│   │   ├── modules/rides/      # Bidding & ride dispatch engine
│   │   └── modules/safety/     # SOS and trip sharing
│   └── tests/                  # Vitest backend test suite
├── ios/                        # iOS Project (com.dartnexuslab.swiftri, iOS 15.0+)
│   ├── Runner/
│   │   ├── AppDelegate.swift   # Native MethodChannels, APNs & GMSServices
│   │   ├── Info.plist          # Transparent iOS permissions, GMSApiKey
│   │   └── PrivacyInfo.xcprivacy # Apple Privacy Manifest (ITMS-91061)
│   ├── ExportOptions.plist     # App Store IPA export configuration
│   └── SwiftRide-unsigned.ipa  # Pre-compiled Unsigned iOS Release IPA (11 MB)
├── lib/
│   ├── ai/                     # Clean AI Architecture (Domain, Data, Presentation)
│   ├── core/                   # Theme, Router, Custom Providers, Utilities
│   ├── domain/models/          # Immutable domain models (Ride, Driver, User, Safety)
│   ├── presentation/           # Glassy screens, GoogleMapView, animated widgets
│   ├── providers/              # Pure custom ChangeNotifier providers
│   └── services/               # Native method channels and business services
├── test/                       # Flutter Unit & Widget Test Suite (27 tests)
├── AI_SETUP.md                 # Firebase AI Logic & App Check Setup Guide
├── DECISIONS.md                # Architecture & Design Decision Log
├── IOS_CHECKLIST.md            # App Store Pre-Submission Checklist
├── IOS_SETUP.md                # Complete iOS Build & Distribution Guide
├── MAPS_SETUP.md               # Google Maps SDK, Cloud Proxies & Cost Controls
├── LICENSE.md                  # MIT License
└── SECURITY.md                 # Security & Vulnerability Disclosure Policy
```

---

## 🚀 Quick Start Guide

### Prerequisites
- **Flutter SDK:** `^3.47.5` (Dart `^3.13.4`)
- **Xcode:** `15.0+` with iOS 15+ SDK
- **Node.js:** `v20+` or `v22+` (for Cloud Functions)
- **CocoaPods:** `1.16+`

### 1. Clone & Install Dependencies
```bash
git clone https://github.com/aliasghar08/Swift-Ride.git
cd Swift-Ride
flutter pub get
```

### 2. Configure Environment
Copy `.env.example` to `.env`:
```bash
cp .env.example .env
```
Configure your `GEMINI_API_KEY` in Google Cloud Secret Manager for Cloud Functions.

### 3. Run Test Suites
```bash
# Flutter Client Tests (27/27 Passing)
flutter analyze
flutter test

# Cloud Functions Vitest Suite (11/11 Passing)
cd functions
npm install
npm test
cd ..
```

### 4. Run Locally
```bash
# Launch on iOS Simulator
flutter run -d "iPhone 17"

# Launch on Android Emulator
flutter run -d emulator-5554
```

---

## 🍏 iOS Release Build & App Store Distribution

The project is pre-configured with Bundle ID **`com.dartnexuslab.swiftri`**, display name **`Swift Ride`**, and complete privacy manifests.

### Building the Release IPA
```bash
# Clean and install CocoaPods
flutter clean
flutter pub get
cd ios && pod install && cd ..

# Compile release IPA using ExportOptions.plist
flutter build ipa --release \
  --export-options-plist=ios/ExportOptions.plist \
  --build-name=1.0.0 \
  --build-number=1
```

An unsigned release archive is also pre-packaged at:
```
ios/SwiftRide-unsigned.ipa (11 MB)
```

Refer to [`IOS_SETUP.md`](./IOS_SETUP.md) and [`IOS_CHECKLIST.md`](./IOS_CHECKLIST.md) for full App Store Connect submission steps.

---

## 🗺️ Google Maps Setup & Key Provisioning

SwiftRide uses `google_maps_flutter` for client rendering combined with Cloud Function proxies for routing and places:

1. **Enable APIs in Google Cloud Console:** Maps SDK for iOS, Maps SDK for Android, Routes API, Places API, Geocoding API, Distance Matrix API.
2. **Configure Native Keys:**
   - **iOS:** Add your key restricted to bundle `com.dartnexuslab.swiftri` into `ios/Runner/Info.plist` (`GMSApiKey`).
   - **Android:** Add your key restricted to package `com.dartnexuslab.swiftri` into `android/app/src/main/AndroidManifest.xml` (`com.google.android.geo.API_KEY`).
3. **Configure Backend Server Key:**
   - Store in Google Cloud Secret Manager:
     ```bash
     firebase functions:secrets:set GOOGLE_MAPS_SERVER_KEY
     ```

For comprehensive instructions on key restrictions, testing cURL commands, cost estimation tables ($200 free credit), and billing alerts, consult the **[Google Maps Setup Guide (`MAPS_SETUP.md`)](./MAPS_SETUP.md)**.

---

## 🤖 CI / CD Pipelines

SwiftRide comes out-of-the-box with two enterprise CI/CD configurations:
1. **Codemagic** ([`codemagic.yaml`](./codemagic.yaml)): Automated building, testing, code signing, and distribution to **TestFlight** and **Google Play Internal Sharing**.
2. **GitHub Actions** ([`.github/workflows/ios-release.yml`](./.github/workflows/ios-release.yml)): Tag-driven (`v*`) automated iOS IPA archive and TestFlight deployment.

---

## 🔒 Security & Privacy

SwiftRide enforces strict defense-in-depth principles:
- **Firebase App Check**: Play Integrity & Apple DeviceCheck enforced across all endpoints.
- **Apple Privacy Manifest**: [`ios/Runner/PrivacyInfo.xcprivacy`](./ios/Runner/PrivacyInfo.xcprivacy) fully declared.
- **Zero Client Secrets**: No third-party API keys stored on mobile devices.
- For vulnerability reporting, see [`SECURITY.md`](./SECURITY.md).

---

## 📄 License

This project is licensed under the **MIT License** — see the [`LICENSE.md`](./LICENSE.md) file for details.

Developed with ❤️ by **Ali Asghar** • [Dart Nexus Lab](https://github.com/aliasghar08)
