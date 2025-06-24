
'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import type { User, SupabaseClient, AuthError } from '@supabase/supabase-js';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';
import { useRouter } from 'next/navigation';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  isConfigured: boolean;
  signInWithEmail: (email: string, password: string) => Promise<{ error: AuthError | null }>;
  signUpWithEmail: (email: string, password: string, companyName: string) => Promise<{ error: AuthError | null }>;
  signOut: () => Promise<void>;
  authLoading: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [supabase] = useState<SupabaseClient | null>(() => createBrowserSupabaseClient());
  const [user, setUser] = useState<User | null>(null);
  const [authLoading, setAuthLoading] = useState(true);
  const router = useRouter();
  
  const isConfigured = !!supabase;

  useEffect(() => {
    if (!supabase) {
      setAuthLoading(false);
      return;
    }

    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        // on SIGNED_IN or SIGNED_OUT, we want to refresh the page
        // to let the middleware handle the redirect.
        if (event === 'SIGNED_IN' || event === 'SIGNED_OUT') {
          router.refresh();
        }
        setUser(session?.user ?? null);
        setAuthLoading(false);
      }
    );

    // Set initial user state on load
    const setInitialUser = async () => {
        const { data: { session } } = await supabase.auth.getSession();
        setUser(session?.user ?? null);
        setAuthLoading(false);
    }
    setInitialUser();

    return () => {
      subscription?.unsubscribe();
    };
  }, [supabase, router]);

  const throwUnconfiguredError = () => {
    const error = new Error('Supabase is not configured. Please check your environment variables.') as AuthError;
    error.name = 'ConfigurationError';
    return { error };
  }

  const signInWithEmail = async (email: string, password: string) => {
    if (!supabase) return throwUnconfiguredError();
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    return { error };
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

    return { error };
  };

  const signOut = async () => {
    if (!supabase) return;
    await supabase.auth.signOut();
  };

  const value = {
    user,
    loading: authLoading,
    authLoading,
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
