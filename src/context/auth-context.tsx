
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
    // The onAuthStateChange listener below will handle the redirect.
  }, [supabase]);

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
        
        // On sign out, forcefully redirect to login to ensure clean state.
        if (event === 'SIGNED_OUT') {
          router.push('/login');
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
