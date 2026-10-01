# Security Policy — SwiftRide

At **SwiftRide**, user safety and platform security are our top priorities. This document details our security architecture, supported versions, and how to responsibly report vulnerabilities.

---

## 1. Supported Versions

We actively provide security patches, dependency updates, and hotfixes for the following versions:

| Version | Supported | Minimum OS Compatibility |
|---|---|---|
| **1.0.x (Current)** | ✅ Yes | iOS 15.0+ / Android 8.0+ (API 26+) |
| **< 1.0.0** | ❌ No | Deprecated development builds |

---

## 2. Core Security Architecture & Safeguards

SwiftRide implements defense-in-depth across the Flutter mobile applications and Firebase Gen 2 cloud backend:

### 2.1 Firebase App Check Enforcement
- **Device Attestation**: All callable Cloud Functions and Firebase AI Logic Gemini endpoints require valid **Firebase App Check** tokens (`enforceAppCheck: true`).
- **Platforms**:
  - **Android**: Google Play Integrity API.
  - **iOS**: Apple DeviceCheck & App Attest providers.
- **Zero Client Secrets**: The mobile application does **not** store Gemini API keys or Stripe Secret Keys. All authenticated server actions run server-side via Google Cloud Secret Manager.

### 2.2 Granular Firestore & Realtime Database Security Rules
- **Authentication**: Anonymous or unauthenticated requests are rejected.
- **Ownership Verification**: Users can only read and write their own documents (`request.auth.uid == userId`).
- **Atomic State Transitions**: Ride status transitions (`REQUESTED` → `OFFERED` → `ACCEPTED` → `ARRIVED` → `IN_PROGRESS` → `COMPLETED`) are strictly enforced via server-side Cloud Function transactions to prevent race conditions and double-acceptance.

### 2.3 Trip Verification & Safety
- **4-Digit Safety PIN**: A secure, randomly generated 4-digit PIN is generated upon ride booking. Drivers cannot transition a ride to `IN_PROGRESS` without verifying the PIN.
- **RideCheck Anomaly Detection**: Cloud Function monitors active ride telemetry (long stops, route deviation, crash detection) and triggers instant check-ins.
- **Location Ephemerality**: High-frequency driver GPS locations in Realtime Database are scoped to active trips and purged upon completion.

### 2.4 Financial & Payment Security
- **PCI-DSS Level 1 Compliance**: All payment processing is delegated to **Stripe Connect**. Cardholder data never touches SwiftRide servers or client memory.
- **Zero Platform Fee Auditing**: Year 1 driver earnings are calculated directly from verified trip distances and deposited via Stripe Express accounts.

---

## 3. Reporting a Vulnerability

We value the security research community. If you discover a vulnerability or security flaw, please report it responsibly:

### How to Report
1. **Email**: Send your findings directly to **`security@swiftride.app`** or open a private advisory on [GitHub Security Advisories](https://github.com/aliasghar08/Swift-Ride/security/advisories/new).
2. **Details to Include**:
   - Vulnerability type and affected component (Flutter app, Cloud Function, Firestore Rule)
   - Step-by-step reproduction instructions or Proof-of-Concept (PoC)
   - Potential impact of the issue
   - Any suggested remediations

### What NOT to Do
- **Do not** disclose vulnerabilities publicly or to third parties before a fix has been released.
- **Do not** perform attacks that degrade service availability (e.g., DoS/DDoS).
- **Do not** access or modify user data that does not belong to your test account.

---

## 4. Response & Remediation SLA

| Phase | Target Timeline |
|---|---|
| **Acknowledgment & Triage** | Within **24–48 hours** |
| **Severity Assessment & Patch Development** | **3–7 business days** |
| **Public Advisory & Release** | Once hotfix is verified and deployed |

We offer public acknowledgment in our security release notes for valid, responsibly disclosed vulnerabilities.
