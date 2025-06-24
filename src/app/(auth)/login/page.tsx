'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useAuth } from '@/context/auth-context';
import { useRouter } from 'next/navigation';
import { DatawiseLogo } from '@/components/datawise-logo';
import Link from 'next/link';

export default function LoginPage() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { signInWithEmail } = useAuth();
  const router = useRouter();

  const handleSignIn = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setLoading(true);
    setError(null);
    
    const formData = new FormData(event.currentTarget);
    const email = (formData.get('email') as string).trim();
    const password = (formData.get('password') as string).trim();

    if (!email || !password) {
        setError('Email and password are required.');
        setLoading(false);
        return;
    }

    try {
      await signInWithEmail(email, password);
      // Instead of pushing, we refresh the page.
      // The middleware will see the authenticated user
      // on an auth route and redirect them to the dashboard.
      // This is more robust than a client-side redirect and avoids race conditions.
      router.refresh();
    } catch (err: any) {
      console.error('Client-side sign-in error:', err);
      if (err.message.includes('Invalid login credentials')) {
        setError('Incorrect email or password. Please try again.');
      } else {
        setError(err.message || 'An unexpected error occurred. Please try again.');
      }
    } finally {
      // This was the cause of the button getting stuck.
      // We ensure loading is always set to false after the sign-in attempt.
      setLoading(false);
    }
  };

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-4">
      <div className="mb-8 flex items-center gap-3 text-3xl font-bold text-foreground">
        <DatawiseLogo className="h-10 w-10" />
        <h1>ARVO</h1>
      </div>
      <Card className="w-full max-w-sm">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">Welcome Back</CardTitle>
          <CardDescription>Sign in to access your inventory assistant.</CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSignIn} className="space-y-4">
            {error && (
              <p className="rounded-md bg-destructive/10 p-3 text-center text-sm text-destructive">
                {error}
              </p>
            )}
            <div className="space-y-1">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                name="email"
                type="email"
                placeholder="m@example.com"
                required
                disabled={loading}
              />
            </div>
            <div className="space-y-1">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                name="password"
                type="password"
                required
                disabled={loading}
              />
            </div>
            <Button type="submit" disabled={loading} className="w-full bg-primary hover:bg-primary/90">
              {loading ? 'Signing in...' : 'Sign In'}
            </Button>
          </form>
           <div className="mt-4 text-center text-sm">
            Don&apos;t have an account?{' '}
            <Link href="/signup" className="underline text-primary">
              Sign up
            </Link>
          </div>
        </CardContent>
      </Card>
      <p className="mt-6 text-sm text-muted-foreground">
        Your intelligent inventory copilot.
      </p>
    </div>
  );
}
