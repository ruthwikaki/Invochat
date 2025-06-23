
'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import type { User } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { signInWithEmailAndPassword, signOut as firebaseSignOut } from 'firebase/auth';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  signInWithEmail: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged(async (firebaseUser) => {
      if (firebaseUser) {
        // Refresh token to get latest custom claims
        await firebaseUser.getIdToken(true);
      }
      setUser(firebaseUser);
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  const signInWithEmail = async (email: string, password: string) => {
    const supabase = createBrowserSupabaseClient();
    try {
      const result = await signInWithEmailAndPassword(auth, email, password);
      const user = result.user;
      if (!user) throw new Error('No user returned from sign-in');
      
      const idToken = await user.getIdToken();
  
      const { error: supabaseSignInError } = await supabase.auth.signInWithJwt(idToken);
  
      if (supabaseSignInError) {
        throw new Error(`Supabase sign-in failed: ${supabaseSignInError.message}`);
      }
      // onAuthStateChanged will handle the user state update
    } catch (error: any) {
      console.error('Error during email sign-in:', error);
      // Attempt to sign out of Supabase just in case, but don't let it block the error flow
      await supabase.auth.signOut().catch(() => {});
      if (error.code === 'auth/invalid-credential' || error.code === 'auth/user-not-found' || error.code === 'auth/wrong-password') {
          throw new Error('Invalid email or password. Please try again.');
      }
      throw new Error(error.message || 'An unexpected error occurred during sign-in.');
    }
  };
  
  const signOut = async () => {
    const supabase = createBrowserSupabaseClient();
    try {
      await firebaseSignOut(auth);
      await supabase.auth.signOut();
      setUser(null);
    } catch (error) {
      console.error('Error signing out:', error);
      // If main signout fails, still try to sign out from Supabase as a fallback
      await supabase.auth.signOut().catch(e => console.error("Supabase sign out failed too", e));
      throw error;
    }
  };

  const value = {
    user,
    loading,
    signInWithEmail,
    signOut,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
