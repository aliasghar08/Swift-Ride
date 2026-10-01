# 🚖 SwiftRide — Zero Commission Ride-Hailing Platform

[![Flutter](https://img.shields.io/badge/Flutter-3.47.5-02569B?logo=flutter)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Gen_2-FFCA28?logo=firebase)](https://firebase.google.com)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.6-3178C6?logo=typescript)](https://www.typescriptlang.org)
[![Stripe](https://img.shields.io/badge/Stripe-Connect-635BFF?logo=stripe)](https://stripe.com)

**SwiftRide** is an autonomous, production-ready ride-hailing platform built with **Flutter** (frontend) and **Firebase Gen 2** (backend). Unlike incumbent ride-hailing platforms (Uber, Lyft, inDrive) that extract 13–25% commission from drivers, SwiftRide offers **0% commission for riders and drivers for the first year**.

---

## 🏛️ Architectural Overview

```
                      ┌──────────────────────────────────────┐
                      │          Flutter Client              │
                      │  (Rider • Driver • Admin Dashboard)  │
                      └──────────────┬───────────────────────┘
                                     │
                 ┌───────────────────┴───────────────────┐
                 │                                       │
     (State / Transactions)                     (Live GPS Broadcast)
                 │                                       │
                 ▼                                       ▼
    ┌─────────────────────────┐             ┌─────────────────────────┐
    │     Cloud Firestore     │             │    Realtime Database    │
    │  • Users & Profiles     │             │  • driver_locations     │
    │  • Rides & Offers       │             │    (updates every 2-3s) │
    │  • Payments & Safety    │             │  • ride_tracking        │
    └────────────┬────────────┘             └────────────┬────────────┘
                 │                                       │
                 └───────────────────┬───────────────────┘
                                     │
                                     ▼
                      ┌──────────────────────────────┐
                      │    Cloud Functions Gen 2     │
                      │       (Node.js 20 TS)        │
                      │  • inDrive Bidding Engine    │
                      │  • Geohash Driver Matching   │
                      │  • Stripe PaymentIntents     │
                      │  • Scheduled Subscriptions   │
                      └──────────────────────────────┘
```

---

## 🚀 Key Advantages of This Stack

1. **Two Databases, One Purpose Each**:
   - **Cloud Firestore**: Complex queries, transactional integrity, and atomic driver offer acceptance.
   - **Realtime Database (RTDB)**: High-frequency driver GPS coordinate streaming every 2–3 seconds at ~10ms latency and minimal bandwidth cost.
2. **0% Commission & Fair Price Negotiation**:
   - Suggested formula: $\$2.00 \text{ base} + (\$0.50 \times \text{km}) + (\$0.10 \times \text{min})$.
   - Riders set proposed fares; nearby drivers counter-offer (+$1, +$2, match).
3. **4-Digit Safety PIN Verification**:
   - Eliminates wrong-car incidents. Driver cannot start trip until entering the rider's 4-digit code.
4. **Driver Instant Payouts**:
   - Connected with Stripe Connect Express for instant debit card cash-outs.
5. **Share My Trip & SOS Emergency**:
   - Generates public web tracking links (`/track?token=...`) allowing contacts to track rides without installing the app.

---

## 📂 Project Directory Structure

```
SwiftRide/
├── lib/
│   ├── core/
│   │   ├── constants/           # AppConstants (fare parameters, pricing, geohash)
│   │   ├── routing/             # GoRouter setup with role switcher & deep-links
│   │   ├── services/            # SwiftRideNotifier Riverpod 3.x state engine
│   │   └── theme/               # AppTheme (Light mode rider, Dark mode driver)
│   ├── domain/
│   │   └── models/              # Clean models (User, Driver, Ride, Payment, Safety)
│   └── presentation/
│       ├── common/              # InteractiveMapCanvas, ModeAppBar, SharedTripScreen
│       ├── rider/               # RiderHomeScreen (inDrive bidding, fare sheet, tracking)
│       ├── driver/              # DriverHomeScreen (RTDB broadcaster, PIN verification)
│       └── admin/               # AdminDashboardScreen (KPIs, Driver verification queue)
├── functions/                   # Firebase Cloud Functions Gen 2 (TypeScript)
│   ├── src/
│   │   ├── config/              # Firebase Admin init, constants, Stripe
│   │   ├── middleware/          # Auth assertions, Zod validation
│   │   ├── modules/             # Auth, Rides, Drivers, Payments, Maps, Safety, Admin
│   │   ├── triggers/            # onRideCreated, onRideUpdated, onPaymentCreated
│   │   └── scheduled/           # Subscriptions, weekly reports, stale ride cleanup
│   └── tests/                   # Vitest unit tests (Fare logic, Geohash bounds)
├── firebase.json                # Emulators, hosting, functions, rules config
├── firestore.rules              # Strict prototype rules with domain validators
├── firestore.indexes.json       # Geospatial compound query indexes
├── database.rules.json          # RTDB rules for live location streaming
├── storage.rules               # Driver documents and photo verification rules
├── DECISIONS.md                 # Technical decisions and trade-offs log
└── NEXT_STEPS.md                # Production launch & deployment checklist
```

---

## 🧪 Testing & Verification

### Run Flutter Tests & Static Analysis
```bash
# Verify widget tests and role switcher
flutter test

# Verify clean static analysis (0 warnings/errors)
flutter analyze
```

### Run Cloud Functions Tests & Build
```bash
cd functions
npm test        # Vitest unit tests
npm run build   # TypeScript compilation
```

---

## 💻 Running the App

```bash
# Run on macOS desktop
flutter run -d macos

# Run on Chrome (Web Admin & Rider)
flutter run -d chrome

# Run on mobile simulator (iOS / Android)
flutter run
```
