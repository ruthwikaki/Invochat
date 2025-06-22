
import { initializeApp, getApps, getApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

function initializeAdminApp() {
    if (getApps().length > 0) {
        return getApp();
    }
    
    let serviceAccount;
    try {
        if (process.env.FIREBASE_SERVICE_ACCOUNT) {
            serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
        }
    } catch (error) {
        console.error('Failed to parse FIREBASE_SERVICE_ACCOUNT. Make sure it is a valid JSON string.', error);
        serviceAccount = undefined;
    }

    try {
        return initializeApp(
            serviceAccount ? { credential: cert(serviceAccount) } : undefined
        );
    } catch (error) {
        console.error("Firebase Admin SDK initialization failed:", error);
        // This will prevent the app from crashing and auth/db will be undefined.
        return null;
    }
}

const app = initializeAdminApp();
const auth = app ? getAuth(app) : undefined;
const db = app ? getFirestore(app) : undefined;

export { auth, db };
