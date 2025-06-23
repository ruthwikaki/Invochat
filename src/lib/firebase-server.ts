
import admin from 'firebase-admin';

if (!admin.apps.length) {
  const serviceAccountString = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (serviceAccountString) {
    try {
      const serviceAccount = JSON.parse(serviceAccountString);
      admin.initializeApp({
        credential: admin.credential.cert(serviceAccount),
      });
      console.log('[Firebase Admin] SDK initialized successfully from service account variable.');
    } catch (e) {
      console.error('[Firebase Admin] Failed to parse FIREBASE_SERVICE_ACCOUNT JSON.', e);
    }
  } else {
    console.warn('[Firebase Admin] FIREBASE_SERVICE_ACCOUNT environment variable is not set. Server-side auth will not work.');
  }
}

export const auth = admin.auth();
