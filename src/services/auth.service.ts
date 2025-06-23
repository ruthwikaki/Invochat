
import { signInWithEmailAndPassword, createUserWithEmailAndPassword } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';

/**
 * Signs the user in with email and password, then syncs the session with Supabase.
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
    await supabase.auth.signOut();
    if (error.code === 'auth/invalid-credential' || error.code === 'auth/user-not-found' || error.code === 'auth/wrong-password') {
        throw new Error('Invalid email or password. Please try again.');
    }
    throw new Error('An unexpected error occurred during sign-in.');
  }
}

/**
 * Signs the user up with email and password, then syncs the session with Supabase
 * and calls the function to set up their initial data.
 */
export async function signUpWithEmail(email: string, password: string, companyName: string) {
  try {
    // 1. Create user in Firebase Auth
    const result = await createUserWithEmailAndPassword(auth, email, password);
    const user = result.user;
    if (!user) throw new Error('No user returned from sign-up');
    
    const idToken = await user.getIdToken();

    // 2. Sign into Supabase with the Firebase token
    const { error: supabaseError } = await supabase.auth.signInWithIdToken({
      provider: 'email',
      token: idToken,
    });
    if (supabaseError) throw new Error(`Supabase sign-in failed: ${supabaseError.message}`);

    // 3. Call the RPC to create the company and user profile, which also sets claims
    const { error: rpcError } = await supabase.rpc('handle_new_user', {
        company_name: companyName
    });

    if (rpcError) {
        // If this fails, we need to clean up the created Firebase user
        await user.delete();
        throw new Error(`Failed to set up company: ${rpcError.message}`);
    }

  } catch (error: any) {
    console.error('Error during email sign-up:', error);
    // Clean up Supabase session if it exists
    await supabase.auth.signOut().catch(() => {});
    if (error.code === 'auth/email-already-in-use') {
        throw new Error('This email address is already in use.');
    }
    throw new Error('An unexpected error occurred during sign-up.');
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
