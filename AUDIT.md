# SwiftRide — Full Pipeline Deep Audit & Fix Report

## 1. Executive Summary

- **Place Search Backend is Fixed & Verified Live**: `getAutocomplete` now calls Google Places API (New) with Pakistan region filtering (`includedRegionCodes: ['pk']`), enabled CORS, and token validation (`assertHasToken`) without crashing on Firestore. Live HTTP calls confirm real predictions for Pakistani cities (e.g., Faisalabad, Lahore, Islamabad).
- **All Silent Fallbacks Permanently Removed**: Removed `_knownLocations`, `_searchLocalGazetteer`, and `MapService.fallbackLocations`. When a search returns no matches or network fails, the UI displays "No places found" with a retry button instead of displaying stale hardcoded landmarks.
- **Authentication Token Minting Restored**: Enabled Anonymous Auth on Firebase project `swift-ride-5ab75`. Added `signInAnonymously()` to `AuthService` and invoked it in `AuthProvider` on boot so guest riders can immediately search places with a valid token.
- **Location Timeout Cascades Resolved**: Native iOS `AppDelegate.swift` fast path now returns valid cached coordinates (< 200m accuracy) instantly instead of dropping fixes on stationary devices, eliminating the 12s timeout spam.
- **UI Contrast & Layout Overlaps Fixed**: `AddressSearchScreen` text fields now derive colors dynamically from `AppColors.of(context)` (preventing white-on-white invisibility). `RiderHomeScreen` nests the GPS status banner directly beneath the top address card, eliminating overlap with the bottom fare sheet.

---

## 2. Evidence Log

### Proof 1 — Cloud Function Actual Response (Bypassing Flutter)

**Initial State (Unauthenticated curl):**
```http
POST https://us-central1-swift-ride-5ab75.cloudfunctions.net/getAutocomplete
HTTP/2 401
{"error":{"message":"User must be authenticated to perform this operation.","status":"UNAUTHENTICATED"}}
```

**Secondary State (Authenticated curl before fix):**
```http
POST https://us-central1-swift-ride-5ab75.cloudfunctions.net/getAutocomplete
HTTP/2 500
{"error":{"message":"INTERNAL","status":"INTERNAL"}}
```
*Cloud Run Log excerpt (`firebase functions:log --only getAutocomplete`):*
```log
Unhandled error Error: 7 PERMISSION_DENIED: Missing or insufficient permissions.
    at callErrorFromStatus (/workspace/node_modules/@grpc/grpc-js/build/src/call.js:32:19)
    at Firestore.getAll (/workspace/node_modules/@google-cloud/firestore/build/src/index.js:1031:32)
```

**After Fix (Deployed Cloud Function with `assertHasToken` + Places API New):**
```bash
curl -X POST "https://us-central1-swift-ride-5ab75.cloudfunctions.net/getAutocomplete" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <anonymous_id_token>" \
  -d '{"data":{"query":"faisalabad","location":{"latitude":31.26323,"longitude":72.35179}}}'
```
*Response Received (Status 200 OK):*
```json
{
  "result": {
    "available": true,
    "predictions": [
      {
        "placeId": "ChIJqVyllahCIjkRxnEmk4iPxd4",
        "description": "Faisalabad, Pakistan",
        "mainText": "Faisalabad",
        "secondaryText": "Pakistan"
      },
      {
        "placeId": "ChIJnW66VLVcIjkRi-A6JKBjzrU",
        "description": "Faisalabad City, Pakistan",
        "mainText": "Faisalabad City",
        "secondaryText": "Pakistan"
      },
      {
        "placeId": "ChIJOSXGyqFcIjkRP9qCNXPICJo",
        "description": "Faisalabad International Airport, Airport Road, Faislabad Airport, Faisalabad, Pakistan",
        "mainText": "Faisalabad International Airport",
        "secondaryText": "Airport Road, Faislabad Airport, Faisalabad, Pakistan"
      },
      {
        "placeId": "ChIJcYKS9cZBIjkRtwdByRwj-_c",
        "description": "Faisalabad Interchange, Pindi Bhattian - Faisalabad Motorway, Faisalabad, Pakistan",
        "mainText": "Faisalabad Interchange",
        "secondaryText": "Pindi Bhattian - Faisalabad Motorway, Faisalabad, Pakistan"
      }
    ]
  }
}
```

*Cloud Functions Log excerpt after search:*
```log
D getautocomplete: {"verifications":{"auth":"VALID","app":"MISSING"},"message":"Callable request verification passed"}
```

---

## 3. Root Causes

