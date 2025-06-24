
'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import type { User, SupabaseClient, AuthError, Session, SignInWithPasswordCredentials } from '@supabase/supabase-js';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';
import { useRouter } from 'next/navigation';

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

    // Get initial session
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user as User ?? null);
      setLoading(false);
    });

    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        setUser(session?.user as User ?? null);
        
        // Handle sign in event
        if (event === 'SIGNED_IN' && session) {
          router.push('/dashboard');
        }
        
        // Handle sign out event
        if (event === 'SIGNED_OUT') {
          router.push('/login');
        }
      }
    );

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
    // Supabase types this as having a non-null user/session on success, which we'll rely on.
    return supabase.auth.signInWithPassword(credentials) as Promise<{ data: { user: User; session: Session; } | { user: null; session: null; }; error: AuthError | null; }>;
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
    await supabase.auth.signOut();
    setUser(null);
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
