
import admin from 'firebase-admin';

const serviceAccountString = process.env.FIREBASE_SERVICE_ACCOUNT;

if (!serviceAccountString) {
  throw new Error('The FIREBASE_SERVICE_ACCOUNT environment variable is not set. Please add it to your .env file or project settings.');
}

// Check for common placeholder values to provide a better error message.
if (!serviceAccountString.trim().startsWith('{')) {
    throw new Error('The FIREBASE_SERVICE_ACCOUNT environment variable does not appear to be a valid JSON object. Please ensure you have copied the entire service account key file content.');
}

try {
  const serviceAccount = JSON.parse(serviceAccountString);

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }
} catch (error: any) {
    console.error("Error parsing FIREBASE_SERVICE_ACCOUNT JSON:", error.message);
    throw new Error(`Failed to parse FIREBASE_SERVICE_ACCOUNT. Please ensure it is a valid, un-escaped JSON object. Original error: ${error.message}`);
}


export const adminAuth = admin.auth();
