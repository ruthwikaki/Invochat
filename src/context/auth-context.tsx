
'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import type { User, SupabaseClient } from '@supabase/supabase-js';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';
import { useRouter } from 'next/navigation';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  signInWithEmail: (email: string, password: string) => Promise<void>;
  signUpWithEmail: (email: string, password: string, companyName: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [supabase] = useState<SupabaseClient>(() => createBrowserSupabaseClient());
  const router = useRouter();

  useEffect(() => {
    // Get initial session
    const initAuth = async () => {
      try {
        const { data: { session } } = await supabase.auth.getSession();
        setUser(session?.user ?? null);
      } catch (error) {
        console.error('Error getting session:', error);
      } finally {
        setLoading(false);
      }
    };

    initAuth();

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      async (_event, session) => {
        setUser(session?.user ?? null);
        
        // Handle navigation based on auth state
        if (session?.user) {
          // User just logged in
          if (window.location.pathname === '/login' || window.location.pathname === '/signup') {
            router.push('/dashboard');
          }
        } else {
          // User logged out or no user
          if (!window.location.pathname.startsWith('/login') && 
              !window.location.pathname.startsWith('/signup') &&
              window.location.pathname !== '/') {
            router.push('/login');
          }
        }
      }
    );

    return () => {
      subscription?.unsubscribe();
    };
  }, [supabase, router]);

  const signInWithEmail = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    
    if (error) {
      throw error;
    }
  };

  const signUpWithEmail = async (email: string, password: string, companyName: string) => {
    // First, sign up the user
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
    });
    
    if (error) {
      throw error;
    }

    // If signup successful and user created, call handle_new_user
    if (data.user) {
      try {
        const { error: rpcError } = await supabase.rpc('handle_new_user', {
          company_name_param: companyName
        });
        
        if (rpcError) {
          console.error('Error creating company:', rpcError);
          // Don't throw here - user is created, just company setup failed
        }
      } catch (err) {
        console.error('Error calling handle_new_user:', err);
      }
    }
  };

  const signOut = async () => {
    const { error } = await supabase.auth.signOut();
    if (error) {
      throw error;
    }
  };

  const value = {
    user,
    loading,
    signInWithEmail,
    signUpWithEmail,
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
