
import { initializeApp, getApps, getApp, type FirebaseApp } from 'firebase/app';
import { getAuth, type Auth } from 'firebase/auth';

const firebaseConfig = {
  apiKey: "AIzaSyDS_DRwrguUfKnMc1aEdZnLRWJ00AUfYUE",
  authDomain: "arvo-r5x6y.firebaseapp.com",
  projectId: "arvo-r5x6y",
  storageBucket: "arvo-r5x6y.appspot.com",
  messagingSenderId: "1032179450962",
  appId: "1:1032179450962:web:c9bbcf7bfeda1a538acb8b"
};

let app: FirebaseApp | null = null;
let auth: Auth | null = null;

// Check if all necessary environment variables are set
export const isFirebaseEnabled = !!(
    firebaseConfig.apiKey &&
    firebaseConfig.authDomain &&
    firebaseConfig.projectId
);

if (isFirebaseEnabled) {
  // Diagnostic log to help debug API key issues.
  console.log(`[Firebase] Attempting to initialize with API Key ending in ...${firebaseConfig.apiKey?.slice(-4)}`);
  try {
    app = !getApps().length ? initializeApp(firebaseConfig) : getApp();
    auth = getAuth(app);
  } catch (e) {
    console.error("Failed to initialize Firebase", e)
  }
} else {
    console.warn('[Firebase] Client-side environment variables are not fully set. Firebase features will be disabled.');
}


export { app, auth };
