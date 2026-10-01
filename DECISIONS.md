# SwiftRide Architectural Decisions & Technical Log (DECISIONS.md)

This document records the architectural decisions, trade-offs, and operational assumptions made during the design and development of the **SwiftRide** platform.

---

## 1. Hybrid Database Architecture: Cloud Firestore + Realtime Database (RTDB)

### Decision
- **Cloud Firestore** is used for transactional, relational, and structured data:
  - `users`: User profiles, roles, ratings, multi-device FCM tokens.
  - `drivers`: Vehicle specifications, verification status, subscription records, Stripe Connect metadata.
  - `rides`: Lifecycle states (`REQUESTED`, `ACCEPTED`, `DRIVER_ARRIVED`, `IN_PROGRESS`, `COMPLETED`, `CANCELLED`), negotiated fares, 4-digit verification PINs, safety flags.
  - `ride_offers`: Driver counter-offers for inDrive-style negotiation.
  - `payments`: Transaction records, Stripe PaymentIntent IDs, fee breakdowns.
  - `safety_events`: SOS alerts, prolonged unexpected stops, route deviations, crash alerts.
  - `shared_trips`: Ephemeral 24-hour public sharing tokens.
- **Firebase Realtime Database (RTDB)** is used exclusively for high-frequency location streaming:
  - `driver_locations/{driverId}`: Live GPS coordinates (`lat`, `lng`, `heading`, `speed`, `timestamp`) written every 2–3 seconds by active drivers.
  - `ride_tracking/{rideId}`: Real-time car position and ETA stream consumed by riders and web public share viewers.

### Rationale & Trade-offs
- **Cost**: Firestore charges per write/read document operation. Writing driver coordinates every 2 seconds via Firestore would generate ~1,800 writes/hour per driver, quickly exceeding free-tier limits and inflating costs. RTDB charges purely based on stored data and GB of download bandwidth, making high-frequency updates virtually free at regional scale.
- **Latency**: RTDB establishes persistent WebSockets with roundtrip latencies of ~10–20ms, producing silky-smooth vehicle marker animation compared to polling or document sync.
- **Audit Persistence**: A scheduled Cloud Function (`persistLocations`) batches RTDB positions into Firestore once per minute for legal/insurance dispute auditing while avoiding real-time write costs.

---

## 2. Business Model & Zero Commission Structure

### Decision
- **Year 1 (Launch Phase)**: Free for riders and drivers. **0.0% platform commission** is charged on rides.
- **Year 2+ (Sustainability Phase)**: Flat driver subscription model ($1.00/day, $15.00/month, or $150.00/year for unlimited rides at zero commission).
- **Target Market**: Regional cities where major incumbents (Uber, Lyft, inDrive) charge 13–25% commission.
- **Cancellation Policy**:
  - Prior to driver acceptance: **$0.00** (Free cancellation).
  - After acceptance, prior to driver arrival: **$2.00 fee**.
  - After driver arrives or during trip: **$5.00 fee**.
  - Driver cancellation: Recorded in driver rating and penalizes matching priority.

---

## 3. inDrive-Style Fair Price Negotiation (Bidding Model)

### Decision
- Riders propose an initial offer fare based on an algorithmic suggestion:
  $$\text{Fare}_{\text{suggested}} = \$2.00 + (\text{Distance}_{\text{km}} \times \$0.50) + (\text{Duration}_{\text{min}} \times \$0.10)$$
  Rounded to the nearest $\$0.50$.
- Drivers within proximity receive push notifications and can:
  1. Accept the rider's offer immediately.
  2. Counter-offer with quick increments ($+\$1$, $+\$2$) or custom amounts.
- Riders choose their preferred driver based on rating, vehicle model, ETA, and proposed fare.
- Acceptance triggers an atomic Firestore transaction (`acceptOffer`) to prevent double-booking.

---

## 4. 4-Digit Verification PIN (Wrong-Car Prevention)

### Decision
- When a ride is requested, a unique 4-digit PIN is cryptographically generated and saved in `rides/{rideId}`.
- The PIN is prominently visible on the rider's screen and must be verbally shared with the driver upon pickup.
- The driver app strictly prevents transitioning the ride to `IN_PROGRESS` until the correct PIN is entered.

---

## 5. Unified Flutter Codebase with Mode Switcher

### Decision
- Built as a single cross-platform Flutter application supporting Rider, Driver, and Admin roles.
- Features a top role-switcher app bar allowing instant switching between Rider, Driver, and Admin modes for seamless testing, demonstration, and multi-tenant mobile/web operations.
- State is managed via pure Flutter `CustomChangeNotifierProvider` with zero third-party state lock-in, ensuring reactive synchronization across map renders, active offers, driver online broadcasts, and admin fleet telemetry.

---

## 6. Gemini AI Provider: Gemini Developer API (Spark Plan Compatible)

### Decision
- Standardized strictly on the **Gemini Developer API** provider (`FirebaseAI.googleAI()`) rather than Vertex AI Gemini API.
- Default model: `gemini-3.8-flash`.

### Rationale & Trade-offs
- **Free Tier Eligibility**: The Gemini Developer API provider runs seamlessly on the Firebase Spark (free) plan without requiring a credit card or mandatory billing account, enabling zero-cost development and testing for the first ~5,000 monthly calls.
- **Cost Efficiency at Scale**: Input tokens cost $0.75 / 1M and output tokens cost $3.75 / 1M (through Dec 31, 2026), making AI assistance economically viable even at 100,000+ monthly rides.
- **Latency**: `gemini-3.8-flash` delivers sub-second response times for in-app conversational assistant turns and real-time RideCheck safety messages.

---

## 7. Firebase App Check: Mandatory Attestation & Zero Client Secrets

