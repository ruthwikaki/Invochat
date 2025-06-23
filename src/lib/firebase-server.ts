
import admin from 'firebase-admin';

// This ensures the SDK is initialized only once.
if (!admin.apps.length) {
  const serviceAccountString = process.env.FIREBASE_SERVICE_ACCOUNT;
  
  if (!serviceAccountString) {
    throw new Error('The FIREBASE_SERVICE_ACCOUNT environment variable is not set. Server-side authentication cannot function.');
  }

  try {
    const serviceAccount = JSON.parse(serviceAccountString);
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
    console.log('[Firebase Admin] SDK initialized successfully.');
  } catch (e: any) {
    console.error('[Firebase Admin] Failed to parse FIREBASE_SERVICE_ACCOUNT JSON. Error:', e.message);
    throw new Error('Firebase Admin SDK initialization failed.');
  }
}

export const auth = admin.auth();
