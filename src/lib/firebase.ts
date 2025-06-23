import { initializeApp, getApps, getApp, type FirebaseApp } from 'firebase/app';
import { getAuth, GoogleAuthProvider, type Auth } from 'firebase/auth';

// Your web app's Firebase configuration
const firebaseConfig = {
  apiKey: "AIzaSyDS_DRwrguUfKnMc1aEdZnLRWJ00AUfYUE",
  authDomain: "arvo-r5x6y.firebaseapp.com",
  projectId: "arvo-r5x6y",
  storageBucket: "arvo-r5x6y.firebasestorage.app",
  messagingSenderId: "1032179450962",
  appId: "1:1032179450962:web:c9bbcf7bfeda1a538acb8b"
};

// Initialize Firebase
const app: FirebaseApp = !getApps().length ? initializeApp(firebaseConfig) : getApp();
const auth: Auth = getAuth(app);
const googleProvider = new GoogleAuthProvider();

export { app, auth, googleProvider };
