
'use client';

import { createContext, useContext, useState, useEffect, ReactNode, useCallback, useRef } from 'react';
import type { SupabaseClient, AuthError } from '@supabase/supabase-js';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';
import type { User } from '@/types';
import { useRouter } from 'next/navigation';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  isConfigured: boolean;
  signOut: () => Promise<{ error: AuthError | null }>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  // Use useRef to ensure supabase client is only created once
  const supabaseRef = useRef<SupabaseClient | null>(null);
  if (!supabaseRef.current) {
    supabaseRef.current = createBrowserSupabaseClient();
  }
  const supabase = supabaseRef.current;

  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [initialized, setInitialized] = useState(false);
  const router = useRouter();
  
  const isConfigured = !!supabase;

  // Memoize the signOut function to prevent unnecessary re-renders
  const signOut = useCallback(async () => {
    if (!supabase) return { error: null };
    
    console.log('🚪 AuthContext: Signing out user');
    
    try {
      const { error } = await supabase.auth.signOut();
      if (error) {
        console.error('🔴 AuthContext: Sign out error:', error);
      } else {
        console.log('✅ AuthContext: Sign out successful');
      }
      return { error };
    } catch (error) {
      console.error('🔴 AuthContext: Sign out exception:', error);
      return { error: error as AuthError };
    }
  }, [supabase]);

  useEffect(() => {
    if (!supabase) {
      console.log('🔴 AuthContext: Supabase not configured');
      setLoading(false);
      return;
    }

    // Prevent multiple initializations
    if (initialized) {
      console.log('⚠️ AuthContext: Already initialized, skipping');
      return;
    }

    console.log('🟡 AuthContext: Setting up auth state management');
    setInitialized(true);

    let mounted = true;

    // Get initial session
    const getInitialSession = async () => {
      try {
        console.log('🔍 AuthContext: Getting initial session...');
        const { data: { session }, error } = await supabase.auth.getSession();
        
        if (error) {
          console.error('🔴 AuthContext: Error getting initial session:', error);
        }

        if (mounted) {
          const authUser = session?.user as User ?? null;
          console.log('🟢 AuthContext: Initial session loaded:', {
            hasSession: !!session,
            hasUser: !!authUser,
            userId: authUser?.id,
            email: authUser?.email,
            companyId: authUser?.app_metadata?.company_id
          });
          
          setUser(authUser);
          setLoading(false);
        }
      } catch (error) {
        console.error('🔴 AuthContext: Exception getting initial session:', error);
        if (mounted) {
          setUser(null);
          setLoading(false);
        }
      }
    };

    // Set up auth state change listener
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      async (event, session) => {
        console.log('🔄 AuthContext: Auth state changed:', {
          event,
          hasSession: !!session,
          hasUser: !!session?.user,
          mounted
        });

        if (mounted) {
          const authUser = session?.user as User ?? null;
          setUser(authUser);
          setLoading(false);
          
          // Handle different auth events
          if (event === 'SIGNED_OUT') {
            console.log('🚪 AuthContext: User signed out, redirecting to login');
            // Use replace instead of push to prevent back button issues
            router.replace('/login');
          } else if (event === 'SIGNED_IN') {
            console.log('🔐 AuthContext: User signed in');
          } else if (event === 'TOKEN_REFRESHED') {
            console.log('🔄 AuthContext: Token refreshed');
          }
        }
      }
    );

    // Get initial session
    getInitialSession();

    return () => {
      console.log('🧹 AuthContext: Cleaning up');
      mounted = false;
      subscription?.unsubscribe();
    };
  }, [supabase, router, initialized]); // Added initialized to dependencies

  // Debug logging for state changes - but only when state actually changes
  useEffect(() => {
    console.log('📊 AuthContext State:', {
      hasUser: !!user,
      userEmail: user?.email,
      companyId: user?.app_metadata?.company_id,
      loading,
      isConfigured,
      initialized
    });
  }, [user?.id, user?.app_metadata?.company_id, loading, isConfigured, initialized]); // Only log when these specific values change

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
