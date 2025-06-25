
'use client';

import { createContext, useContext, useState, useEffect, ReactNode, useCallback } from 'react';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';
import type { User } from '@/types';
import { useRouter } from 'next/navigation';
import type { SupabaseClient } from '@supabase/supabase-js';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  isConfigured: boolean;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  // Use the new ssr library's browser client
  const [supabase] = useState<SupabaseClient | null>(() => createBrowserSupabaseClient());
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();
  
  const isConfigured = !!(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);

  const signOut = useCallback(async () => {
    if (!supabase) return;
    await supabase.auth.signOut();
    router.refresh();
  }, [supabase, router]);

  useEffect(() => {
    if (!supabase) {
      setLoading(false);
      return;
    }

    // 1. Fetch the initial session to hydrate the user state quickly.
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user as User ?? null);
      setLoading(false);
    });
    
    // 2. Set up a listener for subsequent authentication state changes.
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        const currentUser = session?.user as User ?? null;
        setUser(currentUser);
        setLoading(false);

        if (event === 'SIGNED_IN' || event === 'SIGNED_OUT') {
            router.refresh();
        }
      }
    );

    return () => {
      subscription?.unsubscribe();
    };
  }, [supabase, router]);

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
