
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
  const [supabase] = useState<SupabaseClient | null>(() => createBrowserSupabaseClient());
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();
  
  const isConfigured = !!(process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY);

  const signOut = useCallback(async () => {
    if (!supabase) return;
    
    // Clear the user state immediately
    setUser(null);
    
    // Sign out from Supabase
    const { error } = await supabase.auth.signOut();
    if (error) {
      console.error('Error signing out:', error);
    }
    
    // Navigate to login
    router.push('/login');
  }, [supabase, router]);

  useEffect(() => {
    if (!supabase) {
      setLoading(false);
      return;
    }

    let mounted = true;

    // 1. Get initial session
    const initializeAuth = async () => {
      try {
        const { data: { session } } = await supabase.auth.getSession();
        if (mounted) {
          setUser(session?.user as User ?? null);
          setLoading(false);
        }
      } catch (error) {
        console.error('Error initializing auth:', error);
        if (mounted) {
          setLoading(false);
        }
      }
    };

    initializeAuth();
    
    // 2. Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        if (mounted) {
          setUser(session?.user as User ?? null);
        }
      }
    );

    return () => {
      mounted = false;
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
