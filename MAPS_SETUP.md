# 🗺️ Google Maps Platform Integration & Setup Guide

This document outlines the complete setup, key provisioning, security restrictions, cost controls, and verification steps for Google Maps integration in **SwiftRide** (`com.dartnexuslab.swiftri`).

---

## 📋 Architectural Overview

SwiftRide uses a **hybrid architecture** combining client-side rendering with secure, backend-proxied Google Maps Platform web services:

| Layer | Component | Purpose | Security Model |
|---|---|---|---|
| **Client (Flutter)** | `GoogleMapView` (`google_maps_flutter`) | Vector map tile rendering, marker rendering, polyline visualization, camera animations | Restricted Native API Keys in `Info.plist` & `AndroidManifest.xml` |
| **Backend (Cloud Functions)** | `getRoute` | Turn-by-turn routing & traffic-aware polylines via Routes Preferred API | Firebase App Check + Secret Manager (`GOOGLE_MAPS_SERVER_KEY`) |
| **Backend (Cloud Functions)** | `getAutocomplete` | Search suggestions via Places API Autocomplete | App Check + Session Token Billing |
| **Backend (Cloud Functions)** | `getPlaceDetails` | Detailed coordinates & formatted address via Places Details API | App Check + Secret Manager |
| **Backend (Cloud Functions)** | `reverseGeocode` | Street address reverse-geocoding for draggable map pins | App Check + 350ms Client Debounce + Firestore Caching |

> [!IMPORTANT]
> **Zero Client Secrets for Web Services:** Client apps never call Google Maps REST APIs directly. All Places, Routes, and Geocoding requests flow through Firebase Cloud Functions secured with Firebase App Check. This prevents quota theft, API key extraction, and unauthorized billing.

---

## 1. Google Cloud Console Setup

