# SwiftRide Firebase Authentication & Firestore Data Setup Guide

This document outlines the complete production setup for **Firebase Authentication (Phone OTP)**, **Cloud Firestore Data Models**, **Security Rules**, and **Composite Indexes** for the SwiftRide zero-commission ride-hailing platform.

---

## 1. Firebase Authentication Setup (Phone Auth)

SwiftRide uses Firebase Phone Authentication with one-time SMS verification codes (OTP).

### Step 1: Enable Phone Provider in Firebase Console
1. Navigate to [Firebase Console](https://console.firebase.google.com/) and select the SwiftRide project.
2. In the left navigation, click **Build** → **Authentication**.
3. Under the **Sign-in method** tab, click **Add new provider** (or select **Phone** if already listed).
4. Toggle **Enable** to ON and click **Save**.

### Step 2: Configure Test Phone Numbers (Zero Cost & CI/CD Bypass)
To prevent carrier SMS charges, avoid rate-limiting quotas, and support automated UI tests and App Store review:
1. In the **Phone** provider configuration modal, expand **Phone numbers for testing (optional)**.
2. Add the following test credentials:
   - **Phone Number:** `+923000000000` (or `+92 300 0000000`)  
     **Verification Code:** `123456`
   - **Phone Number:** `+923001234567` (or `+92 300 1234567`)  
     **Verification Code:** `123456`
3. Click **Save**. These numbers allow instant sign-in without sending real SMS messages.

### Step 3: Android SHA Fingerprints & Play Integrity
For Android to handle automatic SMS verification and reCAPTCHA fallback:
1. Generate the SHA-1 and SHA-256 certificate fingerprints from your local debug key:
   ```bash
   cd android
   ./gradlew signingReport
   ```
2. In the output, locate `Task :app:signingReport` for the `debug` and `release` variants:
   - Copy the `SHA1` fingerprint (e.g. `AA:BB:CC:...`).
   - Copy the `SHA256` fingerprint (e.g. `11:22:33:...`).
3. In Firebase Console, go to **Project settings** (gear icon) → **General**.
4. Scroll to **Your apps**, select the Android app (`com.swiftride.swiftride`), and click **Add fingerprint**.
5. Paste the SHA-1 and SHA-256 fingerprints.
6. Re-download `google-services.json` and replace `android/app/google-services.json`.

### Step 4: iOS APNs & Push Notifications Setup
For iOS silent background push notifications for phone verification and reCAPTCHA:
1. **Apple Developer Portal:**
   - Go to **Certificates, Identifiers & Profiles** → **Keys**.
   - Create an **Apple Push Notifications service (APNs) key (.p8)**. Note the **Key ID** and your **Team ID**.
2. **Firebase Console:**
   - In **Project settings** → **Cloud Messaging** tab.
   - Under **Apple app configuration**, click **Upload** under *APNs Authentication Key*.
   - Upload the `.p8` file and enter the Key ID and Team ID.
3. **Xcode Project Configuration:**
   - Open `ios/Runner.xcworkspace` in Xcode.
   - Select the `Runner` target → **Signing & Capabilities**.
   - Click `+ Capability` and add **Push Notifications**.
   - Click `+ Capability` and add **Background Modes**, checking **Remote notifications**.
   - Under the **Info** tab → **URL Types**, ensure the reverse client ID from `GoogleService-Info.plist` is registered as a URL Scheme for reCAPTCHA redirect.

---

## 2. Cloud Firestore Data Schema

All monetary values (fares, bids, earnings, subscriptions) are strictly denominated in **Pakistani Rupee (PKR)**.

### Collections Overview

| Collection | Document ID | Description |
| :--- | :--- | :--- |
| `users` | `userId` (Firebase Auth UID) | User profiles (rider, driver, admin) |
| `drivers` | `driverId` (Firebase Auth UID) | Driver verification, vehicle info, and telemetry |
| `rides` | `rideId` (`ride_...`) | Ride lifecycle, route coordinates, PIN, and PKR fare |
| `ride_offers` | `offerId` (`offer_...`) | Driver bidding counter-offers in PKR |
| `payments` | `paymentId` (`pay_...`) | Settlement records and receipts |
| `safety_events` | `eventId` (`sos_...` / `safe_...`) | SOS emergency alerts and route anomalies |
| `shared_trips` | `shareToken` (12 chars) | Public real-time tracking documents |
| `ai_conversations`| `conversationId` | AI voice & text chat session history |
| `ai_insights` | `insightId` | AI earnings insights and heatmaps |

---

### Collection Schemas

#### 1. `users/{userId}`
```typescript
interface UserDocument {
  phone: string;                // e.g. "+923001234567"
  email: string | null;         // optional email
  fullName: string;             // e.g. "Alex Morgan"
  role: "rider" | "driver" | "admin";
  rating: number;               // 0.0 - 5.0 (default 5.0)
  totalRides: number;           // non-negative integer
  fcmTokens: string[];          // device push tokens (max 10)
  location?: {
    geopoint: GeoPoint;
    updatedAt: Timestamp;
  } | null;
  createdAt: Timestamp;         // Immutable server timestamp
  updatedAt: Timestamp;
}
```

#### 2. `drivers/{driverId}`
```typescript
interface DriverDocument {
  userId: string;               // matches auth.uid
  licenseNumber: string;        // e.g. "ISB-DL-48201"
  vehicleMake: string;          // e.g. "Toyota"
  vehicleModel: string;         // e.g. "Corolla"
  vehicleYear: number;          // e.g. 2022
  vehiclePlate: string;         // e.g. "LEE-4400"
  vehicleColor: string;         // e.g. "Midnight Black"
  isVerified: boolean;          // admin/cloud function controlled
  isOnline: boolean;            // driver toggle
  subscriptionStatus: "TRIAL" | "ACTIVE" | "EXPIRED";
  subscriptionExpiresAt: Timestamp;
  stripeAccountId?: string | null;
  payoutStatus: "pending" | "ready_for_payout" | "paid_out";
  rating: number;               // e.g. 4.95
  totalRides: number;
  totalEarnings: number;        // total PKR earned (100% driver kept)
  currentLocation: {
    geopoint: GeoPoint;
    geohash: string;            // 5-character geohash for radius querying
  };
  createdAt: Timestamp;
  updatedAt: Timestamp;
}
```

#### 3. `rides/{rideId}`
```typescript
interface RideDocument {
  riderId: string;              // UID of rider (immutable)
  driverId: string | null;      // UID of assigned driver
  status: "REQUESTED" | "ACCEPTED" | "DRIVER_ARRIVED" | "IN_PROGRESS" | "COMPLETED" | "CANCELLED";
  pickup: {
    geopoint: GeoPoint;
    address: string;
    geohash: string;
  };
  dropoff: {
    geopoint: GeoPoint;
    address: string;
    geohash: string;
  };
  offeredFare: number;          // Rider proposed fare in PKR
  acceptedFare: number | null;  // Agreed negotiated fare in PKR
  suggestedFare: number;        // Benchmark fare in PKR
  distanceKm: number;           // Road distance in km
  durationMin: number;          // Estimated duration in minutes
  commissionAmount: number;     // PKR 0.00 (Zero commission in Year 1)
  paymentIntentId: string | null;
  paymentStatus: "pending" | "paid" | "failed";
  safetyFlags: string[];
  shareToken: string | null;    // 12-char public token
  pin: string;                  // 4-digit trip start safety PIN
  createdAt: Timestamp;
  completedAt: Timestamp | null;
}
```

#### 4. `ride_offers/{offerId}`
```typescript
interface RideOfferDocument {
  rideId: string;               // linked ride ID
  driverId: string;             // UID of offering driver
  driverName: string;
  counterFare: number;          // Counter-bid in PKR
  etaMinutes: number;           // Pickup ETA
  vehicleSummary: string;       // e.g. "Silver Toyota Corolla (LEE-4400)"
  driverRating: number;         // e.g. 4.95
  status: "PENDING" | "ACCEPTED" | "REJECTED" | "EXPIRED";
  createdAt: Timestamp;
}
```

#### 5. `safety_events/{eventId}`
```typescript
interface SafetyEventDocument {
  rideId: string;
  type: "SOS" | "LONG_STOP" | "ROUTE_DEVIATION" | "CRASH_DETECTED";
  geopoint: GeoPoint;
  metadata: {
    message?: string;
    alertLevel?: "CRITICAL" | "WARNING";
    triggeredBy?: string;
    dispatchedAt?: string;
  };
  resolvedAt: Timestamp | null;
  createdAt: Timestamp;
}
```

#### 6. `shared_trips/{shareToken}`
```typescript
interface SharedTripDocument {
  token: string;
  rideId: string;
  riderName: string;
  driverName?: string;
  vehicleSummary?: string;
  pickupAddress: string;
  dropoffAddress: string;
  status: string;
  driverLocation?: {
    lat: number;
    lng: number;
  };
  expiresAt: string;
  createdAt: Timestamp;
}
```

---

## 3. Firestore Security Rules

Production security rules are defined in `firestore.rules`.

### Key Security Policies:
1. **User Identity & Role-Based Access Control (RBAC):**
   - Users can only read and write their own profile (`users/{userId}`).
   - Admins (via Firebase custom token claim `admin: true` or `users/{uid}.role == 'admin'`) have full administrative read/write privileges.
   - Users cannot grant themselves the `admin` role upon creation or profile update.
2. **Driver Verification Hardening:**
   - Drivers cannot self-verify (`isVerified == false` enforced on document creation).
   - Only admins or Cloud Functions can toggle `isVerified` and modify subscription tiers.
3. **Ride Lifecycle State Machine:**
   - Enforces legal status transitions:
     - `REQUESTED` → `ACCEPTED` or `CANCELLED`
     - `ACCEPTED` → `DRIVER_ARRIVED` or `CANCELLED`
     - `DRIVER_ARRIVED` → `IN_PROGRESS` or `CANCELLED`
     - `IN_PROGRESS` → `COMPLETED` or `CANCELLED`
   - `riderId` and `createdAt` are strictly immutable.
4. **Driver Bidding Integrity:**
   - Drivers can only submit offers for rides with their own authenticated `driverId`.
   - Offers can only be accepted by the rider who owns the corresponding ride request.
5. **Public Shared Trips:**
   - `shared_trips/{shareToken}` allows unauthenticated public read access for friends/family with the unique 12-character token. Creation requires an authenticated user.

### Deploying Security Rules
```bash
firebase deploy --only firestore:rules
```

---

## 4. Composite Indexes

Composite indexes are defined in `firestore.indexes.json` to support high-throughput, multi-field queries.

### Required Index Definitions:

1. **`rides` — Available Requests Query**
   - Fields: `status` ASC, `createdAt` DESC
   - Query: Driver cockpit streaming nearby open ride requests.

2. **`rides` — Rider Ride History**
   - Fields: `riderId` ASC, `createdAt` DESC
   - Query: Rider active and past rides list.

3. **`rides` — Driver Ride History**
   - Fields: `driverId` ASC, `createdAt` DESC
   - Query: Driver earnings history and active dispatch.

4. **`ride_offers` — Rider InDrive Bidding Cockpit**
   - Fields: `rideId` ASC, `status` ASC, `counterFare` ASC
   - Query: Real-time driver counter-offers sorted by lowest fare.

5. **`ride_offers` — Driver Offer History**
   - Fields: `driverId` ASC, `createdAt` DESC
   - Query: Active and pending bids submitted by the driver.

6. **`drivers` — Geospatial Online Drivers**
   - Fields: `isOnline` ASC, `isVerified` ASC, `currentLocation.geohash` ASC
   - Query: Finding available, verified drivers within a geohash bounding box.

7. **`safety_events` — Ride Incident Log**
   - Fields: `rideId` ASC, `createdAt` DESC
   - Query: Real-time emergency audit trail for a ride.

8. **`payments` — User Transaction History**
   - Fields: `userId` ASC, `createdAt` DESC
   - Query: User receipts and payment logs.

### Deploying Composite Indexes
```bash
firebase deploy --only firestore:indexes
```

---

## 5. Offline Fallback & Testing Architecture

To enable offline development, unit tests, and continuous integration environments without requiring live Firebase instances:

1. **`AuthService`**:
   - Detects `Firebase.apps.isNotEmpty`.
   - If uninitialized (e.g. `flutter test`), it returns mock credentials and dispatches mock verification tokens (`mock_verification_id_...`) with test token `123456`.
2. **`FirestoreUserService`, `FirestoreRideService`, `FirestoreDriverService`, `FirestoreSafetyService`**:
   - Maintain in-memory synchronized caches (`_memoryCache`, `_memoryRides`, `_memoryDrivers`, `_memoryEvents`).
   - If Firestore is disconnected or in test runner, operations update the memory store, ensuring 100% test reliability with zero network flakiness.

---

## 6. Verification & Test Commands

Run the complete test suites to verify that the Flutter application and Cloud Functions pass all tests:

```bash
# 1. Analyze Dart & Flutter Code (Expect: 0 issues)
flutter analyze

# 2. Run All Flutter Unit & Widget Tests (Expect: 41/41 passing)
flutter test

# 3. Run Specific Auth & Firestore Test Suite
flutter test test/auth_and_firestore_test.dart

# 4. Run Cloud Functions Backend Tests (Expect: 11/11 passing)
cd functions && npm test
```
