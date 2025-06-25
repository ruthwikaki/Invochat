
'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
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
  const [supabase] = useState<SupabaseClient | null>(() => createBrowserSupabaseClient());
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const [initialLoadComplete, setInitialLoadComplete] = useState(false);
  const router = useRouter();
  
  const isConfigured = !!supabase;

  useEffect(() => {
    if (!supabase) {
      console.log('🔴 AuthContext: Supabase not configured');
      setLoading(false);
      return;
    }

    let mounted = true;

    console.log('🟡 AuthContext: Setting up auth state management');

    // Get initial session first
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
          setInitialLoadComplete(true);
        }
      } catch (error) {
        console.error('🔴 AuthContext: Exception getting initial session:', error);
        if (mounted) {
          setUser(null);
          setLoading(false);
          setInitialLoadComplete(true);
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
          initialLoadComplete
        });

        if (mounted) {
          const authUser = session?.user as User ?? null;
          setUser(authUser);
          
          // Only set loading to false if we haven't completed initial load
          if (!initialLoadComplete) {
            setLoading(false);
            setInitialLoadComplete(true);
          }
          
          // Handle different auth events
          if (event === 'SIGNED_OUT') {
            console.log('🚪 AuthContext: User signed out, redirecting to login');
            // Small delay to ensure state is updated
            setTimeout(() => {
              router.push('/login');
            }, 100);
          } else if (event === 'SIGNED_IN') {
            console.log('🔐 AuthContext: User signed in');
            // Don't redirect here, let middleware handle it
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
  }, [supabase, router, initialLoadComplete]);

  const signOut = async () => {
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
  };

  const value = {
    user,
    loading,
    isConfigured,
    signOut,
  };

  // Debug logging for state changes
  useEffect(() => {
    console.log('📊 AuthContext State:', {
      hasUser: !!user,
      loading,
      isConfigured,
      initialLoadComplete,
      userEmail: user?.email,
      companyId: user?.app_metadata?.company_id
    });
  }, [user, loading, isConfigured, initialLoadComplete]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