1. **Root Cause 1: Cloud Function Crash on Firestore Document Read (`assertAuthenticated`)**
   - **File:** `functions/src/middleware/auth.ts:18`
   - **Response Code:** `HTTP 500 INTERNAL` (`gRPC 7 PERMISSION_DENIED`)
   - **Detail:** `assertAuthenticated` called `db.collection('users').doc(uid).get()`. The Cloud Run runtime service account (`113634488038-compute@developer.gserviceaccount.com`) lacks read permissions on Firestore. Autocomplete does not require a user profile.

2. **Root Cause 2: Double Fallback to Hardcoded Gazetteer Hiding Backend Failures**
   - **Files:** `lib/services/map_service.dart:232, 281` & `lib/presentation/rider/address_search_screen.dart:91`
   - **Detail:** Whenever the backend failed or returned empty results, `_fetchAutocomplete` fell back to `_searchLocalGazetteer`. Additionally, `AddressSearchScreen` explicitly fell back to `MapService.fallbackLocations` whenever results were empty and query length >= 2. Users saw the exact same 5 hardcoded landmarks regardless of their search query.

3. **Root Cause 3: Missing Anonymous Auth and Client Session Initialization**
   - **Files:** Google Cloud Identity Toolkit & `lib/services/auth_service.dart`
   - **Response Code:** `400 ADMIN_ONLY_OPERATION` on initial anonymous sign-in
   - **Detail:** Anonymous sign-in was disabled in the Firebase Console / Identity Toolkit configuration. Furthermore, `AuthService` had no `signInAnonymously()` method, and `AuthProvider` never initialized an anonymous session on bootstrap.

4. **Root Cause 4: Stationary Location Cache Rejection in Native iOS**
   - **File:** `ios/Runner/AppDelegate.swift:214`
   - **Response Code:** `LOCATION_TIMEOUT No GPS fix within 12s`
   - **Detail:** Core Location has `distanceFilter = 5.0`. A stationary device (or simulator) only fires `didUpdateLocations` once on launch. `AppDelegate.swift` previously rejected any cached location older than 60s (`timeIntervalSinceNow > -60`), causing all subsequent 4s polls from `LocationService.io` to fall through to a 12s timeout queue.

5. **Root Cause 5: Search UI Hardcoded Colors and Layout Overlap**
   - **Files:** `lib/presentation/rider/address_search_screen.dart:184` & `lib/presentation/rider/rider_home_screen.dart:340`
   - **Detail:** Search text input hardcoded `Colors.white` and `Colors.black87` instead of adapting to `AppColors.of(context)`, creating white-on-white illegibility on light surfaces. On `RiderHomeScreen`, the GPS banner and address card sat in disjointed overlays that collided with the bottom fare proposal sheet.

---

## 4. Fixes Applied

## Fix: Split Auth Middleware & Remove Firestore Read for Map Endpoints
**File:** `functions/src/middleware/auth.ts:12` & `functions/src/modules/maps/*.ts`
**Before:** Map functions called `assertAuthenticated`, which executed a Firestore read and failed with `7 PERMISSION_DENIED`.
**After:** Added `assertHasToken(request)` which verifies `request.auth.uid` is non-null with zero Firestore reads. Enabled `cors: true` on all 4 callable functions (`getAutocomplete`, `getPlaceDetails`, `reverseGeocode`, `getRoute`).
**Proof:**
```bash
curl -X POST "https://us-central1-swift-ride-5ab75.cloudfunctions.net/getAutocomplete" \
  -H "Authorization: Bearer <id_token>" -H "Content-Type: application/json" \
  -d '{"data":{"query":"faisalabad"}}'
# Output: HTTP 200 with real predictions array
```

## Fix: Permanently Remove Hardcoded Gazetteer Fallbacks
**File:** `lib/services/map_service.dart:108-181` & `lib/presentation/rider/address_search_screen.dart:38, 89-98`
**Before:** Failed queries returned `_knownLocations` (5 static landmarks).
**After:** Deleted `_knownLocations`, `_searchLocalGazetteer`, and `MapService.fallbackLocations`. `searchPlaces` returns an empty list on failure. `AddressSearchScreen` renders an empty state with "No places found" and a "Retry Search" button.
**Proof:**
`flutter test` runs with 129/129 tests passing.

## Fix: Auto-Provision Anonymous Auth Session on Boot
**File:** `lib/services/auth_service.dart:44` & `lib/providers/auth_provider.dart:32`
**Before:** Guest users had no Firebase session; Cloud Functions threw `unauthenticated`.
**After:** Added `signInAnonymously()` to `AuthService` and invoked it during `AuthProvider` initialization.
**Proof:**
Verified live token minting via Firebase Auth REST API with the Web/iOS API key.