### Step 1.1: Select or Create a Project
1. Navigate to the [Google Cloud Console](https://console.cloud.google.com/).
2. Select your Firebase project (e.g. `swiftride-production` or `swiftride-xxxxx`) so that billing and credentials stay unified with your Firebase ecosystem.

### Step 1.2: Enable Billing
Ensure a valid billing account is linked to the project. Google provides **$200 in free usage every month** for Google Maps Platform.

### Step 1.3: Enable the 6 Required APIs
Enable the following APIs in **APIs & Services > Library**:
1. **Maps SDK for iOS** — Enables vector map tile rendering on iPhones/iPads.
2. **Maps SDK for Android** — Enables vector map tile rendering on Android devices.
3. **Routes API** (and Routes Preferred) — Turn-by-turn route calculations, polyline geometry, and traffic conditions.
4. **Places API (New)** / **Places API** — Autocomplete suggestions and place detail lookups.
5. **Geocoding API** — Reverse-geocoding pin coordinates to human-readable street addresses.
6. **Distance Matrix API** — Fast matrix distance and ETA calculations for dispatch and upfront fare estimation.

Alternatively, enable them via the `gcloud` CLI:
```bash
gcloud services enable \
  maps-ios-backend.googleapis.com \
  maps-android-backend.googleapis.com \
  routes.googleapis.com \
  places-backend.googleapis.com \
  geocoding-backend.googleapis.com \
  distance-matrix-backend.googleapis.com \
  --project=YOUR_PROJECT_ID
```

---

## 2. API Key Generation & Security Restrictions

Create **three separate API keys** in [Google Cloud Console > Credentials](https://console.cloud.google.com/apis/credentials). Never reuse a single unrestricted key.

### Key 1: iOS Maps Client Key
- **Name:** `SwiftRide iOS Maps Key`
- **Application Restriction:** **iOS apps**
- **Bundle ID:** `com.dartnexuslab.swiftri`
- **API Restrictions:** Restrict to **Maps SDK for iOS** only.

### Key 2: Android Maps Client Key
- **Name:** `SwiftRide Android Maps Key`
- **Application Restriction:** **Android apps**
- **Package Name:** `com.dartnexuslab.swiftri`
- **SHA-1 Fingerprint:**
  - *Debug Keystore:* Obtain with:
    ```bash
    keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android
    ```
  - *Release Keystore / Play App Signing:* Copy the SHA-1 from Google Play Console > Release > Setup > App Signing.
- **API Restrictions:** Restrict to **Maps SDK for Android** only.

### Key 3: Server Key (Cloud Functions)
- **Name:** `SwiftRide Server Maps Key`
- **Application Restriction:** **None** (or IP addresses of egress if using a fixed NAT gateway).
- **API Restrictions:** Restrict strictly to:
  - `Routes API`
  - `Places API`
  - `Geocoding API`
  - `Distance Matrix API`

---

## 3. Adding Keys to SwiftRide

### iOS Setup
Open `ios/Runner/Info.plist` and replace `YOUR_GOOGLE_MAPS_IOS_API_KEY`:
```xml
<key>GMSApiKey</key>
<string>AIzaSyYourRealIosKeyHere</string>
```
The key is initialized automatically in `ios/Runner/AppDelegate.swift`:
```swift
if let apiKey = Bundle.main.object(forInfoDictionaryKey: "GMSApiKey") as? String {
  GMSServices.provideAPIKey(apiKey)
}
```

### Android Setup
Open `android/app/src/main/AndroidManifest.xml` and replace `YOUR_ANDROID_MAPS_API_KEY`:
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="AIzaSyYourRealAndroidKeyHere"/>
```

### Cloud Functions Setup (Secret Manager)
Store the server key securely using Firebase CLI:
```bash
firebase functions:secrets:set GOOGLE_MAPS_SERVER_KEY
# Enter your server API key when prompted
```

To test locally using the Firebase Emulator Suite:
```bash
echo "GOOGLE_MAPS_SERVER_KEY=AIzaSyYourRealServerKeyHere" >> functions/.secret.local
```

---

## 4. Verification & Testing

### 1. Test Server Key via cURL

**Geocoding:**
```bash
curl -s "https://maps.googleapis.com/maps/api/geocode/json?latlng=37.7749,-122.4194&key=YOUR_SERVER_KEY" | grep -A 2 "formatted_address"
```

**Places Autocomplete:**
```bash
curl -s "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=Market%20Street&key=YOUR_SERVER_KEY" | grep "description"
```

**Routes Preferred:**
```bash
curl -X POST "https://routes.googleapis.com/directions/v2:computeRoutes" \
  -H "Content-Type: application/json" \
  -H "X-Goog-Api-Key: YOUR_SERVER_KEY" \
  -H "X-Goog-FieldMask: routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline" \
  -d '{
    "origin": {"location": {"latLng": {"latitude": 37.7749, "longitude": -122.4194}}},
    "destination": {"location": {"latLng": {"latitude": 37.7891, "longitude": -122.4014}}},
    "travelMode": "DRIVE"
  }'
```

### 2. Test Mobile Client Maps
1. Run on iOS:
   ```bash
   cd SwiftRide
   flutter run -d "iPhone 17"
   ```
2. Verify:
   - Real Google vector tiles load with clean dark-mode styling.
   - User GPS location dot appears when permissions are accepted.
   - Center pin displays in `pinPicker` mode.
   - Moving the map triggers reverse-geocoding debounced by 350ms.
   - Searching for an address suggests locations and settles camera upon selection.
   - Route polylines draw smoothly between origin and destination.

---

## 5. Cost Controls & Production Safeguards

To prevent unexpected Google Cloud charges, the following optimizations are implemented:

1. **Client-Side Debouncing (350ms):**
   - In `GoogleMapView`, pin dragging cancels pending timers and waits 350ms of camera settle time before dispatching reverse-geocode requests.
2. **Session Token Billing for Autocomplete:**
   - Autocomplete calls bundle typing queries under a single `sessionToken` UUID per search session, billing as 1 Autocomplete Session ($0.017) instead of billing per keystroke ($0.00283 × 10 = $0.028).
3. **Firestore Reverse-Geocode & Route Caching:**
   - Coordinates rounded to 5 decimal places (~1.1 meter accuracy) are cached in Firestore for 24 hours. Duplicate lookups for popular pickup points cost $0 in Maps API calls.
   - Route polylines between active origin/destination pairs are cached in-memory and in Firestore for 60 seconds.
4. **App Check Rate Limiting:**
   - All backend proxies enforce Firebase App Check with custom token verification. Non-app clients are blocked before consuming Maps API quota.

---

## 6. Cost Estimation Table

Google grants **$200 monthly free credit** (equivalent to ~28,500 free map loads or 11,700 autocomplete sessions per month).

| Metric | 1,000 Rides/mo | 10,000 Rides/mo | 100,000 Rides/mo |
|---|---|---|---|
| **Dynamic Maps Loads** ($7.00 / 1K) | ~3,000 ($21.00) | ~30,000 ($210.00) | ~300,000 ($2,100.00) |
| **Places Autocomplete Sessions** ($17.00 / 1K) | ~1,200 ($20.40) | ~12,000 ($204.00) | ~120,000 ($2,040.00) |
| **Routes Compute API** ($5.00 / 1K) | ~1,500 ($7.50) | ~15,000 ($75.00) | ~150,000 ($750.00) |
| **Reverse Geocoding** ($5.00 / 1K, after cache) | ~800 ($4.00) | ~8,000 ($40.00) | ~80,000 ($400.00) |
| **Total Estimated Gross Cost** | **$52.90** | **$529.00** | **$5,290.00** |
| **Google Monthly Free Credit** | -$200.00 | -$200.00 | -$200.00 |
| **Net Monthly Cost** | **$0.00** (Free) | **~$329.00** | **~$5,090.00** |

---

## 7. Cloud Console Billing Alerts

Configure automated budget alerts to avoid surprises:
1. Go to **Google Cloud Console > Billing > Budgets & Alerts**.
2. Create Budget: `SwiftRide Maps Monthly Budget`.
3. Set Target Amount: `$200.00`.
4. Configure Trigger Thresholds:
   - **25% ($50)** — Informational email alert.
   - **100% ($200)** — Alert when approaching exhaustion of free tier.
   - **250% ($500)** — Critical alert for high volume or abnormal traffic.
5. Connect alerts to developer email and Slack webhook.
