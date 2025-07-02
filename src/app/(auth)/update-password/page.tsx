'use client';

import { useFormStatus } from 'react-dom';
import React, { useState, useEffect } from 'react';
import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { ArvoLogo } from '@/components/arvo-logo';
import { AlertTriangle, Eye, EyeOff, Loader2 } from 'lucide-react';
import { updatePassword } from '@/app/(auth)/actions';
import { CSRF_COOKIE_NAME, CSRF_FORM_NAME } from '@/lib/csrf';


function getCookie(name: string): string | null {
  if (typeof document === 'undefined') return null;
  const value = `; ${document.cookie}`;
  const parts = value.split(`; ${name}=`);
  if (parts.length === 2) return parts.pop()?.split(';').shift() || null;
  return null;
}

const PasswordInput = React.forwardRef<HTMLInputElement, React.ComponentProps<'input'>>(
  (props, ref) => {
    const [showPassword, setShowPassword] = useState(false);
    return (
      <div className="relative">
        <Input
          ref={ref}
          type={showPassword ? 'text' : 'password'}
          className="pr-10 bg-slate-800/50 border-slate-600 text-white placeholder:text-slate-400 focus:ring-blue-500 focus:border-transparent"
          {...props}
        />
        <Button
          type="button"
          variant="ghost"
          size="icon"
          className="absolute right-1 top-1/2 h-7 w-7 -translate-y-1/2 text-slate-400 hover:bg-transparent hover:text-white"
          onClick={() => setShowPassword((prev) => !prev)}
          aria-label={showPassword ? 'Hide password' : 'Show password'}
          tabIndex={-1}
        >
          {showPassword ? (
            <EyeOff className="h-4 w-4" />
          ) : (
            <Eye className="h-4 w-4" />
          )}
        </Button>
      </div>
    );
  }
);
PasswordInput.displayName = 'PasswordInput';


export default function UpdatePasswordPage({ searchParams }: { searchParams?: { error?: string } }) {
    const [error, setError] = useState(searchParams?.error || null);
    const [csrfToken, setCsrfToken] = useState<string | null>(null);

    useEffect(() => {
        setCsrfToken(getCookie(CSRF_COOKIE_NAME));
    }, []);

    const handleSubmit = async (formData: FormData) => {
        if (formData.get('password') !== formData.get('confirmPassword')) {
            setError('Passwords do not match.');
            return;
        }
        setError(null);
        await updatePassword(formData);
    }
    
    const SubmitButton = () => {
        const { pending } = useFormStatus();
        const isDisabled = pending || !csrfToken;
        return (
            <Button type="submit" className="w-full" disabled={isDisabled}>
            {pending ? <Loader2 className="animate-spin" /> : 'Update Password'}
            </Button>
        );
    }

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center bg-slate-900 text-white p-4">
        <div className="absolute inset-0 -z-10">
            <div className="absolute inset-0 bg-gradient-to-br from-slate-900 via-purple-900/20 to-slate-900" />
            <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_80%_at_50%_-20%,rgba(120,119,198,0.3),rgba(255,255,255,0))]" />
            <div className="absolute top-0 left-1/4 w-72 h-72 bg-purple-500 rounded-full mix-blend-multiply filter blur-xl opacity-20 animate-blob" />
            <div className="absolute top-0 right-1/4 w-72 h-72 bg-blue-500 rounded-full mix-blend-multiply filter blur-xl opacity-20 animate-blob animation-delay-2000" />
            <div className="absolute bottom-1/4 left-1/3 w-72 h-72 bg-pink-500 rounded-full mix-blend-multiply filter blur-xl opacity-20 animate-blob animation-delay-4000" />
        </div>
      <div className="mb-8 flex items-center gap-3 text-3xl font-bold text-foreground">
        <ArvoLogo className="h-10 w-10 text-primary" />
        <h1 className="text-4xl font-bold tracking-tight bg-gradient-to-r from-blue-400 to-purple-400 bg-clip-text text-transparent">ARVO</h1>
      </div>
      <Card className="w-full max-w-md p-8 space-y-6 rounded-2xl shadow-2xl bg-slate-800/80 backdrop-blur-xl border border-slate-700/50">
        <CardHeader className="p-0 text-center">
          <CardTitle className="text-2xl text-slate-200">Create a New Password</CardTitle>
          <CardDescription className="text-slate-400">
            Enter a new password for your account below.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <form action={handleSubmit} className="grid gap-4">
            <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken || ''} />
            <div className="grid gap-2">
              <Label htmlFor="password" className="text-slate-300">New Password</Label>
               <PasswordInput
                    id="password"
                    name="password"
                    required
                    placeholder="••••••••"
                    autoComplete="new-password"
               />
            </div>
             <div className="grid gap-2">
              <Label htmlFor="confirmPassword" className="text-slate-300">Confirm New Password</Label>
              <PasswordInput
                id="confirmPassword"
                name="confirmPassword"
                placeholder="••••••••"
                required
              />
            </div>
            {error && (
              <Alert variant="destructive">
                 <AlertTriangle className="h-4 w-4" />
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}
            <SubmitButton />
          </form>
        </CardContent>
      </Card>
    </div>
  );
}
