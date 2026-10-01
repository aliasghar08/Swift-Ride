# SwiftRide Gemini AI & Firebase AI Logic Setup Guide

This document provides complete instructions for provisioning, configuring, securing, and operating the **Gemini AI** layer across the SwiftRide platform using **Firebase AI Logic** with the **Gemini Developer API** provider and **Firebase App Check** enforcement.

---

## 1. Provider & Architecture Summary

| Component | Setting / Provider | Justification |
|---|---|---|
| **AI Provider** | **Gemini Developer API** (`FirebaseAI.googleAI()`) | Spark plan compatible, free tier eligible without billing account |
| **Model** | `gemini-3.8-flash` | Ultra-low latency, structured outputs, $0.75 / 1M in, $3.75 / 1M out |
| **Client Authentication** | **Firebase App Check** | Protects Gemini endpoints from token theft; no API keys on mobile clients |
| **Server Backend** | Firebase Cloud Functions Gen 2 (`@google/generative-ai`) | Secret Manager for API keys, Pino structured logging |
| **Cost Control** | Strict token budgets (`256` chat, `512` insights) | Low thinking level, 24h Firestore caching |

---

## 2. Enabling Firebase AI Logic in Firebase Console

1. Navigate to the [Firebase Console](https://console.firebase.google.com/) and select your project (`swiftride-production`).
2. In the left navigation menu, expand **Build** and select **Firebase AI Logic** (or **AI Logic** under Extensions / Build).
3. Click **Get Started** / **Enable**.
4. When prompted to select your provider:
   - Select **Gemini Developer API** (Google AI Studio provider).
   - **DO NOT** select Vertex AI Gemini API (which requires Blaze billing and does not offer the Spark free tier).
5. Accept the default terms and click **Save**.

---

## 3. Configuring Firebase App Check (Mandatory)

Firebase AI Logic requires **Firebase App Check** enforcement. Client apps make direct Gemini calls without storing any client API keys; authentication and abuse prevention are guaranteed by device attestation.

### Android: Google Play Integrity
1. In the Firebase Console, go to **App Check** > **Apps** tab.
2. Select your Android app (`com.swiftride.swiftride`).
3. Under **Play Integrity**:
   - Link your Google Play Developer Account or upload your SHA-256 app signing certificate fingerprint.
   - Set Token TTL to **1 hour**.
4. In `android/app/build.gradle.kts`:
   ```kotlin
   dependencies {
       implementation("com.google.firebase:firebase-appcheck-playintegrity:18.0.0")
   }
   ```
5. For local Android emulator testing, generate a debug token in your `Logcat` and register it under **App Check** > **Manage debug tokens**.

### iOS: DeviceCheck & App Attest
1. In the Firebase Console, select your iOS app (`com.swiftride.swiftride`).
2. Under **DeviceCheck**:
   - Upload your Apple Developer Key ID (`.p8` private key file) and Team ID from developer.apple.com.
3. Under **App Attest**:
   - Register your App Bundle ID.
4. In `ios/Runner/AppDelegate.swift`:
   ```swift
   import FirebaseCore
   import FirebaseAppCheck

   // Configured automatically with AppleDeviceCheckProvider
   ```

### Debug Tokens for Development
To test App Check on physical test devices or CI without production attestation:
1. In `lib/main.dart`, activate debug provider in debug mode:
   ```dart
   if (kDebugMode) {
     await FirebaseAppCheck.instance.activate(
       providerAndroid: const AndroidDebugProvider(),
       providerApple: const AppleDebugProvider(),
     );
   } else {
     await FirebaseAppCheck.instance.activate(
       providerAndroid: const AndroidPlayIntegrityProvider(),
       providerApple: const AppleDeviceCheckProvider(),
     );
   }
   ```
2. Copy the printed UUID token from your console and paste it into **Firebase Console > App Check > Apps > Manage debug tokens**.

---

## 4. Rate Limiting Strategy per User

Configure AI Logic quota rules to prevent individual users from draining quotas:

| Feature | Limit per User | Implementation |
|---|---|---|
| **In-App Assistant Chat** | 20 messages / hour | Enforced by client counter & Cloud Function rate limiter |
| **Earnings Advisor** | 10 calls / day | Enforced by 24-hour Firestore cache & rate limiter |
| **Safety Check-in** | Unlimited | Safety critical, triggered only on RideCheck flags |
| **Maintenance Predictor** | 1 run / week | Scheduled via Cloud Scheduler every Monday 8:00 AM |

### Cloud Function App Check Enforcement
All AI Cloud Functions enforce App Check validation before execution:
```typescript
export const generateEarningsInsight = onCall(
  {
    region: 'us-central1',
    enforceAppCheck: true,
    memory: '512MiB',
    timeoutSeconds: 60,
  },
  async (request) => { ... }
);
```

---

## 5. Google Cloud Budget Alerts & Caps

To guarantee expenses never exceed budget thresholds:

1. Open [Google Cloud Console Billing](https://console.cloud.google.com/billing).
2. Select your Billing Account and click **Budgets & alerts**.
3. Click **Create Budget**:
   - **Name:** `SwiftRide-AI-Monthly-Cap`
   - **Projects:** `swiftride-production`
   - **Services:** Select *Generative Language API* and *Cloud Functions*.
   - **Amount:** Set Target Budget to **$50.00 / month**.
4. Set Alert Thresholds:
   - **50% ($25.00)**: Email project owners and dev team.
   - **80% ($40.00)**: Trigger Pub/Sub topic `budget-warning`.
   - **100% ($50.00)**: Cloud Function automatically disables `ai_features_enabled` via Firebase Remote Config.

---

## 6. Remote Config Feature Toggles

Control AI behavior dynamically without redeploying mobile apps:

| Parameter Key | Type | Default Value | Description |
|---|---|---|---|
| `ai_features_enabled` | Boolean | `true` | Master kill switch for all AI assistant features |
| `voice_assistant_enabled` | Boolean | `true` | Enables speech-to-text voice assistant button |
| `safety_ai_enabled` | Boolean | `true` | Enables RideCheck automated safety messages |
| `earnings_advisor_enabled` | Boolean | `true` | Enables driver daily earnings recommendations |
| `ai_max_tokens_chat` | Number | `256` | Maximum response length for in-app assistant |

---

## 7. Monthly Cost Estimates & Scaling Forecast

Pricing based on `gemini-3.8-flash`:
- Input: **$0.75 per 1,000,000 tokens**
- Output: **$3.75 per 1,000,000 tokens**

| Rides / Month | Est. AI Calls / Month | Est. Monthly Cost | Notes |
|---|---|---|---|
| **1,000** | ~5,000 calls | **$0.00** | Covered entirely within free tier (Spark plan) |
| **10,000** | ~50,000 calls | **$5.00 – $15.00** | Ultra-efficient token usage via 24h Firestore caching |
| **100,000** | ~500,000 calls | **$50.00 – $150.00** | Set Google Cloud budget cap at $200.00 |

### Key Optimization Rules
1. **Chat Prompts:** Short system prompt (under 80 words) and `maxOutputTokens: 256`.
2. **Thinking Budget:** Low thinking level (`ThinkingLevel.low` / `thinkingBudget: 0`) eliminates unnecessary reasoning overhead tokens.
3. **24-Hour Caching:** Daily earnings forecasts and vehicle maintenance alerts are cached in Firestore collection `ai_insights`, preventing redundant model calls on app reload.
