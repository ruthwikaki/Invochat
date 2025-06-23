
'use client';

import { createContext, useContext, useEffect, useState, ReactNode, useCallback } from 'react';
import { 
  onAuthStateChanged, 
  User as FirebaseUser, 
  signInWithEmailAndPassword, 
  createUserWithEmailAndPassword,
  signOut,
  sendPasswordResetEmail,
  getIdToken as getFirebaseIdToken
} from 'firebase/auth';
import { auth, isFirebaseEnabled } from '@/lib/firebase';
import type { UserProfile } from '@/types';
import { useRouter } from 'next/navigation';

interface AuthContextType {
  user: FirebaseUser | null;
  userProfile: UserProfile | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<any>;
  signup: (email: string, password: string) => Promise<any>;
  logout: () => Promise<any>;
  getIdToken: () => Promise<string | null>;
  resetPassword: (email: string) => Promise<any>;
  refreshUserProfile: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<FirebaseUser | null>(null);
  const [userProfile, setUserProfile] = useState<UserProfile | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  const refreshUserProfile = useCallback(async () => {
    const currentUser = auth?.currentUser;
    if (!currentUser) {
      setUserProfile(null);
      return;
    }
    
    try {
      // The dynamic import here is to avoid circular dependencies in server components
      const { getUserProfile } = await import('@/app/actions');
      const idToken = await getFirebaseIdToken(currentUser);
      const profile = await getUserProfile(idToken);
      setUserProfile(profile);
    } catch (error) {
      console.error('Failed to fetch user profile:', error);
      setUserProfile(null);
    }
  }, []);

  useEffect(() => {
    if (!isFirebaseEnabled || !auth) {
      setLoading(false);
      return;
    }

    const unsubscribe = onAuthStateChanged(auth, async (firebaseUser) => {
      setLoading(true);
      setUser(firebaseUser);
      
      if (firebaseUser) {
        // Set a brief timeout to allow custom claims to propagate after login/signup
        setTimeout(() => refreshUserProfile(), 1000);
      } else {
        setUserProfile(null);
      }
      
      setLoading(false);
    });

    return () => unsubscribe();
  }, [refreshUserProfile]);

  const login = async (email: string, password: string) => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    const result = await signInWithEmailAndPassword(auth, email, password);
    await refreshUserProfile();
    return result;
  };

  const signup = (email: string, password: string) => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    return createUserWithEmailAndPassword(auth, email, password);
  };
  
  const logout = async () => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    await signOut(auth);
    setUserProfile(null);
    router.push('/login');
  };

  const resetPassword = (email: string) => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    return sendPasswordResetEmail(auth, email);
  };

  const getIdToken = async () => {
    if (!auth?.currentUser) return null;
    return auth.currentUser.getIdToken(true);
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
    refreshUserProfile,
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
