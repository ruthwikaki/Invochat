
import { getApp, getApps, initializeApp, type FirebaseApp } from 'firebase/app';
import {
  getAuth,
  type Auth,
} from 'firebase/auth';

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

const CLIENT_APP_NAME = 'firebase-client-app-for-arvo-named';

// Safely initialize the app, checking for required config values.
let app: FirebaseApp | null = null;
let auth: Auth | null = null;

if (firebaseConfig.projectId && firebaseConfig.apiKey) {
    if (!getApps().some(app => app.name === CLIENT_APP_NAME)) {
        try {
            app = initializeApp(firebaseConfig, CLIENT_APP_NAME);
        } catch (e) {
            console.error("Failed to initialize Firebase", e)
        }
    } else {
        app = getApp(CLIENT_APP_NAME);
    }
    
    if (app) {
        auth = getAuth(app);
    }
} else {
    console.warn("Firebase projectId or apiKey is missing from environment variables. Firebase client services will not be initialized.");
}

export { auth };
