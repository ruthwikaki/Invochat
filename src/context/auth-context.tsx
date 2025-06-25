
'use client';

import { createContext, useContext, useState, useEffect, ReactNode, useCallback } from 'react';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';
import type { User } from '@/types';
import { useRouter } from 'next/navigation';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  isConfigured: boolean;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [supabase] = useState(() => createBrowserSupabaseClient());
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();
  
  const isConfigured = !!supabase;

  const signOut = useCallback(async () => {
    if (!supabase) return;
    await supabase.auth.signOut();
    // After signing out, the middleware will handle the server-side redirect.
    // We push to the login page on the client for a smoother UX.
    router.push('/login');
    router.refresh(); // Force a refresh to ensure all server components re-evaluate.
  }, [supabase, router]);

  useEffect(() => {
    if (!supabase) {
      setLoading(false);
      return;
    }

    // This single listener is the most reliable way to manage auth state.
    // It handles the initial load (SIGNED_IN) and all subsequent changes.
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        const currentUser = session?.user as User ?? null;
        setUser(currentUser);
        setLoading(false);
      }
    );

    return () => {
      subscription?.unsubscribe();
    };
  }, [supabase]);

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
