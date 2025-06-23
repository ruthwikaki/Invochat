
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

  // This is the core function that keeps user state in sync.
  const updateUserState = useCallback(async (firebaseUser: FirebaseUser | null) => {
    setLoading(true);
    setUser(firebaseUser);

    if (firebaseUser) {
      try {
        // Force a token refresh to get the latest custom claims.
        // This is crucial after signup or login for a demo user.
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

    // The onAuthStateChanged listener will fire, but for the demo user,
    // we need to ensure their profile exists BEFORE the state update.
    if (email === 'demo@example.com' && firebaseUser) {
        const idToken = await firebaseUser.getIdToken();
        await ensureDemoUserExists(idToken);
    }
    // After provisioning/login, force a state refresh to get the new profile & claims.
    await updateUserState(firebaseUser);
  };

  const signup = async (email: string, password: string): Promise<UserCredential> => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    const userCredential = await createUserWithEmailAndPassword(auth, email, password);
    // The onAuthStateChanged listener will handle the initial user state.
    // The profile/company setup is handled by a separate server action called from the signup page.
    // After that action, we must manually refresh the state.
    return userCredential;
  };
  
  const logout = async () => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    await signOut(auth);
    // State will be cleared by the onAuthStateChanged listener.
  };

  const resetPassword = (email: string) => {
    if (!auth) throw new Error("Firebase Auth is not initialized.");
    return sendPasswordResetEmail(auth, email);
  };

  const getIdToken = async () => {
    if (!auth?.currentUser) return null;
    return getFirebaseIdToken(auth.currentUser, true);
  };

  // Expose a manual refresh function for use after profile/company setup.
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
