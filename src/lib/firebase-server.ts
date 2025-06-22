
import { initializeApp, getApps, getApp, cert, App } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

function initializeAdminApp(): App | null {
    if (getApps().length > 0) {
        return getApp();
    }
    
    try {
        const serviceAccountStr = process.env.FIREBASE_SERVICE_ACCOUNT;
        if (serviceAccountStr) {
            const serviceAccount = JSON.parse(serviceAccountStr);
            return initializeApp({ credential: cert(serviceAccount) });
        } else {
            // This will use Application Default Credentials if available.
            return initializeApp();
        }
    } catch (error: any) {
        let errorMessage = "Firebase Admin SDK initialization failed. ";
        if (error.code === 'app/duplicate-app') {
            return getApp(); // This is not a failure, just a re-init attempt.
        } else if (error instanceof SyntaxError) {
             errorMessage += 'Failed to parse FIREBASE_SERVICE_ACCOUNT. Make sure it is a valid, non-empty JSON string.';
        } else if (process.env.FIREBASE_SERVICE_ACCOUNT) {
             errorMessage += 'The provided FIREBASE_SERVICE_ACCOUNT seems invalid.';
        } else {
            errorMessage += 'Could not find necessary credentials. For server-side features, set the FIREBASE_SERVICE_ACCOUNT or GOOGLE_APPLICATION_CREDENTIALS environment variables.';
        }
        console.error(errorMessage);
        
        // Return null to prevent the entire server from crashing.
        return null;
    }
}

const app = initializeAdminApp();
const auth = app ? getAuth(app) : undefined;
const db = app ? getFirestore(app) : undefined;

export { auth, db };
