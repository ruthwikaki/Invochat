
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

  const fetchUserProfile = useCallback(async (currentUser: FirebaseUser | null) => {
    if (!currentUser) {
      setUserProfile(null);
      setLoading(false);
      return;
    }
    
    try {
      const { getUserProfile } = await import('@/app/actions');
      const idToken = await getFirebaseIdToken(currentUser);
      const profile = await getUserProfile(idToken);
      setUserProfile(profile);
    } catch (error) {
      console.error('Failed to fetch user profile:', error);
      setUserProfile(null);
    } finally {
      setLoading(false);
    }
  }, []);
  
  const refreshUserProfile = useCallback(async () => {
    if (!auth?.currentUser) return;
    setLoading(true); // Signal that a refresh is in progress
    await fetchUserProfile(auth.currentUser);
  }, [fetchUserProfile]);


  useEffect(() => {
    if (!isFirebaseEnabled || !auth) {
      setLoading(false);
      return;
    }

    const unsubscribe = onAuthStateChanged(auth, async (firebaseUser) => {
      setLoading(true);
      setUser(firebaseUser);
      await fetchUserProfile(firebaseUser);
    });

    return () => unsubscribe();
  }, [fetchUserProfile]);

  const login = async (email: string, password: string) => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    return signInWithEmailAndPassword(auth, email, password);
  };

  const signup = (email: string, password: string) => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    return createUserWithEmailAndPassword(auth, email, password);
  };
  
  const logout = async () => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    await signOut(auth);
    // onAuthStateChanged will handle setting user and profile to null
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
