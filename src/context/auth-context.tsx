
'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import type { User, SupabaseClient } from '@supabase/supabase-js';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';
import { useRouter } from 'next/navigation';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  isConfigured: boolean;
  signInWithEmail: (email: string, password: string) => Promise<void>;
  signUpWithEmail: (email: string, password: string, companyName: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [supabase] = useState<SupabaseClient | null>(() => createBrowserSupabaseClient());
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();
  
  const isConfigured = !!supabase;

  useEffect(() => {
    if (!supabase) {
      setLoading(false);
      return;
    }

    // Get initial session
    const initAuth = async () => {
      try {
        const { data: { session } } = await supabase.auth.getSession();
        setUser(session?.user ?? null);
      } catch (error) {
        console.error('Error getting session:', error);
      } finally {
        setLoading(false);
      }
    };

    initAuth();

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      async (_event, session) => {
        setUser(session?.user ?? null);
      }
    );

    return () => {
      subscription?.unsubscribe();
    };
  }, [supabase]);

  const throwUnconfiguredError = () => {
    throw new Error('Supabase is not configured. Please check your environment variables.');
  }

  const signInWithEmail = async (email: string, password: string) => {
    if (!supabase) return throwUnconfiguredError();
    
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    
    if (error) throw error;
    if (!data.session) throw new Error('Authentication successful, but no session was returned. Please try again.');
    
    // Navigate to dashboard after successful login
    router.push('/dashboard');
  };

  const signUpWithEmail = async (email: string, password: string, companyName: string) => {
    if (!supabase) return throwUnconfiguredError();
    
    // The user record creation and company creation logic is now expected to be handled
    // by a database trigger or RPC function, as was the case in a previous version.
    // The client-side multi-step process is brittle and exposes too much logic.
    // We revert to calling the `handle_new_user` RPC function for robustness.
    const { data, error } = await supabase.auth.signUp({ email, password });

    if (error) throw error;

    if (data.user) {
      // This RPC function should create the company and user records transactionally.
      const { error: rpcError } = await supabase.rpc('handle_new_user', { company_name_param: companyName });
      if (rpcError) {
        // Log the error, but don't block the user from seeing the success message.
        // The user has been created in auth, but their company link failed.
        // This is a situation that may need manual intervention or a more robust cleanup process.
        console.error('Error in handle_new_user RPC:', rpcError);
      }
    }
  };

  const signOut = async () => {
    if (!supabase) return throwUnconfiguredError();
    
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
    
    // Navigate to login after signout
    router.push('/login');
  };

  const value = {
    user,
    loading,
    isConfigured,
    signInWithEmail,
    signUpWithEmail,
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
