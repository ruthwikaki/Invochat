
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
  authLoading: boolean;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [supabase] = useState<SupabaseClient | null>(() => createBrowserSupabaseClient());
  const [user, setUser] = useState<User | null>(null);
  const [authLoading, setAuthLoading] = useState(true);
  const router = useRouter();
  
  const isConfigured = !!supabase;

  useEffect(() => {
    if (!supabase) {
      setAuthLoading(false);
      return;
    }

    // Set the initial user state
    const setInitialUser = async () => {
        const { data: { user } } = await supabase.auth.getUser();
        setUser(user);
        setAuthLoading(false);
    }
    setInitialUser();

    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      (event, session) => {
        setUser(session?.user ?? null);
        
        // On sign-in or sign-out, refresh the page.
        // This will cause Next.js to re-run the middleware with the new
        // session cookie, which correctly handles redirects.
        if (event === 'SIGNED_IN' || event === 'SIGNED_OUT') {
           router.refresh();
        }
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
    // Navigation is handled by onAuthStateChange listener
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
    // the onAuthStateChange listener will handle the refresh.
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
    // Navigation is handled by onAuthStateChange listener
  };

  const value = {
    user,
    loading: authLoading,
    authLoading,
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
