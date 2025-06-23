import admin from 'firebase-admin';

// This is a workaround for Vercel/Next.js to parse the private key correctly
const privateKey = process.env.FIREBASE_ADMIN_PRIVATE_KEY?.replace(/\\n/g, '\n');

if (!admin.apps.length) {
  if (!process.env.FIREBASE_ADMIN_PROJECT_ID || !process.env.FIREBASE_ADMIN_CLIENT_EMAIL || !privateKey) {
    console.warn('[Firebase Admin] Missing environment variables for Firebase Admin SDK. Server-side auth will not work.');
  } else {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: process.env.FIREBASE_ADMIN_PROJECT_ID,
        clientEmail: process.env.FIREBASE_ADMIN_CLIENT_EMAIL,
        privateKey: privateKey,
      }),
    });
    console.log('[Firebase Admin] SDK initialized successfully.');
  }
}

export const auth = admin.auth();
