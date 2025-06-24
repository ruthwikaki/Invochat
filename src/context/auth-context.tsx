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
  signUpWithEmail: (email: string, password: string, companyName: string) => Promise<{isSuccess: boolean}>;
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

    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      async (_event, session) => {
        setUser(session?.user ?? null);
      }
    );

    return () => {
      subscription?.unsubscribe();
    };
  }, [supabase]);

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
  };

  const signUpWithEmail = async (email: string, password: string, companyName: string): Promise<{isSuccess: boolean}> => {
    if (!supabase) return throwUnconfiguredError();
    
    // Create company first
    const { data: company, error: companyError } = await supabase
      .from('companies')
      .insert({ name: companyName })
      .select()
      .single();

    if (companyError) {
      console.error('Company creation error:', companyError);
      throw new Error('Failed to create company. The name might already be taken.');
    }

    // Create auth user with company_id in metadata
    const { data, error } = await supabase.auth.signUp({ 
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

    // If signup is successful and returns a user session (meaning email confirmation is off),
    // signal success to the caller so it can navigate.
    if (data.session) {
        return { isSuccess: true };
    }

    // Otherwise, tell the UI to show the "check email" message.
    return { isSuccess: false };
  };

  const signOut = async () => {
    if (!supabase) return throwUnconfiguredError();
    
    const { error } = await supabase.auth.signOut();
    if (error) throw error;
    
    // On success, navigate to login
    router.push('/login');
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
