
'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import { useRouter } from 'next/navigation';
import type { SupabaseClient, AuthError, Session, SignInWithPasswordCredentials } from '@supabase/supabase-js';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';
import type { User } from '@/types';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  isConfigured: boolean;
  signInWithEmail: (credentials: SignInWithPasswordCredentials) => Promise<{ data: { user: User; session: Session; } | { user: null; session: null; }; error: AuthError | null }>;
  signUpWithEmail: (email: string, password: string, companyName: string) => Promise<{ data: { user: User | null; session: Session | null; }; error: AuthError | null; }>;
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

    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        // This listener is the single source of truth for the user state.
        setUser(session?.user as User ?? null);
        setLoading(false);

        // On successful sign-in, redirect to the dashboard.
        // This is the most reliable way, as it fires *after* Supabase confirms authentication.
        if (event === 'SIGNED_IN') {
          router.push('/dashboard');
        }

        // On sign-out, redirect to the login page.
        if (event === 'SIGNED_OUT') {
          router.push('/login');
        }
      }
    );

    // Also check the initial session when the app loads.
    supabase.auth.getSession().then(({ data: { session } }) => {
        if (!session) {
            setLoading(false);
        }
        // The onAuthStateChange listener will handle setting the user and loading state
        // if a session exists, so we don't need to do it here to avoid race conditions.
    });

    return () => {
      subscription?.unsubscribe();
    };
  }, [supabase, router]);

  const throwUnconfiguredError = () => {
    const error = new Error('Supabase is not configured. Please check your environment variables.') as AuthError;
    error.name = 'ConfigurationError';
    return { data: { user: null, session: null }, error };
  }

  const signInWithEmail = async (credentials: SignInWithPasswordCredentials) => {
    if (!supabase) return throwUnconfiguredError();
    // We just call the function. The onAuthStateChange listener will handle the result.
    const result = await supabase.auth.signInWithPassword(credentials);
    return result as Promise<{ data: { user: User; session: Session; } | { user: null; session: null; }; error: AuthError | null; }>;
  };

  const signUpWithEmail = async (email: string, password: string, companyName: string) => {
    if (!supabase) return throwUnconfiguredError();
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
    if (!supabase) return;
    // The onAuthStateChange listener will handle the redirect.
    await supabase.auth.signOut();
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
