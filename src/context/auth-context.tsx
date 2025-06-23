
'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import type { User } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { signInWithEmail as signInService, signOut as signOutService, signUpWithEmail as signUpService } from '@/services/auth.service';

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

  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged((firebaseUser) => {
      setUser(firebaseUser);
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  const signInWithEmail = async (email: string, password: string) => {
    await signInService(email, password);
    // onAuthStateChanged will handle the user state update
  };
  
  const signUpWithEmail = async (email: string, password: string, companyName: string) => {
    await signUpService(email, password, companyName);
    // Force refresh to get custom claims
    if (auth.currentUser) {
        await auth.currentUser.getIdToken(true);
    }
    // onAuthStateChanged will handle the user state update, which will trigger redirect
  };

  const signOut = async () => {
    await signOutService();
    setUser(null);
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
