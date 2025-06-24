
'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import type { User, SupabaseClient } from '@supabase/supabase-js';
import { createBrowserClient } from '@supabase/ssr';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  signInWithEmail: (email: string, password: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

function SupabaseConfigurationError() {
    return (
        <div className="flex h-dvh w-full flex-col items-center justify-center bg-background p-4 text-center">
            <div className="max-w-lg space-y-4 rounded-lg border border-destructive bg-card p-8">
                 <h1 className="text-2xl font-bold text-destructive">Supabase Configuration Error</h1>
                 <p className="text-muted-foreground">
                    The application is missing required Supabase environment variables. Please add <code className="font-mono bg-muted px-1 py-0.5 rounded">NEXT_PUBLIC_SUPABASE_URL</code> and <code className="font-mono bg-muted px-1 py-0.5 rounded">NEXT_PUBLIC_SUPABASE_ANON_KEY</code> to your environment file.
                 </p>
                  <p className="text-sm text-muted-foreground">The app cannot function without these settings.</p>
            </div>
        </div>
    )
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [supabase, setSupabase] = useState<SupabaseClient | null>(null);

  useEffect(() => {
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

    if (supabaseUrl && supabaseAnonKey) {
        setSupabase(createBrowserClient(supabaseUrl, supabaseAnonKey));
    } else {
        console.error("Supabase environment variables are missing!");
        setLoading(false);
    }
  }, []);

  useEffect(() => {
    if (!supabase) {
      if (!loading) setLoading(true);
      return;
    }

    const getInitialSession = async () => {
      const { data: { session } } = await supabase.auth.getSession();
      setUser(session?.user ?? null);
      setLoading(false);
    };

    getInitialSession();

    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (_event, session) => {
        setUser(session?.user ?? null);
        setLoading(false);
      }
    );

    return () => {
      subscription?.unsubscribe();
    };
  }, [supabase]);

  const signInWithEmail = async (email: string, password: string) => {
    if (!supabase) throw new Error("Supabase is not configured.");
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    if (error) {
      throw error;
    }
  };
  
  const signOut = async () => {
    if (!supabase) throw new Error("Supabase is not configured.");
    const { error } = await supabase.auth.signOut();
    if (error) {
        console.error('Error signing out:', error);
        throw error;
    }
    setUser(null);
  };

  const value = {
    user,
    loading,
    signInWithEmail,
    signOut,
  };

  if (!loading && !supabase) {
      return <SupabaseConfigurationError />;
  }

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