## Fix: Fast-Path Location Return in Native iOS
**File:** `ios/Runner/AppDelegate.swift:212-228`
**Before:** Location updates older than 60s were discarded on stationary devices, triggering cascading 12s timeout errors.
**After:** `getCurrentLocation` returns `lastKnownLocation` or `locationManager.location` immediately if horizontal accuracy < 200m.
**Proof:**
```log
flutter: [LocationProvider] first real fix: 31.26323, 72.35179
# Zero LOCATION_TIMEOUT lines once fix acquired.
```

## Fix: Theme Dynamic Colors in Address Search Field
**File:** `lib/presentation/rider/address_search_screen.dart:180-210`
**Before:** `style: TextStyle(color: Colors.white)` hardcoded.
**After:** Replaced with `c.textPrimary`, `c.textMuted`, and `c.surfaceRaised` from `AppColors.of(context)`.
**Proof:**
Verified readability across light and dark surface renders.

## Fix: GPS Banner and Address Card Layout Hierarchy
**File:** `lib/presentation/rider/rider_home_screen.dart:339-370`
**Before:** GPS banner and Address Card were positioned in independent overlays that collided with the bottom fare proposal sheet.
**After:** Both are unified inside a single top-aligned `Column`: the GPS banner displays directly beneath `_buildAddressCard`, preventing any overlap with the bottom sheet.
**Proof:**
Layout verified across Compact, Mobile, Tablet, and Desktop widget tests.

---

## 5. Platform Matrix

| Feature         | iOS | Android | Web |
|-----------------|:---:|:-------:|:---:|
| GPS fix         | ✅  | ⬜      | ✅  |
| Place search    | ✅  | ⬜      | ✅  |
| Place resolve   | ✅  | ⬜      | ✅  |
| Reverse geocode | ✅  | ⬜      | ✅  |
| Route polyline  | ✅  | ⬜      | ✅  |
| Route options selector | ✅  | ⬜      | ✅  |

*Verification Status:*
- **Economically-Optimized Route Options & Economics Engine**:
  - Cloud Function `getRoute` deployed with Google Routes API multi-route calculation and economics engine (fuel, maintenance, tolls, commission, driver profit, profit/min).
  - Verified live via curl for Sargodha→Jhang (3 routes, labeled and sorted with FASTEST default) and Lahore→Islamabad (M2 motorway corridor).
  - Verified live on **iOS Simulator (`iPhone 17`)** with dynamic pill selection (Cheapest, Fastest, Best for Driver), real-time fare/driver earnings calculation, and polyline redraw.
  - Verified live on **Web (Chrome)** with multi-route options row, default selection, and driver earnings display.
- **iOS Simulator (`iPhone 17`, UDID: `C1D75089-85CD-4177-AB89-0EE621FE149B`)**:
  - Mac location (`31.5580, 74.3507`) applied via `xcrun simctl location`.
  - App booted with native location channel: `flutter: [LocationProvider] first real fix: 31.55800, 74.35070`.
  - Top card pinned pickup location at `31.5580, 74.3507` (Mayo Gardens, Lahore).
- **Web (Chrome on `localhost:8085`)**:
  - `[WEB FILE LOADED]` logged on boot, proving the conditional export dispatch routed correctly.
  - `hasGeolocation? = true` and `[WEB] ✓✓✓ FIX ACQUIRED: 31.26323, 72.35172` acquired via browser geolocation.
- **Android**:
  - Marked ⬜ (untested). No Android emulator is currently booted on this machine (`adb devices` returned 0 attached devices).

---

## 6. Manual Steps for the User

1. **Physical iPhone App Check Debug Token:**
   - App Check debug tokens are per-device. When running an Xcode development build on a physical iPhone, inspect the Xcode debug console for:
     ```
     [FirebaseAppCheck] Enter this debug secret into the allow list in the Firebase Console: <NEW_UUID>
     ```
   - Add that token in **Firebase Console → App Check → Apps → iOS app → Manage debug tokens**.
2. **App Check Enforcement in Production:**
   - App Check enforcement is currently disabled on Cloud Functions (`enforceAppCheck: false`) for local development. Do not re-enable enforcement in Firebase Console until physical devices and web domains are registered.

---

## 7. Remaining Risks

- **Firestore Security Rules for User Profile Read**:
  If non-map functions (rides, payments) call `assertAuthenticated`, the Cloud Run service account must either be granted Firestore reader permissions in IAM (`roles/datastore.user`), or Firestore rules must permit the operation.
- **Physical Device GPS Warmup**:
  A cold device starting indoors may take 5–10 seconds for initial satellite lock. The UI gracefully displays "Finding your location…" beneath the address card until the first fix arrives.
