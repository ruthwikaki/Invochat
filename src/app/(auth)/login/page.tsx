
'use client';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useAuth } from '@/context/auth-context';
import { useToast } from '@/hooks/use-toast';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState, useEffect } from 'react';
import { Skeleton } from '@/components/ui/skeleton';

export default function LoginPage() {
  const [email, setEmail] = useState('demo@example.com');
  const [password, setPassword] = useState('password');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const { login, user, userProfile, loading: authLoading } = useAuth();
  const router = useRouter();
  const { toast } = useToast();

  useEffect(() => {
    // This effect handles the case where a user is already logged in
    // and visits the login page. It will redirect them to the dashboard.
    if (!authLoading && user && userProfile) {
        router.replace('/dashboard');
    }
  }, [user, userProfile, authLoading, router]);

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);
    try {
      await login(email, password);
      
      toast({
        title: 'Login Successful',
        description: 'Redirecting to your dashboard...',
      });

      router.push('/dashboard');
      
    } catch (error: any) {
      console.error('Login error details:', error);
      let description = 'An unknown error occurred. Please try again.';
      if (error.code) {
        switch (error.code) {
            case 'auth/user-not-found':
            case 'auth/wrong-password':
            case 'auth/invalid-credential':
                description = "Invalid email or password. Please try again.";
                break;
            case 'auth/invalid-email':
                description = "The email address you entered is not valid.";
                break;
            case 'auth/too-many-requests':
                description = "Access to this account has been temporarily disabled due to many failed login attempts. You can immediately restore it by resetting your password or you can try again later.";
                break;
            default:
                description = `An unexpected error occurred: ${error.message}`;
        }
      }
      toast({
        variant: 'destructive',
        title: 'Login Failed',
        description: description,
      });
    } finally {
        setIsSubmitting(false);
    }
  };

  // Show a skeleton while the auth state is being checked, or if the user
  // is already logged in and being redirected.
  if (authLoading || (user && userProfile)) {
    return (
        <Card>
            <CardHeader>
                <Skeleton className="h-7 w-3/5" />
                <Skeleton className="h-4 w-4/5" />
            </CardHeader>
            <CardContent className="space-y-4">
                <div className="space-y-2">
                    <Skeleton className="h-4 w-16" />
                    <Skeleton className="h-10 w-full" />
                </div>
                 <div className="space-y-2">
                    <Skeleton className="h-4 w-16" />
                    <Skeleton className="h-10 w-full" />
                </div>
            </CardContent>
            <CardFooter className="flex-col gap-4">
                <Skeleton className="h-10 w-full" />
                <Skeleton className="h-4 w-full" />
            </CardFooter>
        </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Welcome Back</CardTitle>
        <CardDescription>Enter your credentials to access your account.</CardDescription>
      </CardHeader>
      <form onSubmit={handleLogin}>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <Input id="email" type="email" placeholder="you@company.com" value={email} onChange={(e) => setEmail(e.target.value)} required />
          </div>
          <div className="space-y-2">
            <Label htmlFor="password">Password</Label>
            <Input id="password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
          </div>
        </CardContent>
        <CardFooter className="flex flex-col gap-4">
          <Button type="submit" className="w-full" disabled={isSubmitting}>
            {isSubmitting ? 'Logging in...' : 'Log In'}
          </Button>
          <div className="text-center text-sm text-muted-foreground w-full flex justify-between">
            <Link href="/signup" className="font-medium text-primary hover:underline">
              Sign up
            </Link>
             <Link href="/reset-password" className="font-medium text-primary hover:underline">
              Forgot password?
            </Link>
          </div>
        </CardFooter>
      </form>
    </Card>
  );
}
