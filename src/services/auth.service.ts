import { signInWithPopup } from 'firebase/auth';
import { auth, googleProvider } from '@/lib/firebase';
import { supabase } from '@/lib/supabase';

/**
 * Signs the user in with Google, then syncs the session with Supabase.
 * If it's the user's first time, it triggers a Supabase function to set up their initial data.
 */
export async function signInWithGoogle() {
  try {
    // 1. Sign in with Firebase
    const result = await signInWithPopup(auth, googleProvider);
    const user = result.user;
    if (!user) throw new Error('No user returned from Google sign-in');
    
    const idToken = await user.getIdToken();

    // 2. Sign into Supabase with the Firebase token
    const { error: supabaseError } = await supabase.auth.signInWithIdToken({
      provider: 'google',
      token: idToken,
    });

    if (supabaseError) {
      console.error('Supabase sign-in error:', supabaseError);
      throw new Error(`Supabase sign-in failed: ${supabaseError.message}`);
    }

    // 3. Check if it's a new user by checking their sign-in times in Supabase
    // This part assumes that `handle_new_user` is a DB function that needs to be called.
    // A more modern approach is to use a DB trigger on the `auth.users` table, which would make this check unnecessary.
    // Sticking to the prompt's specified flow for now.
    const { data: { user: supabaseUser } } = await supabase.auth.getUser();

    if (supabaseUser) {
        const createdAt = new Date(supabaseUser.created_at).getTime();
        // last_sign_in_at can be null on first sign up
        const lastSignInAt = supabaseUser.last_sign_in_at ? new Date(supabaseUser.last_sign_in_at).getTime() : createdAt;

        // If the account was created within the last minute and sign-in times match, it's likely a new user.
        if (Date.now() - createdAt < 60000 && createdAt === lastSignInAt) {
            console.log('New user detected, calling handle_new_user...');
            const { error: rpcError } = await supabase.rpc('handle_new_user', {
                company_name: 'My New Company' // Or prompt user for this during signup
            });

            if (rpcError) {
                console.error('Error calling handle_new_user:', rpcError);
                // Not throwing here to allow login to proceed, but logging the error.
            }
        }
    }

  } catch (error: any) {
    console.error('Error during Google sign-in:', error);
    // Clean up Supabase session if Firebase login fails partway
    await supabase.auth.signOut();
    throw error;
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
    // Even if one fails, try the other, then re-throw
    await supabase.auth.signOut().catch(e => console.error("Supabase sign out failed too", e));
    throw error;
  }
}
