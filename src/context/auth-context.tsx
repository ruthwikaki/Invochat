
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
import { ensureDemoUserExists, getUserProfile } from '@/app/actions';


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

  const updateUserState = useCallback(async (firebaseUser: FirebaseUser | null) => {
    setLoading(true);
    setUser(firebaseUser);

    if (firebaseUser) {
      try {
        const idToken = await getFirebaseIdToken(firebaseUser, true);
        const profile = await getUserProfile(idToken);
        setUserProfile(profile);
      } catch (error) {
        console.error('Failed to fetch user profile:', error);
        setUserProfile(null);
      }
    } else {
      setUserProfile(null);
    }
    setLoading(false);
  }, []);

  useEffect(() => {
    if (!isFirebaseEnabled || !auth) {
      setLoading(false);
      return;
    }

    const unsubscribe = onAuthStateChanged(auth, (firebaseUser) => {
      updateUserState(firebaseUser);
    });

    return () => unsubscribe();
  }, [updateUserState]);

  const login = async (email: string, password: string) => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");

    const userCredential = await signInWithEmailAndPassword(auth, email, password);
    
    if (email === 'demo@example.com' && userCredential.user) {
        const idToken = await userCredential.user.getIdToken();
        await ensureDemoUserExists(idToken);
        // onAuthStateChanged will fire and handle the profile update.
        await updateUserState(userCredential.user);
    }
    
    return userCredential;
  };

  const signup = (email: string, password: string) => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    return createUserWithEmailAndPassword(auth, email, password);
  };
  
  const logout = async () => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    await signOut(auth);
  };

  const resetPassword = (email: string) => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    return sendPasswordResetEmail(auth, email);
  };

  const getIdToken = async () => {
    if (!auth?.currentUser) return null;
    return auth.currentUser.getIdToken(true);
  };

  const refreshUserProfile = useCallback(async () => {
    if (auth.currentUser) {
      await updateUserState(auth.currentUser);
    }
  }, [updateUserState]);

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
