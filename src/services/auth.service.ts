
import { signInWithEmailAndPassword } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';

/**
 * Signs the user in with email and password, then syncs the session with Supabase.
 * This is called from the CLIENT.
 */
export async function signInWithEmail(email: string, password: string) {
  try {
    const result = await signInWithEmailAndPassword(auth, email, password);
    const user = result.user;
    if (!user) throw new Error('No user returned from sign-in');
    
    const idToken = await user.getIdToken();

    const { error: supabaseError } = await supabase.auth.signInWithIdToken({
      provider: 'email',
      token: idToken,
    });

    if (supabaseError) {
      throw new Error(`Supabase sign-in failed: ${supabaseError.message}`);
    }
  } catch (error: any) {
    console.error('Error during email sign-in:', error);
    await supabase.auth.signOut().catch(() => {});
    if (error.code === 'auth/invalid-credential' || error.code === 'auth/user-not-found' || error.code === 'auth/wrong-password') {
        throw new Error('Invalid email or password. Please try again.');
    }
    throw new Error('An unexpected error occurred during sign-in.');
  }
}


/**
 * Signs the user out from both Firebase and Supabase.
 */
export async function signOut() {
  try {
    await auth.signOut();
    await supabase.auth.signOut();
  } catch (error) {
    console.error('Error signing out:', error);
    await supabase.auth.signOut().catch(e => console.error("Supabase sign out failed too", e));
    throw error;
  }
}
