
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
  // Use useState to hold the Supabase client instance.
  const [supabase] = useState<SupabaseClient | null>(() => createBrowserSupabaseClient());
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();
  
  // isConfigured is true if the Supabase client was successfully created.
  const isConfigured = !!supabase;

  // Define the signOut function once and wrap in useCallback for stability.
  const signOut = useCallback(async () => {
    if (!supabase) return;
    await supabase.auth.signOut();
    // Use router.refresh() to force a server-side re-render and re-run middleware.
    // This is crucial for ensuring a clean state after sign-out.
    router.refresh();
  }, [supabase, router]);

  useEffect(() => {
    if (!supabase) {
      // If Supabase isn't configured, we stop loading and do nothing else.
      setLoading(false);
      return;
    }

    // Set up a listener for authentication state changes.
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        const currentUser = session?.user as User ?? null;
        setUser(currentUser);
        setLoading(false);

        // On SIGNED_IN or SIGNED_OUT events, refresh the page to ensure all
        // server components are updated with the new session state.
        if (event === 'SIGNED_IN' || event === 'SIGNED_OUT') {
            router.refresh();
        }
      }
    );

    // Cleanup: Unsubscribe from the listener when the component unmounts.
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
