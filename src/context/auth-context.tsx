
'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import type { SupabaseClient, AuthError, Session, SignInWithPasswordCredentials } from '@supabase/supabase-js';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';
import type { User } from '@/types';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  isConfigured: boolean;
  signInWithEmail: (credentials: SignInWithPasswordCredentials) => Promise<{ error: AuthError | null }>;
  signUpWithEmail: (email: string, password: string, companyName: string) => Promise<{ data: { user: User | null; session: Session | null; }; error: AuthError | null; }>;
  signOut: () => Promise<{ error: AuthError | null }>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [supabase] = useState<SupabaseClient | null>(() => createBrowserSupabaseClient());
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  
  const isConfigured = !!supabase;

  useEffect(() => {
    if (!supabase) {
      setLoading(false);
      return;
    }

    const getSession = async () => {
        const { data: { session } } = await supabase.auth.getSession();
        setUser(session?.user as User ?? null);
        setLoading(false);
    };
    getSession();

    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        setUser(session?.user as User ?? null);
      }
    );

    return () => {
      subscription?.unsubscribe();
    };
  }, [supabase]);

  const throwUnconfiguredError = () => {
    const error = new Error('Supabase is not configured. Please check your environment variables.') as AuthError;
    error.name = 'ConfigurationError';
    return { data: { user: null, session: null }, error };
  }

  const signInWithEmail = async (credentials: SignInWithPasswordCredentials) => {
    if (!supabase) return throwUnconfiguredError();
    const { error } = await supabase.auth.signInWithPassword(credentials);
    return { error };
  };

  const signUpWithEmail = async (email: string, password: string, companyName: string) => {
    if (!supabase) return throwUnconfiguredError();
    // This passes the company_name in the metadata, which the database trigger uses.
    const { data, error } = await supabase.auth.signUp({ 
      email, 
      password,
      options: {
        data: {
          company_name: companyName,
        }
      }
    });

    return { data: data as { user: User | null; session: Session | null }, error };
  };

  const signOut = async () => {
    if (!supabase) return { error: null };
    const { error } = await supabase.auth.signOut();
    return { error };
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
