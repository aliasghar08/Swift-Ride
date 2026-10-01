import * as admin from 'firebase-admin';
import Stripe from 'stripe';

if (!process.env.FIREBASE_CONFIG && !process.env.FIREBASE_DATABASE_URL) {
  process.env.FIREBASE_DATABASE_URL = 'https://swiftride-default-rtdb.firebaseio.com';
}

if (!admin.apps.length) {
  admin.initializeApp({
    projectId: process.env.GCLOUD_PROJECT || 'swiftride-production',
    databaseURL: process.env.FIREBASE_DATABASE_URL || 'https://swiftride-default-rtdb.firebaseio.com',
  });
}

export const db = admin.firestore();
export const rtdb = admin.database();
export const auth = admin.auth();
export const storage = admin.storage();
export const messaging = admin.messaging();

const stripeSecretKey = process.env.STRIPE_SECRET_KEY || 'sk_test_placeholder_swiftride_development';
export const stripe = new Stripe(stripeSecretKey, {
  apiVersion: '2024-06-20' as Stripe.LatestApiVersion,
});
