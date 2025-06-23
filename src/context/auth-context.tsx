
'use client';

import { createContext, useContext, useEffect, useState, ReactNode, useCallback } from 'react';
import { 
    onAuthStateChanged, 
    User as FirebaseUser, 
    signInWithEmailAndPassword, 
    signOut,
    createUserWithEmailAndPassword,
    sendPasswordResetEmail
} from 'firebase/auth';
import { auth, isFirebaseEnabled } from '@/lib/firebase';
import { getUserProfile } from '@/services/database';
import type { UserProfile } from '@/types';
import { useRouter } from 'next/navigation';

interface AuthContextType {
  user: FirebaseUser | null;
  userProfile: UserProfile | null;
  loading: boolean;
  login: (email: string, pass: string) => Promise<any>;
  signup: (email: string, pass: string) => Promise<any>;
  logout: () => Promise<any>;
  getIdToken: () => Promise<string | null>;
  resetPassword: (email: string) => Promise<void>;
  refreshUserProfile: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<FirebaseUser | null>(null);
  const [userProfile, setUserProfile] = useState<UserProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  const refreshUserProfile = useCallback(async () => {
    if (auth?.currentUser) {
        try {
            const profile = await getUserProfile(auth.currentUser.uid);
            setUserProfile(profile);
        } catch (error) {
            console.error("Failed to refresh user profile", error);
            setUserProfile(null);
        }
    }
  }, []);

  useEffect(() => {
    if (!isFirebaseEnabled || !auth) {
      setLoading(false);
      return;
    }
    const unsubscribe = onAuthStateChanged(auth, async (user) => {
      setLoading(true);
      if (user) {
        setUser(user);
        try {
            const profile = await getUserProfile(user.uid);
            setUserProfile(profile);
        } catch (error) {
            console.error("Failed to fetch user profile on auth change", error);
            setUserProfile(null);
        }
      } else {
        setUser(null);
        setUserProfile(null);
      }
      setLoading(false);
    });

    return () => unsubscribe();
  }, []);

  const login = (email: string, pass: string) => {
    if (!auth) return Promise.reject(new Error("Firebase is not configured."));
    return signInWithEmailAndPassword(auth, email, pass);
  };
  
  const signup = (email: string, pass: string) => {
    if (!auth) return Promise.reject(new Error("Firebase is not configured."));
    return createUserWithEmailAndPassword(auth, email, pass);
  };

  const logout = async () => {
    if (!auth) throw new Error("Firebase is not configured.");
    await signOut(auth);
    router.push('/login');
  }

  const resetPassword = (email: string) => {
    if (!auth) return Promise.reject(new Error("Firebase is not configured."));
    return sendPasswordResetEmail(auth, email);
  }

  const getIdToken = async () => {
    if (!auth?.currentUser) return null;
    try {
      // Force refresh of the token to ensure it's not expired.
      return await auth.currentUser.getIdToken(true); 
    } catch (error) {
      console.error("Error getting ID token:", error);
      // It's possible the user's session became invalid, so log them out.
      await logout();
      return null;
    }
  };

  const value = {
    user,
    userProfile,
    loading,
    login,
    signup,
    logout,
    getIdToken,
    resetPassword,
    refreshUserProfile
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
