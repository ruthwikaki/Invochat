
'use client';

import { createContext, useContext, useEffect, useState, ReactNode, useCallback } from 'react';
import { 
  onAuthStateChanged, 
  User as FirebaseUser, 
  signInWithEmailAndPassword, 
  createUserWithEmailAndPassword,
  signOut,
  sendPasswordResetEmail,
  getIdToken as getFirebaseIdToken,
  UserCredential
} from 'firebase/auth';
import { auth, isFirebaseEnabled } from '@/lib/firebase';
import type { UserProfile } from '@/types';
import { ensureDemoUserExists, getUserProfile } from '@/app/actions';

interface AuthContextType {
  user: FirebaseUser | null;
  userProfile: UserProfile | null;
  loading: boolean;
  login: (email: string, password: string) => Promise<void>;
  signup: (email: string, password: string) => Promise<UserCredential>;
  logout: () => Promise<void>;
  getIdToken: () => Promise<string | null>;
  resetPassword: (email: string) => Promise<void>;
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
        // Force a token refresh to get the latest custom claims (like companyId)
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
    const firebaseUser = userCredential.user;

    if (email === 'demo@example.com' && firebaseUser) {
        const idToken = await firebaseUser.getIdToken();
        await ensureDemoUserExists(idToken);
        // Force a state refresh after provisioning to get the new profile & claims
        await updateUserState(firebaseUser);
    }
    // For other users, onAuthStateChanged handles the update automatically.
  };

  const signup = (email: string, password: string) => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    return createUserWithEmailAndPassword(auth, email, password);
  };
  
  const logout = async () => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    await signOut(auth);
    setUser(null);
    setUserProfile(null);
  };

  const resetPassword = (email: string) => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    return sendPasswordResetEmail(auth, email);
  };

  const getIdToken = async () => {
    if (!auth?.currentUser) return null;
    return getFirebaseIdToken(auth.currentUser, true);
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

  return (
    <AuthContext.Provider value={value}>
        {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
