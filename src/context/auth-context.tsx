
'use client';

import { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { createBrowserClient } from '@supabase/ssr';
import type { User, Session, SupabaseClient } from '@supabase/supabase-js';
import { useRouter } from 'next/navigation';

interface AuthContextType {
  user: User | null;
  session: Session | null;
  loading: boolean;
  logout: () => Promise<void>;
  supabase: SupabaseClient;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  const [supabase] = useState(() => {
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    
    if (!supabaseUrl || !anonKey) {
      console.error('Supabase environment variables are missing');
      // Return a mock client to prevent crashes
      return {} as SupabaseClient;
    }
    
    return createBrowserClient(supabaseUrl, anonKey);
  });

  useEffect(() => {
    // Skip if supabase client is not properly initialized
    if (!supabase.auth) {
      setLoading(false);
      return;
    }

    const { data: authListener } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        setSession(session);
        setUser(session?.user ?? null);
        setLoading(false);
      }
    );

    const getInitialSession = async () => {
        try {
            const { data: { session }, error } = await supabase.auth.getSession();
            if (error) {
                console.warn('Error getting initial session:', error.message);
            }
            setSession(session);
            setUser(session?.user ?? null);
        } catch (error) {
            console.error('Failed to get initial session:', error);
        } finally {
            setLoading(false);
        }
    };

    getInitialSession();

    return () => {
      authListener.subscription.unsubscribe();
    };
  }, [supabase, router]);

  const logout = async () => {
    if (supabase.auth) {
      await supabase.auth.signOut();
    }
  };

  const value = {
    user,
    session,
    loading,
    logout,
    supabase,
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
