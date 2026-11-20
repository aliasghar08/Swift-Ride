# Account & Data Deletion Policy for SwiftRide

**Last Updated:** November 21, 2026  
**Effective Date:** October 17, 2026  
**Application Name:** SwiftRide (Swift Ride)  
**Package / Bundle ID:** `com.dartnexuslab.swiftride`  
**Developer / Publisher:** DartNexusLab  
**Contact Email:** [aliasgharinnocent@yahoo.com](mailto:aliasgharinnocent@yahoo.com)  
**Web Deletion Request URL:** `https://swift-ride-5ab75.firebaseapp.com/account-deletion.html`

---

## 1. Overview

At SwiftRide (operated by DartNexusLab), we respect your privacy and provide transparent, full control over your personal data. In accordance with Google Play Store and Apple App Store policies, users have the right to request the permanent deletion of their account and all associated personal data at any time.

This document describes:
- How you can initiate an account deletion request (both in-app and on the web).
- What categories of data are deleted.
- What data, if any, is retained and the legal or security justification for its retention.
- The timeline for complete data removal.

---

## 2. How to Delete Your Account

You can delete your account and personal data using either of the following two methods:

### Method A: In-App Instant Deletion (Recommended)

1. Open the **SwiftRide** application on your device.
2. Ensure you are signed in.
3. Tap your **Profile** icon in the top right corner of the home screen to open the Profile menu.
4. Scroll to the bottom of the Profile sheet and tap **Delete Account** (highlighted in red).
5. Read the confirmation warning dialog explaining that this action is irreversible.
6. Tap **Delete My Account Permanently**.
7. Your account credentials, profile, authentication records, and device tokens will be permanently erased immediately, and you will be signed out back to the welcome screen.

---

### Method B: Web or Email Deletion Request (If App is Uninstalled)

If you have uninstalled the application or cannot access your mobile device:

1. Send an email to our Data Protection team at: **[aliasgharinnocent@yahoo.com](mailto:aliasgharinnocent@yahoo.com)**
2. Subject line: **`Account Deletion Request - SwiftRide`**
3. Include the **registered phone number** associated with your SwiftRide account (including country code, e.g. `+92 300 1234567`).
4. To verify ownership and prevent unauthorized deletion of accounts, our team will send a verification SMS or email confirmation to your registered credentials.
5. Once ownership is confirmed, your account and associated personal data will be completely deleted from our production databases within **7 business days**.

You may also submit a deletion request via our online portal at:  
👉 **`https://swift-ride-5ab75.firebaseapp.com/account-deletion.html`**

---

## 3. Data That Is Permanently Deleted

Upon receiving and validating your account deletion request, the following information is permanently purged from Firebase Authentication, Cloud Firestore, Realtime Database, and Cloud Storage:

- **Authentication Record:** Your Firebase Auth user identity (UID), encrypted password tokens, and phone number credentials.
- **Personal Profile Data:** Full name, display name, email address, profile picture (stored in Cloud Storage), and user role (`Rider` or `Driver`).
- **Driver Verification Documents (Drivers only):** Vehicle make/model, license plate number, registration documents, CNIC / ID cards, and driving license images.
- **Location Data & GPS History:** Saved home/work favorite locations, cached trip coordinates, and historical driver telemetry points.
- **Communication & Push Tokens:** Firebase Cloud Messaging (FCM) device registration tokens, in-app notification preferences, and customer support chat transcripts.
- **Active Bids & Ride Drafts:** All open fare negotiations, pending ride offers, and live bids.

---

## 4. Data Retained and Retention Period

Certain non-identifiable or legally mandated records may be retained for a strictly limited period:

| Data Category | Reason for Retention | Retention Period |
| :--- | :--- | :--- |
| **Completed Financial & Transaction Logs** | Compliance with statutory financial reporting, audit regulations, and tax accounting in Pakistan. | Up to 90 days after account deletion, after which logs are anonymized or permanently purged. |
| **Fraud & Safety Investigation Records** | Prevention of platform abuse (e.g. users banned for harassment, severe safety infractions, or fraud trying to re-register under a fresh account). | Restricted hash stored in secure audit tables with zero public access. |

*Note: Retained records are stripped of direct personal contact identifiers and cannot be used for marketing, profiling, or re-engagement.*

---

## 5. Security & Confirmation

- All data deletion routines use cryptographically secure cascading delete operations across Google Cloud Platform (Firestore, Cloud Storage, Authentication, and Realtime Database).
- After deletion, you will receive an email confirmation (if an email address was linked to your profile) or SMS notification confirming successful data eradication.

---

## 6. Questions & Contact

For any inquiries or assistance regarding data privacy and account deletion, please contact:

**DartNexusLab Data Protection**  
Email: [aliasgharinnocent@yahoo.com](mailto:aliasgharinnocent@yahoo.com)  
Address: Jhang, Punjab, Pakistan  
Privacy Policy: [https://swift-ride-5ab75.firebaseapp.com/privacy-policy.html](https://swift-ride-5ab75.firebaseapp.com/privacy-policy.html)
