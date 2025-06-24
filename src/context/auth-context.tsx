
'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import type { User, SupabaseClient } from '@supabase/supabase-js';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';
import { useRouter } from 'next/navigation';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  isConfigured: boolean;
  signInWithEmail: (email: string, password: string) => Promise<void>;
  signUpWithEmail: (email: string, password: string, companyName: string) => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [supabase] = useState<SupabaseClient | null>(() => createBrowserSupabaseClient());
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();
  
  const isConfigured = !!supabase;

  useEffect(() => {
    if (!supabase) {
      setLoading(false);
      return;
    }

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
        // On sign-in or sign-out, refresh the page to apply middleware redirects
        router.refresh();
      }
    );

    return () => {
      subscription?.unsubscribe();
    };
  }, [supabase, router]);

  const throwUnconfiguredError = () => {
    throw new Error('Supabase is not configured. Please check your environment variables.');
  }

  const signInWithEmail = async (email: string, password: string) => {
    if (!supabase) return throwUnconfiguredError();
    
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    
    if (error) throw error;
    
    // router.refresh() is called by the onAuthStateChange listener
  };

  const signUpWithEmail = async (email: string, password: string, companyName: string) => {
    if (!supabase) return throwUnconfiguredError();
    
    try {
      // Create company first
      const { data: company, error: companyError } = await supabase
        .from('companies')
        .insert({ name: companyName })
        .select()
        .single();
  
      if (companyError) {
        console.error('Company creation error:', companyError);
        throw new Error('Failed to create company');
      }
  
      // Create auth user with company_id in metadata
      const { error } = await supabase.auth.signUp({ 
        email, 
        password,
        options: {
          data: {
            company_id: company.id,
            full_name: email.split('@')[0]
          }
        }
      });
      
      if (error) {
        // Clean up company if auth fails
        await supabase.from('companies').delete().eq('id', company.id);
        throw error;
      }
      
      // router.refresh() will be called by onAuthStateChange listener
      
    } catch (error) {
      console.error('Signup error:', error);
      throw error;
    }
  };

  const signOut = async () => {
    if (!supabase) return throwUnconfiguredError();
    
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
    
    // router.refresh() is called by the onAuthStateChange listener
  };

  const value = {
    user,
    loading,
    isConfigured,
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
