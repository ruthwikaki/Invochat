import { getApp, getApps, initializeApp } from 'firebase/app';
import {
  createUserWithEmailAndPassword,
  getAuth,
} from 'firebase/auth';
import {
  addDoc,
  collection,
  getFirestore,
  serverTimestamp,
} from 'firebase/firestore';
import { getFunctions, httpsCallable } from 'firebase/functions';

const firebaseConfig = {
  apiKey: process.env.NEXT_PUBLIC_FIREBASE_API_KEY,
  authDomain: process.env.NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN,
  projectId: process.env.NEXT_PUBLIC_FIREBASE_PROJECT_ID,
  storageBucket: process.env.NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: process.env.NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID,
  appId: process.env.NEXT_PUBLIC_FIREBASE_APP_ID,
};

// Initialize Firebase for client-side
const app = !getApps().length ? initializeApp(firebaseConfig) : getApp();
const auth = getAuth(app);
const db = getFirestore(app);
const functions = getFunctions(app);

// Function to create a user and associate them with a company
export const createUserWithCompany = async (
  email,
  password,
  companyName
) => {
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
