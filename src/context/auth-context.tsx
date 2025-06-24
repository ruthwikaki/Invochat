'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import type { User, SupabaseClient } from '@supabase/supabase-js';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';

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
  const [supabase] = useState<SupabaseClient | null>(() => createBrowserSupabaseClient());


  useEffect(() => {
    if (!supabase) {
        setLoading(false);
        return;
    }

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
    if (!supabase) throw new Error("Supabase client is not initialized.");
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    if (error) {
      throw error;
    }
  };
  
  const signOut = async () => {
    if (!supabase) throw new Error("Supabase client is not initialized.");
    await supabase.auth.signOut();
  };

  const value = {
    user,
    loading,
    signInWithEmail,
    signOut,
  };
  
  if (!supabase && !loading) {
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
