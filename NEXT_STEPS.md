# SwiftRide Launch Checklist & Next Steps (NEXT_STEPS.md)

Follow this step-by-step launch guide to configure environment variables, deploy Cloud Functions, and publish the mobile and web clients.

---

## 1. Firebase Project Provisioning

1. **Install Firebase CLI** (if not already installed):
   ```bash
   npm install -g firebase-tools
   ```
2. **Log in to Firebase**:
   ```bash
   firebase login
   ```
3. **Initialize & Select Project**:
   ```bash
   firebase use --add <your-firebase-project-id>
   ```
4. **Enable Services in Firebase Console**:
   - **Authentication**: Enable Phone (SMS) and Email/Password providers.
   - **Cloud Firestore**: Create database in production mode in `us-central1`.
   - **Realtime Database**: Create default instance in `us-central1`.
   - **Cloud Storage**: Create default storage bucket.
   - **Cloud Functions**: Ensure Blaze (pay-as-you-go) plan is active for Gen 2 Cloud Run deployment.

---

## 2. Environment Variables & Secret Configuration

Set production secrets in Google Cloud Secret Manager or via Firebase CLI:

```bash
# Stripe Secret Key (for card payments and driver payouts)
firebase functions:secrets:set STRIPE_SECRET_KEY

# Stripe Webhook Secret (signing secret from Stripe Dashboard)
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET

# Google Maps API Key (Routes Preferred, Places, Geocoding)
firebase functions:secrets:set GOOGLE_MAPS_API_KEY

# Gemini Developer API Key (for Cloud Functions Gen 2 AI calls)
firebase functions:secrets:set GEMINI_API_KEY
```

---

## 2.1 Firebase AI Logic & App Check Activation

1. **Enable Firebase AI Logic**:
   - In Firebase Console, go to **Build** > **Firebase AI Logic**.
   - Select the **Gemini Developer API** provider (Spark plan compatible, model `gemini-3.8-flash`).

2. **Activate App Check Enforcement**:
   - In Firebase Console, go to **App Check** > **Apps**.
   - Android: Register SHA-256 fingerprint for **Play Integrity**.
   - iOS: Register Apple Team ID & Private Key for **DeviceCheck** / **App Attest**.
   - Under **Cloud Functions**, verify App Check enforcement is toggled on for all AI callables (`generateEarningsInsight`, `safetyCheckIn`, `conversationalAssistant`, `predictVehicleMaintenance`, `routeOptimizer`).

3. **Remote Config Flags**:
   - Create parameter `ai_features_enabled` (Boolean, default `true`).
   - Create parameter `voice_assistant_enabled` (Boolean, default `true`).
   - Create parameter `safety_ai_enabled` (Boolean, default `true`).

---

## 2.2 Google Maps Platform API Key Setup (Required for Map Tiles)

To display live Google Maps tiles with streets, buildings, labels, and traffic on iOS and Android:

1. **Obtain API Keys from Google Cloud Console**:
   - Go to [Google Cloud Console Credentials](https://console.cloud.google.com/google/maps-apis/credentials).
   - Ensure the following APIs are enabled in your Google Cloud Project:
     - **Maps SDK for iOS**
     - **Maps SDK for Android**
     - **Routes API / Routes Preferred**
     - **Places API (New)**
     - **Geocoding API**
   - Create an API key with Application Restriction:
     - **iOS restriction:** Bundle ID `com.dartnexuslab.swiftri`
     - **Android restriction:** Package name `com.dartnexuslab.swiftri` + SHA-1 certificate fingerprint

2. **Insert iOS Key (`ios/Runner/Info.plist`)**:
   Open `ios/Runner/Info.plist` and replace `YOUR_IOS_MAPS_API_KEY_HERE`:
   ```xml
   <key>GMSApiKey</key>
   <string>YOUR_ACTUAL_IOS_GOOGLE_MAPS_API_KEY</string>
   ```

3. **Insert Android Key (`android/app/src/main/AndroidManifest.xml`)**:
   Open `android/app/src/main/AndroidManifest.xml` and replace `YOUR_ANDROID_MAPS_API_KEY_HERE`:
   ```xml
   <meta-data
       android:name="com.google.android.geo.API_KEY"
       android:value="YOUR_ACTUAL_ANDROID_GOOGLE_MAPS_API_KEY"/>
   ```

4. **Rebuild & Run**:
   ```bash
   flutter clean && flutter pub get
   cd ios && pod install && cd ..
   flutter run
   ```

## 3. Deploy Backend Security Rules & Cloud Functions

```bash
# 1. Deploy Firestore Security Rules & Indexes
firebase deploy --only firestore:rules,firestore:indexes

# 2. Deploy Realtime Database Rules
firebase deploy --only database

# 3. Deploy Cloud Storage Rules
firebase deploy --only storage

# 4. Build and Deploy Cloud Functions Gen 2
cd functions
npm run build
firebase deploy --only functions
```

---

## 4. Local Emulator Testing

Test the entire stack locally with the Firebase Emulator Suite:

```bash
# Start all emulators (Auth, Functions, Firestore, RTDB, Hosting, Storage)
firebase emulators:start
```
- Emulator UI: `http://localhost:4000`
- Functions: `http://localhost:5001`
- Firestore: `http://localhost:8080`
- RTDB: `http://localhost:9000`

---

## 5. Running & Building the Flutter Applications

```bash
# Run unit and widget tests
flutter test

# Run static analysis
flutter analyze

# Launch on Chrome / Web (Admin Portal & Public Trip Tracking)
flutter run -d chrome

# Launch on macOS Desktop
flutter run -d macos

# Launch on connected iOS / Android device
flutter run
```

### Production Web Build (Admin Portal)
```bash
flutter build web --release
firebase deploy --only hosting
```
