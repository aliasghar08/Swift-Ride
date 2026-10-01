# SwiftRide Diagnostic Bug Report: Map Rendering & Fare Calculation

**Date:** October 2, 2026  
**Simulator Platform:** iOS 27.0 (iPhone 17)  
**Status:** In Progress / Remediating

---

## 1. Diagnostic Findings

### Diagnostic 1: `google_maps_flutter` in `pubspec.yaml`
```bash
$ grep "google_maps_flutter" pubspec.yaml
  google_maps_flutter: ^2.10.0
  google_maps_flutter_android: ^2.21.0
  google_maps_flutter_ios: ^2.18.6
```
**Finding:** `google_maps_flutter` was declared in `pubspec.yaml`, and additional native runner dependencies (`google_maps_flutter_android`, `google_maps_flutter_ios`, `flutter_polyline_points`, `geolocator`, `geocoding`) have now been verified and resolved.

---

### Diagnostic 2: Contents of `lib/presentation/common/interactive_map_canvas.dart`
```
File Status: NOT PRESENT (Already refactored / superseded by GoogleMap widget).
```
**Detailed Cause of White Screen & Floating Pin:**
The blank white screen was **NOT** an HTML canvas mock — it was the official `GoogleMap` widget failing to render map tiles because:
1. `ios/Runner/Info.plist` had `GMSApiKey` set to placeholder `YOUR_GOOGLE_MAPS_IOS_API_KEY`. Without a valid Google Cloud Maps SDK for iOS API key, the Google Maps renderer cannot authenticate with Google tile servers and displays a blank background.
2. In `lib/presentation/common/google_map_view.dart` (lines 165-186), a custom `Icon(Icons.location_pin)` was overlaid directly in the center of the `Stack` for `MapMode.pinPicker`:
```dart
// Center pin for pin-picker mode
if (widget.mode == MapMode.pinPicker)
  const IgnorePointer(
    child: Center(
      child: Padding(
        padding: EdgeInsets.only(bottom: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_pin, size: 48, color: Colors.redAccent),
            ...
```
Combined with the unauthenticated Google Maps tile view, this appeared visually as a blank box with a lone floating pin.

---

### Diagnostic 3: Output of `grep -rn "GoogleMap(" lib/`
```bash
$ grep -rn "GoogleMap(" lib/
lib/presentation/common/google_map_view.dart:141:        GoogleMap(
```
**Finding:** A `GoogleMap` widget exists in `lib/presentation/common/google_map_view.dart`. Per the prompt instructions, we are creating the standalone `lib/presentation/common/real_map_view.dart` with standard controller callbacks, lifecycle handling, and direct GoogleMap rendering.

---

## 2. Root Cause Analysis of Coordinate & Fare Mismatch

1. **Bug 2 — Coordinate & Distance Mismatch**:
   - `AppConstants.defaultLat` and `AppConstants.defaultLng` were set to `37.7749, -122.4194` (San Francisco).
   - In `RiderViewModel`, initial pickup location was pulled from `LocationProvider`, pointing to San Francisco, while the default dropoff text was set to `"Islamabad International Airport (ISB)"`.
   - `_estimatedDistanceKm = 8.5` and `_estimatedDurationMin = 18.0` were hardcoded initial defaults in `RiderViewModel` instead of recalculating from real origin and destination coordinates.
   - **Fix:** Set platform default coordinates to **Islamabad, Pakistan** (`33.6844, 73.0479`), default dropoff to Islamabad Airport (`33.5605, 72.8518`), and dynamically query route metrics via `calculateRoute` and `estimateRoute`.

2. **Bug 3 — Currency Inconsistency**:
   - Backend functions (`functions/src/config/constants.ts`) and client pricing constants (`AppConstants`) standardize on **PKR**:
     - `baseFare = 150.0` (PKR 150)
     - `perKmFare = 45.0` (PKR 45/km)
     - `perMinFare = 5.0` (PKR 5/min)
     - `currencyCode = 'PKR'`
     - `currencySymbol = 'Rs '`
   - All legacy mentions of USD and mismatched rates are eliminated.
