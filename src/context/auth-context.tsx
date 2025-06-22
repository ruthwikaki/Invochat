
'use client';

import { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { onAuthStateChanged, User as FirebaseUser, signInWithEmailAndPassword, signOut } from 'firebase/auth';
import { auth } from '@/lib/firebase';

interface AuthContextType {
  user: FirebaseUser | null;
  loading: boolean;
  login: (email: string, pass: string) => Promise<any>;
  logout: () => Promise<any>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<FirebaseUser | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (auth) {
        const unsubscribe = onAuthStateChanged(auth, (user) => {
          setUser(user);
          setLoading(false);
        });
        return () => unsubscribe();
    } else {
        // If auth is not initialized, stop loading and treat as logged out.
        // This happens if Firebase env vars are not set.
        setLoading(false);
        setUser(null);
        console.warn("Firebase Auth is not initialized. Make sure your NEXT_PUBLIC_FIREBASE_* environment variables are set in your .env file.");
    }
  }, []);

  const login = (email: string, pass: string) => {
    if (!auth) {
        return Promise.reject(new Error("Firebase Auth is not initialized."));
    }
    return signInWithEmailAndPassword(auth, email, pass);
  };
  
  const logout = () => {
    if (!auth) {
        return Promise.reject(new Error("Firebase Auth is not initialized."));
    }
    return signOut(auth);
  }

  const value = {
    user,
    loading,
    login,
    logout,
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