### Decision
- Client Flutter apps carry **zero Gemini API keys**.
- All mobile client requests to Gemini Developer API are authenticated and verified via **Firebase App Check** (Google Play Integrity on Android, DeviceCheck / App Attest on iOS).
- All Cloud Functions Gen 2 callable endpoints enforce `enforceAppCheck: true`.
- Server-side Gemini calls (e.g. daily scheduled earnings batch) retrieve their API key strictly from Google Cloud Secret Manager or environment variables.

### Rationale
- Prevents API key extraction from decompiled APK/IPA packages.
- Protects the project from billing abuse and malicious bot spam without requiring complex custom auth proxying.

---

## 8. Cost Control Strategy & 24-Hour Firestore Caching

### Decision
1. **Token Budgets**:
   - In-app chatbot responses capped at `maxOutputTokens: 256`.
   - AI Insights (earnings advisor, vehicle health, route optimizer) capped at `maxOutputTokens: 512`.
   - Low thinking level (`ThinkingLevel.low` / `thinkingBudget: 0`) applied to suppress costly reasoning chain tokens.
2. **24-Hour Caching**:
   - Driver daily earnings forecasts and vehicle maintenance alerts are cached in Firestore (`ai_insights` collection) for 24 hours.
   - Repeated dashboard opens serve cached documents with zero Gemini API calls, unless the driver explicitly taps "Regenerate".
3. **Emergency Circuit Breaker**:
   - Integrated with Firebase Remote Config (`ai_features_enabled: false`) to instantly disable all AI features fleet-wide if Google Cloud budget thresholds are approached.

---

## 9. Glassmorphism & Micro-Animation Design Language

### Decision
- Integrated custom hardware-accelerated frosted glass containers (`GlassContainer`) with dual-plane backdrop blur, layered shadows, and subtle ambient border glows.
- Integrated `StaggeredEntryWidget` (cascading slide, fade, and scale) and `PulsingGlowWidget` (interactive breathing beacon) for rich tactile feedback.
- Designed pixel-perfect responsive layouts spanning compact handsets (360px), standard smartphones, tablets (768px), and desktop widescreen monitors (1440px+).

---

## 10. iOS Production Readiness & App Store Submission Architecture

### Decision
1. **Bundle Identifier Alignment**:
   - Set iOS and Android bundle identifier to `com.dartnexuslab.swiftri` across `project.pbxproj`, `GoogleService-Info.plist`, `ExportOptions.plist`, and `build.gradle.kts`.
2. **Branding & App Display Name**:
   - Configured `CFBundleDisplayName` as `Swift Ride` and `CFBundleName` as `Swft Ride` to fulfill exact naming requirements.
   - Converted master branding asset `assets/Gemini_Generated_Image_5pjlpe5pjlpe5pjl.jpeg` (2048x2048) into all 15 iOS app icon scales (`Icon-App-*`) in `Assets.xcassets/AppIcon.appiconset/`, including the 1024x1024 marketing icon.
3. **Apple Privacy Manifest Compliance (ITMS-91061)**:
   - Authored `ios/Runner/PrivacyInfo.xcprivacy` declaring data collection (Precise Location, Coarse Location, User ID, Crash Diagnostics) and Required Reason APIs (`UserDefaults` `CA92.1`, `FileTimestamp` `C617.1`, `SystemBootTime` `35F9.1`, `DiskSpace` `E174.1`).
4. **Permissions & Background Execution**:
   - Fully declared transparent, user-facing permission descriptions in `Info.plist` for Location (When In Use, Always & Background), Camera & Photos, Microphone & Speech Recognition, Motion Sensors, Contacts, and Bluetooth.
   - Configured background execution modes for `location`, `remote-notification`, and `fetch`.
5. **App Store Distribution Automation**:
   - Provisioned `ios/ExportOptions.plist` for `app-store` method with automatic signing and bitcode disabled.
   - Added automated GitHub Actions workflow (`.github/workflows/ios-release.yml`) for automated TestFlight builds.

---

## 11. Google Maps SDK & Cloud Proxies Architecture

### Decision
1. **Real Google Maps SDK via `google_maps_flutter`**:
   - Completely deprecated and removed the mock canvas implementation (`InteractiveMapCanvas`).
   - Integrated official `google_maps_flutter` (v2.10+) with platform packages (`google_maps_flutter_android`, `google_maps_flutter_ios`).
   - Created `GoogleMapView` widget supporting four operational modes: `viewOnly`, `pinPicker` (with 350ms reverse-geocode debouncing), `navigation` (following user location and heading), and `liveTracking` (following moving driver marker).
   - Created `MapMarkers` factory providing standardized pickup, dropoff, and rotated heading driver markers.
2. **Native Key Isolation**:
   - Client API keys are restricted directly in native manifests (`Info.plist` -> `GMSApiKey`, `AndroidManifest.xml` -> `com.google.android.geo.API_KEY`).
   - Android `minSdkVersion` elevated to 21 to meet Google Maps SDK Android requirements.
3. **Zero Client Secrets for Web Services**:
   - Client never calls Google Maps REST web services directly.
   - All routing (`getRoute`), places autocomplete (`getAutocomplete`), place details (`getPlaceDetails`), and reverse geocoding (`reverseGeocode`) are routed through Cloud Functions Gen 2 backed by Google Cloud Secret Manager (`GOOGLE_MAPS_SERVER_KEY`) and protected with Firebase App Check.
4. **Cost Optimization & Safeguards**:
   - Pin dragger debouncing at 350ms avoids flooding the Geocoding API while moving the map.
   - Places Autocomplete utilizes session tokens to bill per search session instead of per keystroke.
   - Firestore caching layer caches coordinates and reverse geocode results for 24h.


