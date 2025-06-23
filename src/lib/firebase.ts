
import { initializeApp, getApps, getApp, type FirebaseApp } from 'firebase/app';
import { getAuth, type Auth } from 'firebase/auth';

// Hardcoded configuration to resolve API key issues.
// This ensures the correct credentials are used, bypassing environment variable problems.
const firebaseConfig = {
  apiKey: "AIzaSyDS_DRwrguUfKnMc1aEdZnLRWJ00AUfYUE",
  authDomain: "arvo-r5x6y.firebaseapp.com",
  projectId: "arvo-r5x6y",
  storageBucket: "arvo-r5x6y.appspot.com",
  messagingSenderId: "1032179450962",
  appId: "1:1032179450962:web:c9bbcf7bfeda1a538acb8b"
};

const app: FirebaseApp = getApps().length ? getApp() : initializeApp(firebaseConfig);
const auth: Auth = getAuth(app);

export const isFirebaseEnabled = true;

export { app, auth };
