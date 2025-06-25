
'use client';

import { useState } from 'react';
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
import Link from 'next/link';
import { useAuth } from '@/context/auth-context';
import { InvoChatLogo } from '@/components/invochat-logo';
import { CheckCircle } from 'lucide-react';
import { useRouter } from 'next/navigation';

export default function SignupPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [companyName, setCompanyName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [isSubmitted, setIsSubmitted] = useState(false);
  const { signUpWithEmail } = useAuth();
  const router = useRouter();
  
  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);

    const { data, error: signUpError } = await signUpWithEmail(email, password, companyName);
    
    if (signUpError) {
      setError(signUpError.message);
      setLoading(false);
    } else if (data.session) {
      // User is logged in immediately, refresh the page.
      // The middleware will handle the redirect to the dashboard.
      router.refresh();
    } else if (data.user) {
      // User exists, but no session -> email verification needed
      setIsSubmitted(true);
      setLoading(false);
    } else {
      setError('An unexpected error occurred during sign up.');
      setLoading(false);
    }
  };

  if (isSubmitted) {
    return (
      <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-4">
         <div className="mb-8 flex items-center gap-3 text-3xl font-bold text-foreground">
          <InvoChatLogo className="h-10 w-10" />
          <h1>ARVO</h1>
        </div>
        <Card className="w-full max-w-sm text-center">
            <CardHeader>
                <div className="mx-auto bg-success/10 p-3 rounded-full w-fit">
                    <CheckCircle className="h-8 w-8 text-success" />
                </div>
                <CardTitle className="mt-4">Success!</CardTitle>
                <CardDescription>
                    Please check your email to verify your account.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <Button asChild className="w-full">
                    <Link href="/login">Back to Sign In</Link>
                </Button>
            </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-4">
      <div className="mb-8 flex items-center gap-3 text-3xl font-bold text-foreground">
        <InvoChatLogo className="h-10 w-10" />
        <h1>ARVO</h1>
      </div>
      <Card className="w-full max-w-sm">
        <CardHeader>
          <CardTitle className="text-2xl">Create Account</CardTitle>
          <CardDescription>
            Enter your information to create your ARVO account
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="grid gap-4">
            <div className="grid gap-2">
              <Label htmlFor="company">Company Name</Label>
              <Input
                id="company"
                type="text"
                placeholder="Your Company Inc."
                value={companyName}
                onChange={(e) => setCompanyName(e.target.value)}
                required
                disabled={loading}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                placeholder="you@company.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                disabled={loading}
              />
            </div>
            <div className="grid gap-2">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
                minLength={6}
                disabled={loading}
              />
            </div>
            {error && (
              <Alert variant="destructive">
                <AlertDescription>{error}</AlertDescription>
              </Alert>
            )}
            <Button type="submit" className="w-full" disabled={loading}>
              {loading ? 'Creating account...' : 'Sign up'}
            </Button>
          </form>
          <div className="mt-4 text-center text-sm">
            Already have an account?{' '}
            <Link href="/login" className="underline">
              Sign in
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
