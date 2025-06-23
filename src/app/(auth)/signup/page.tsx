
'use client';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useToast } from '@/hooks/use-toast';
import { supabase } from '@/lib/db';
import { completeUserRegistration } from '@/app/actions';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState, useEffect } from 'react';
import { CheckCircle } from 'lucide-react';
import { useAuth } from '@/context/auth-context';
import { Skeleton } from '@/components/ui/skeleton';

export default function SignupPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [companyName, setCompanyName] = useState('');
  const [loading, setLoading] = useState(false);
  const [needsConfirmation, setNeedsConfirmation] = useState(false);
  const router = useRouter();
  const { toast } = useToast();
  const { user, loading: authLoading } = useAuth();

  useEffect(() => {
    // If auth is not loading and a user is present, redirect to dashboard.
    // This handles the redirect after a successful signup and session creation.
    if (!authLoading && user) {
      router.push('/dashboard');
    }
  }, [user, authLoading, router]);

  const handleSignup = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      // Step 1: Create the user in Supabase Authentication
      const { data, error } = await supabase.auth.signUp({ email, password });

      if (error) {
        throw error;
      }
      
      // Step 2: Check for a session. A session is ONLY returned when email confirmation is disabled.
      if (data.session) {
        // SUCCESS CASE: User is logged in immediately.
        // The onAuthStateChange listener will eventually pick this up, but we can
        // proceed to create their profile right away.
        const registrationResult = await completeUserRegistration({
          companyName,
          idToken: data.session.access_token,
        });

        if (!registrationResult.success) {
          // If profile creation fails, we should inform the user.
          // The user exists in auth but not in our DB. They may need to contact support.
          throw new Error(registrationResult.error || 'Your account was created, but we failed to set up your company profile. Please contact support.');
        }

        // Now we simply wait for the auth provider to update and the useEffect to redirect.
        // The toast gives the user feedback that something is happening.
        toast({
          title: 'Account Created!',
          description: "You're all set. Redirecting you to the dashboard.",
        });

      } else if (data.user) {
        // PENDING CONFIRMATION CASE: No session, but a user object was returned.
        // This means email confirmation is required in your Supabase project settings.
        setNeedsConfirmation(true);

      } else {
        // UNEXPECTED CASE: No session, no user, no error.
        throw new Error('An unexpected error occurred during signup. Please try again.');
      }

    } catch (error: any) {
      toast({
        variant: 'destructive',
        title: 'Signup Failed',
        description: error.message || 'Could not create your account. Please try again.',
      });
    } finally {
      // We only stop the main loading indicator if we aren't waiting for a redirect or showing the confirmation page.
      if (needsConfirmation) {
        setLoading(false);
      }
    }
  };
  
  if (needsConfirmation) {
      return (
          <Card>
              <CardHeader>
                  <CardTitle className="flex items-center gap-2">
                      <CheckCircle className="h-6 w-6 text-green-500" />
                      One Last Step!
                  </CardTitle>
                  <CardDescription>We've sent a verification link to your email.</CardDescription>
              </CardHeader>
              <CardContent>
                  <p className="text-sm text-muted-foreground">
                      Please check your inbox at <span className="font-semibold text-foreground">{email}</span> and click the link to activate your account. You can close this page.
                  </p>
              </CardContent>
              <CardFooter>
                  <Button variant="outline" className="w-full" asChild>
                      <Link href="/login">Back to Login</Link>
                  </Button>
              </CardFooter>
          </Card>
      )
  }

  // While checking auth status or if user exists (and we're about to redirect), show a loader.
  if (authLoading || user) {
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
             <div className="space-y-2">
                <Skeleton className="h-4 w-16" />
                <Skeleton className="h-10 w-full" />
            </div>
        </CardContent>
        <CardFooter className="flex flex-col gap-4">
            <Skeleton className="h-10 w-full" />
            <Skeleton className="h-4 w-1/2" />
        </CardFooter>
    </Card>
    );
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Create an Account</CardTitle>
        <CardDescription>Get started with InvoChat for your business.</CardDescription>
      </CardHeader>
      <form onSubmit={handleSignup}>
        <CardContent className="space-y-4">
          <div className="space-y-2">
            <Label htmlFor="companyName">Company Name</Label>
            <Input id="companyName" type="text" placeholder="Your Company, Inc." value={companyName} onChange={(e) => setCompanyName(e.target.value)} required />
          </div>
          <div className="space-y-2">
            <Label htmlFor="email">Email</Label>
            <Input id="email" type="email" placeholder="you@company.com" value={email} onChange={(e) => setEmail(e.target.value)} required />
          </div>
          <div className="space-y-2">
            <Label htmlFor="password">Password</Label>
            <Input id="password" type="password" placeholder="••••••••" value={password} onChange={(e) => setPassword(e.target.value)} required />
          </div>
        </CardContent>
        <CardFooter className="flex flex-col gap-4">
          <Button type="submit" className="w-full" disabled={loading}>
            {loading ? 'Creating Account...' : 'Sign Up'}
          </Button>
          <p className="text-center text-sm text-muted-foreground">
            Already have an account?{' '}
            <Link href="/login" className="font-medium text-primary hover:underline">
              Log in
            </Link>
          </p>
        </CardFooter>
      </form>
    </Card>
  );
}
