
'use client';

import { createContext, useContext, useState, useEffect, ReactNode } from 'react';
import type { User } from 'firebase/auth';
import { auth } from '@/lib/firebase';
import { signInWithEmail as signInService, signOut as signOutService } from '@/services/auth.service';
import { signUpWithEmailAndPassword } from '@/app/auth-actions';

interface AuthContextType {
  user: User | null;
  loading: boolean;
  signInWithEmail: (email: string, password: string) => Promise<void>;
  signUpWithEmail: (formData: FormData) => Promise<{ success: boolean, error: string | null }>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const unsubscribe = auth.onAuthStateChanged(async (firebaseUser) => {
      if (firebaseUser) {
        // Refresh token to get latest custom claims
        await firebaseUser.getIdToken(true);
      }
      setUser(firebaseUser);
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  const signInWithEmail = async (email: string, password: string) => {
    await signInService(email, password);
    // onAuthStateChanged will handle the user state update
  };
  
  const signUpWithEmail = async (formData: FormData) => {
    const result = await signUpWithEmailAndPassword(formData);
    if(result.success) {
        // After successful server-side creation, sign the user in on the client
        const email = formData.get('email') as string;
        const password = formData.get('password') as string;
        await signInWithEmail(email, password);
    }
    return result;
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
