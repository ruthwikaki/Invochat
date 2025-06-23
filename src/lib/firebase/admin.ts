
import admin from 'firebase-admin';

// Reconstruct the service account object from individual environment variables
const serviceAccount = {
  type: process.env.FIREBASE_TYPE,
  project_id: process.env.FIREBASE_PROJECT_ID,
  private_key_id: process.env.FIREBASE_PRIVATE_KEY_ID,
  // When passing the private key from an env var, we need to replace the `\n` literal characters with actual newlines.
  private_key: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
  client_email: process.env.FIREBASE_CLIENT_EMAIL,
  client_id: process.env.FIREBASE_CLIENT_ID,
  auth_uri: process.env.FIREBASE_AUTH_URI,
  token_uri: process.env.FIREBASE_TOKEN_URI,
  auth_provider_x509_cert_url: process.env.FIREBASE_AUTH_PROVIDER_X509_CERT_URL,
  client_x509_cert_url: process.env.FIREBASE_CLIENT_X509_CERT_URL,
  universe_domain: process.env.FIREBASE_UNIVERSE_DOMAIN,
};

// Check that the required environment variables are set.
if (
  !serviceAccount.project_id ||
  !serviceAccount.private_key ||
  !serviceAccount.client_email
) {
  throw new Error(
    'Firebase Admin SDK environment variables are not fully set. Please check your .env file.'
  );
}


try {
  if (!admin.apps.length) {
    admin.initializeApp({
      // Cast to `admin.ServiceAccount` to satisfy TypeScript
      credential: admin.credential.cert(serviceAccount as admin.ServiceAccount),
    });
  }
} catch (error: any) {
    console.error("Firebase Admin SDK Initialization Error:", error.stack);
    throw new Error(`Failed to initialize Firebase Admin SDK. Please check the environment variables. Error: ${error.message}`);
}


export const adminAuth = admin.auth();
