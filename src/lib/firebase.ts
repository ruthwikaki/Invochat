
import { getApp, getApps, initializeApp, type FirebaseApp } from 'firebase/app';
import {
  createUserWithEmailAndPassword,
  getAuth,
  type Auth,
} from 'firebase/auth';
import {
  addDoc,
  collection,
  getFirestore,
  serverTimestamp,
  type Firestore,
} from 'firebase/firestore';
import { getFunctions, httpsCallable, type Functions } from 'firebase/functions';

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
let db: Firestore | null = null;
let functions: Functions | null = null;

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
        db = getFirestore(app);
        functions = getFunctions(app);
    }
} else {
    console.warn("Firebase projectId or apiKey is missing from environment variables. Firebase client services will not be initialized.");
}


// Function to create a user and associate them with a company
export const createUserWithCompany = async (
  email,
  password,
  companyName
) => {
    if (!auth || !db || !functions) {
        throw new Error("Firebase is not configured correctly. Please check your environment variables.");
    }
  // Create user in Firebase Auth
  const userCredential = await createUserWithEmailAndPassword(
    auth,
    email,
    password
  );
  const user = userCredential.user;

  // Create a company document in Firestore
  const companyRef = await addDoc(collection(db, 'companies'), {
    name: companyName,
    ownerId: user.uid,
    createdAt: serverTimestamp(),
  });

  // Call the Cloud Function to set custom claims.
  // IMPORTANT: You must deploy the 'setUserCompany' Cloud Function to your Firebase project.
  const setUserCompany = httpsCallable(functions, 'setUserCompany');
  await setUserCompany({
    userId: user.uid,
    companyId: companyRef.id,
  });

  // It can take a moment for the custom claim to propagate. The user might need to
  // refresh or re-login for the app to recognize the companyId immediately.

  return { user, companyId: companyRef.id };
};

export { auth, db, functions };
