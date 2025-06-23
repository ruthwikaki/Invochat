
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

export default function SignupPage() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { signUpWithEmail } = useAuth();
  const router = useRouter();


  const handleSignUp = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setLoading(true);
    setError(null);
    
    const formData = new FormData(event.currentTarget);
    
    try {
      const result = await signUpWithEmail(formData);
      if (result.success) {
        router.push('/dashboard');
      } else {
        setError(result.error || 'An unexpected error occurred.');
      }
    } catch (err: any) {
      console.error(err);
      setError(err.message || 'An unexpected client-side error occurred.');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-[#F0F2F5] p-4">
      <div className="mb-8 flex items-center gap-3 text-3xl font-bold text-slate-800">
        <DatawiseLogo className="h-10 w-10" />
        <h1>InvoChat</h1>
      </div>
      <Card className="w-full max-w-sm">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">Create an Account</CardTitle>
          <CardDescription>Get started with your smart inventory assistant.</CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSignUp} className="space-y-4">
            {error && (
              <p className="rounded-md bg-destructive/10 p-3 text-center text-sm text-destructive">
                {error}
              </p>
            )}
            <div className="space-y-1">
              <Label htmlFor="companyName">Company Name</Label>
              <Input
                id="companyName"
                name="companyName"
                type="text"
                placeholder="Your Company Inc."
                required
                minLength={2}
                disabled={loading}
              />
            </div>
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
                minLength={6}
                disabled={loading}
              />
            </div>
            <Button type="submit" disabled={loading} className="w-full bg-[#3F51B5] hover:bg-[#3F51B5]/90">
              {loading ? 'Creating Account...' : 'Create Account'}
            </Button>
          </form>
           <div className="mt-4 text-center text-sm">
            Already have an account?{' '}
            <Link href="/login" className="underline text-primary">
              Sign in
            </Link>
          </div>
        </CardContent>
      </Card>
      <p className="mt-6 text-sm text-slate-500">
        Your intelligent inventory copilot.
      </p>
    </div>
  );
}
