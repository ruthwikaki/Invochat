
import admin from 'firebase-admin';

if (!process.env.FIREBASE_SERVICE_ACCOUNT) {
  throw new Error('The FIREBASE_SERVICE_ACCOUNT environment variable is not set. Please add it to your .env file.');
}

try {
  const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }
} catch (error: any) {
    throw new Error(`Failed to parse FIREBASE_SERVICE_ACCOUNT: ${error.message}`);
}


export const adminAuth = admin.auth();
