# Privacy Policy for SwiftRide

**Last Updated:** October 17, 2026  
**Effective Date:** October 17, 2026  
**Application Name:** SwiftRide (Swift Ride)[cite: 10]  
**Package / Bundle ID:** `com.dartnexuslab.swiftride`[cite: 10]  
**Developer / Publisher:** DartNexusLab[cite: 10]  
**Contact Email:** privacy@dartnexuslab.com  

---

## 1. Introduction

DartNexusLab ("we", "our", or "us") operates the **SwiftRide** mobile application[cite: 10]. SwiftRide is a zero-commission, peer-to-peer ride-hailing and smart bidding platform connecting passengers ("Riders") with independent drivers ("Drivers")[cite: 10].

This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you use our mobile application across Android and iOS platforms. By downloading, accessing, or using SwiftRide, you agree to the collection and use of information in accordance with this policy.

---

## 2. Information We Collect

### A. Personal Identification Data
- **Phone Number:** Collected during registration and verified via secure Firebase Phone Authentication (SMS One-Time Passwords)[cite: 10]. Used as your primary account identifier.
- **Profile Information:** Full display name, optional profile picture, and user role (`Rider` or `Driver`)[cite: 10].
- **Driver Specific Data:** Vehicle make, model, registration year, license plate number, color, and driver verification documents (for driver accounts).

### B. Location Information (Foreground and Background)
Location services are fundamental to the operation of the SwiftRide platform[cite: 10]:
- **Foreground Location:** Collected while the application is active on your screen to identify your current pickup location, search nearby landmarks, calculate distance, and render map routes[cite: 10].
- **Background Location (Drivers Only):** When a driver is marked "Online" or engaged in an active trip, SwiftRide collects precise GPS coordinates even when the app is running in the background or minimized[cite: 10]. This ensures riders receive accurate real-time driver ETA, live turn-by-turn tracking, and safety monitoring[cite: 10].
- **Rider Background Location:** Riders' location is only accessed in the foreground or while actively sharing a live trip link for safety purposes.
- *Control:* You can enable or disable location services at any time through your device settings, though key features like ride booking and driver dispatch will be disabled.

### C. On-Device AI & Pricing Telemetry
- SwiftRide incorporates an on-device machine learning model (TensorFlow Lite) to calculate suggested "Sweet-Spot" fares based on trip distance, estimated duration, time of day, and regional demand in Punjab (e.g., Jhang and surrounding districts)[cite: 10].
- **On-Device Execution:** Fare prediction inference runs locally on your smartphone device[cite: 10]. We do not transmit sensitive behavioral profiles or continuous sensor feeds to external AI servers for model execution.

### D. Safety & Emergency Data
- **SOS Alerts:** If you trigger the in-app SOS safety button, the app records your immediate GPS coordinates, timestamp, and active ride ID to dispatch safety logs and notify designated emergency contacts or authorities.
- **Trip Sharing Tokens:** Public, time-limited, encrypted share tokens generated when you choose to share your live ride status with friends or family.

### E. Device & Usage Telemetry
- **Push Notification Tokens:** Firebase Cloud Messaging (FCM) tokens required to deliver real-time ride proposals, counter-offers, driver arrival alerts, and in-app chat messages[cite: 10].
- **Technical Logs:** Device model, operating system version, crash diagnostics, and network connection status used solely for platform stability and debugging.

---

## 3. How We Use Your Information

We use the collected information for the following purposes:
1. **Ride Matching & Bidding:** Enabling riders and drivers to propose, negotiate, and agree upon fares directly[cite: 10].
2. **Navigation & Mapping:** Displaying detailed turn-by-turn route previews, highway cues, and navigation via Google Maps Platform and OpenStreetMap APIs[cite: 10].
3. **Safety & Verification:** Verifying phone numbers to prevent fraudulent accounts, authenticating drivers, validating boarding PINs, and supporting emergency safety events[cite: 10].
4. **Push Communications:** Alerting drivers to new ride requests in their vicinity and notifying riders when their ride offer is accepted[cite: 10].
5. **Platform Quality & Support:** Diagnosing app crashes, preventing malicious activities, and responding to user support requests[cite: 10].

---

## 4. Sharing of Information

We do not sell, rent, or trade your personal data to third parties. We share data only in the following limited scenarios:

### A. Between Riders and Drivers
- **When a Ride is Requested:** Drivers see the rider's first name, pickup location, destination, and proposed fare[cite: 10].
- **When a Ride is Accepted:** Riders see the driver's name, vehicle details (make, model, color, plate), contact phone number, rating, and live moving vehicle location[cite: 10].

### B. Third-Party Service Providers
We partner with trusted infrastructure providers governed by confidentiality and data processing agreements:
- **Google Cloud Platform & Firebase:** Secure cloud infrastructure providing Firebase Authentication, Cloud Firestore, Cloud Functions, and Firebase App Check[cite: 10].
- **Google Maps Platform:** Geospatial mapping, autocomplete, and routing services[cite: 10].
- **Crashlytics / Firebase Analytics:** Anonymous application crash telemetry.

### C. Legal Requirements
We may disclose information if required to do so by applicable law, regulation, legal process, or governmental request, or to protect the safety, rights, and property of our users, drivers, or the public.

---

## 5. Data Retention and Security

- **Security:** All network communications use industry-standard Transport Layer Security (TLS 1.3 / HTTPS). Database records are protected by strict, server-enforced Cloud Firestore Security Rules[cite: 10].
- **Retention:** We retain personal data for as long as your account remains active or as needed to provide our services, maintain dispute records, and comply with applicable statutory requirements.

---

## 6. Your Rights and Choices

- **Access & Update:** You can view and edit your profile name, role, and vehicle details anytime inside the app settings.
- **Location Controls:** You may revoke location access via your Android or iOS device settings at any time.
- **Push Notifications:** You can opt-out of push notifications through your device settings.

### Account & Data Deletion
Users have the right to request the complete deletion of their account and all associated personal data at any time.

* **In-App Deletion:** Navigate to **Settings > Account > Delete Account** and confirm your request.
* **Web & Email Deletion Request:** If you are unable to access the app or prefer to request deletion via the web, you can submit a deletion request by emailing **privacy@dartnexuslab.com** with your registered phone number and the subject line *"Account Deletion Request"*.
* **Data Permanently Deleted:** Upon verification of your identity, your user profile information, authentication credentials, phone number mapping, vehicle verification records, and trip history will be permanently deleted from our active Firebase databases within 30 days.
* **Data Retained:** Transaction logs or records required to comply with statutory tax, fraud-prevention, regulatory requirements, or unresolved dispute records will be retained for the minimum period legally required by applicable law, after which they are irreversibly destroyed.

---

## 7. Children's Privacy

SwiftRide is not directed to children under the age of 13 (or under 18 for driver accounts)[cite: 10]. We do not knowingly collect personal identifiable information from children under 13[cite: 10]. If you become aware that a child has provided us with personal information, please contact us immediately, and we will take prompt steps to remove such data[cite: 10].

---

## 8. Changes to This Privacy Policy

We may update this Privacy Policy from time to time. Any revisions will be reflected with an updated "Last Updated" date at the top of this document. Continued use of the SwiftRide application following notice of changes constitutes acceptance of the revised policy.

---

## 9. Contact Us

If you have any questions, concerns, or requests regarding this Privacy Policy or your personal data, please contact:

**DartNexusLab**  
*Email:* privacy@dartnexuslab.com  
*Support Desk:* support@dartnexuslab.com  
*Registered Office:* Jhang, Punjab, Pakistan[cite: 10]  
*Website:* https://swiftride.dartnexuslab.com
