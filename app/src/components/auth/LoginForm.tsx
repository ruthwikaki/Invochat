
'use client';

import React, { useState, useEffect } from 'react';
import Link from 'next/link';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { PasswordInput } from './PasswordInput';
import { useAuth } from '@/context/auth-context';
import { getErrorMessage } from '@/lib/error-handler';
import { useRouter } from 'next/navigation';

interface LoginFormProps {
    initialError: string | null;
}

export function LoginForm({ initialError }: LoginFormProps) {
  const [error, setError] = useState(initialError);
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const { login, loading } = useAuth();

  useEffect(() => {
    setError(initialError);
    if (initialError) {
        const url = new URL(window.location.href);
        url.searchParams.delete('error');
        window.history.replaceState({}, '', url.toString());
    }
  }, [initialError]);

  const handleLogin = async (e: React.FormEvent) => {
      e.preventDefault();
      setError(null);
      try {
          await login(email, password);
          // The redirect is handled by the AuthProvider's onAuthStateChange
      } catch (e) {
          setError(getErrorMessage(e));
      }
  };

  const handleInteraction = () => {
    if (error) setError(null);
  };

  return (
    <form onSubmit={handleLogin} className="space-y-4" onChange={handleInteraction}>
        <div className="space-y-2">
            <Label htmlFor="email" className="text-slate-300">Email</Label>
            <Input
                id="email"
                name="email"
                type="email"
                placeholder="you@company.com"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                disabled={loading}
                className="bg-slate-800/50 border-slate-600 text-white placeholder:text-slate-400 focus:ring-primary focus:border-transparent"
            />
        </div>

        <div className="space-y-2">
            <div className="flex items-center justify-between">
            <Label htmlFor="password" className="text-slate-300">Password</Label>
            <Link
                href="/forgot-password"
                className="text-sm text-primary/80 hover:text-primary transition-colors"
            >
                Forgot password?
            </Link>
            </div>
            <PasswordInput
                id="password"
                name="password"
                placeholder="••••••••"
                required
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                disabled={loading}
            />
        </div>

        {error && (
            <Alert variant="destructive" className="bg-red-500/10 border-red-500/30 text-red-400">
                <AlertTriangle className="h-4 w-4 flex-shrink-0" />
                <AlertDescription>{error}</AlertDescription>
            </Alert>
        )}

        <div className="pt-2">
             <Button
                type="submit"
                disabled={loading}
                className="w-full h-12 text-base font-semibold bg-primary text-primary-foreground shadow-lg transition-all duration-300 ease-in-out hover:bg-primary/90 hover:shadow-xl disabled:opacity-50 rounded-lg"
            >
                {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Sign In'}
            </Button>
        </div>
    </form>
  );
}
