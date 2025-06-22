
import { initializeApp, getApps, getApp, cert, App } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const ADMIN_APP_NAME = 'firebase-admin-app-for-arvo';

function initializeAdminApp(): App | null {
    // Check if the admin app is already initialized to prevent re-initialization.
    if (getApps().some(app => app.name === ADMIN_APP_NAME)) {
        return getApp(ADMIN_APP_NAME);
    }

    try {
        const serviceAccountStr = process.env.FIREBASE_SERVICE_ACCOUNT;
        
        if (!serviceAccountStr) {
            console.warn(
                `[Firebase Admin]: FIREBASE_SERVICE_ACCOUNT is not set. 
                For local development, provide the service account JSON in your .env file. 
                In a hosted environment, ensure Application Default Credentials are available. 
                Server-side AI actions will be disabled.`
            );
            return null;
        }

        const serviceAccount = JSON.parse(serviceAccountStr);

        return initializeApp({
            credential: cert(serviceAccount)
        }, ADMIN_APP_NAME);

    } catch (error: any) {
        let errorMessage = `[Firebase Admin]: Initialization failed. `;
        if (error instanceof SyntaxError) {
             errorMessage += 'Failed to parse FIREBASE_SERVICE_ACCOUNT. Make sure it is valid, single-line JSON in your .env file.';
        } else {
            errorMessage += error.message;
        }
        console.error(errorMessage);
        return null;
    }
}

const adminApp = initializeAdminApp();
const auth = adminApp ? getAuth(adminApp) : undefined;
const db = adminApp ? getFirestore(adminApp) : undefined;

export { auth, db };
