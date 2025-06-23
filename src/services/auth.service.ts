
import { signInWithEmailAndPassword } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';

/**
 * Signs the user in with email and password, then syncs the session with Supabase.
 * This is called from the CLIENT.
 */
export async function signInWithEmail(email: string, password: string) {
  const supabase = createBrowserSupabaseClient();
  
  try {
    const result = await signInWithEmailAndPassword(auth, email, password);
    const user = result.user;
    if (!user) throw new Error('No user returned from sign-in');
    
    const idToken = await user.getIdToken();

    // This is the correct method for signing into Supabase with a Firebase ID token.
    const { error: supabaseSignInError } = await supabase.auth.signInWithJwt(idToken);

    if (supabaseSignInError) {
      throw new Error(`Supabase sign-in failed: ${supabaseSignInError.message}`);
    }
  } catch (error: any)
    console.error('Error during email sign-in:', error);
    // Attempt to sign out of Supabase just in case, but don't let it block the error flow
    await supabase.auth.signOut().catch(() => {});
    if (error.code === 'auth/invalid-credential' || error.code === 'auth/user-not-found' || error.code === 'auth/wrong-password') {
        throw new Error('Invalid email or password. Please try again.');
    }
    throw new Error(error.message || 'An unexpected error occurred during sign-in.');
  }
}


/**
 * Signs the user out from both Firebase and Supabase.
 */
export async function signOut() {
  const supabase = createBrowserSupabaseClient();
  try {
    await auth.signOut();
    await supabase.auth.signOut();
  } catch (error) {
    console.error('Error signing out:', error);
    // If main signout fails, still try to sign out from Supabase as a fallback
    await supabase.auth.signOut().catch(e => console.error("Supabase sign out failed too", e));
    throw error;
  }
}
