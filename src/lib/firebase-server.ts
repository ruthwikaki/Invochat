import { initializeApp, getApps, getApp, cert } from 'firebase-admin/app';
import { getAuth } from 'firebase-admin/auth';
import { getFirestore } from 'firebase-admin/firestore';

const serviceAccount = process.env.FIREBASE_SERVICE_ACCOUNT
  ? JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT)
  : undefined;

const app =
  getApps().length > 0
    ? getApp()
    : initializeApp(
        serviceAccount ? { credential: cert(serviceAccount) } : undefined
      );

const auth = getAuth(app);
const db = getFirestore(app);

export { auth, db };
