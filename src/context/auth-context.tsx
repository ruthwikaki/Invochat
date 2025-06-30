
'use client';

import { createContext, useContext, useState, useEffect, ReactNode, useCallback } from 'react';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';
import type { User } from '@/types';
import { useRouter } from 'next/navigation';
import type { SupabaseClient, Subscription } from '@supabase/supabase-js';
import { logError } from '@/lib/error-handler';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  isConfigured: boolean;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [supabase] = useState<SupabaseClient | null>(() => createBrowserSupabaseClient());
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();
  
  const isConfigured = !!(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);

  const signOut = useCallback(async () => {
    if (!supabase) return;
    
    setUser(null);
    const { error } = await supabase.auth.signOut();
    if (error) {
      logError(error, { context: 'signOut' });
    }
    router.push('/login');
  }, [supabase, router]);

  useEffect(() => {
    if (!supabase) {
      setLoading(false);
      return;
    }

    let mounted = true;
    let authListener: Subscription | undefined;

    const initializeAndListen = async () => {
      // 1. Get initial session
      try {
        const { data: { session } } = await supabase.auth.getSession();
        if (mounted) {
          setUser(session?.user as User ?? null);
        }
      } catch (error) {
        logError(error, { context: 'getSession in auth-context' });
      } finally {
        if (mounted) {
          setLoading(false);
        }
      }

      // 2. Listen for auth changes
      const { data: { subscription } } = supabase.auth.onAuthStateChange(
        (_event, session) => {
          if (mounted) {
            setUser(session?.user as User ?? null);
          }
        }
      );
      authListener = subscription;
    };

    initializeAndListen();

    return () => {
      mounted = false;
      authListener?.unsubscribe();
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
