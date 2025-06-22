
import { getApp, getApps, initializeApp, type FirebaseApp } from 'firebase/app';
import {
  createUserWithEmailAndPassword,
  getAuth,
  type Auth,
} from 'firebase/auth';
import { createCompanyAndUserInDB } from '@/services/database';

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

const CLIENT_APP_NAME = 'firebase-client-app-for-arvo';

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


// Function to create a user and associate them with a company in PostgreSQL
export const createUserWithCompany = async (
  email: string,
  password: string,
  companyName: string
) => {
    if (!auth) {
        throw new Error("Firebase Auth is not configured correctly. Please check your environment variables.");
    }
    
    // 1. Create user in Firebase Auth
    const userCredential = await createUserWithEmailAndPassword(
      auth,
      email,
      password
    );
    const user = userCredential.user;

    // 2. Create company and user records in your PostgreSQL database
    const companyId = await createCompanyAndUserInDB(
        user.uid,
        email,
        companyName
    );

    // The user is now created in both systems. They can now log in and
    // their companyId will be retrieved from the DB on server actions.
    return { user, companyId };
};

export { auth };

    