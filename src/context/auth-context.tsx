
'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import type { SupabaseClient, AuthError } from '@supabase/supabase-js';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';
import type { User } from '@/types';
import { useRouter } from 'next/navigation';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  isConfigured: boolean;
  signOut: () => Promise<{ error: AuthError | null }>;
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

    let mounted = true;

    // This is the primary mechanism for keeping the client-side auth state in sync.
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        if (mounted) {
            setUser(session?.user as User ?? null);
            setLoading(false);
            
            // On sign out, the middleware will handle the redirect.
            // We can also push to the login page to ensure a clean transition.
            if (event === 'SIGNED_OUT') {
                router.push('/login');
            }
        }
      }
    );

    // Ensure we have the initial session on first load.
    const getInitialSession = async () => {
        const { data: { session } } = await supabase.auth.getSession();
        if (mounted) {
            setUser(session?.user as User ?? null);
            setLoading(false);
        }
    };
    
    getInitialSession();


    return () => {
      mounted = false;
      subscription?.unsubscribe();
    };
  }, [supabase, router]);

  const signOut = async () => {
    if (!supabase) return { error: null };
    
    // signOut will trigger the onAuthStateChange listener, which handles the user state.
    const { error } = await supabase.auth.signOut();
    if(error) {
        console.error('Sign out error:', error);
    }
    return { error };
  };

  const value = {
    user,
    loading,
    isConfigured,
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
