
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
import { useState } from 'react';
import { CheckCircle } from 'lucide-react';

export default function SignupPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [companyName, setCompanyName] = useState('');
  const [loading, setLoading] = useState(false);
  const [needsConfirmation, setNeedsConfirmation] = useState(false);
  const router = useRouter();
  const { toast } = useToast();

  const handleSignup = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);

    try {
      // Step 1: Create the user in Supabase Authentication
      const { data, error } = await supabase.auth.signUp({ email, password });

      if (error) {
          throw error;
      }
      
      if (!data.user) {
          throw new Error("User not created. Please try again.");
      }

      // Step 2: Handle based on whether email confirmation is required.
      // If data.session is null, the user needs to confirm their email.
      if (!data.session) {
        setNeedsConfirmation(true);
        setLoading(false); // Stop loading indicator
        return;
      }
      
      // Step 3: Call a secure RPC to create the company and user records in our DB.
      // We pass the new user's access token to the server action.
      const registrationResult = await completeUserRegistration({
          companyName,
          idToken: data.session.access_token,
      });

      if (!registrationResult.success) {
          // This is a partial failure. The user exists in Supabase Auth but not in our DB.
          // A production app would need a cleanup process. For now, we'll just show the error.
          throw new Error(registrationResult.error || 'Failed to create your company profile.');
      }

      // If we have a session, confirmation is off or already done.
      toast({
        title: 'Account Created!',
        description: "You're all set. Redirecting you to the dashboard.",
      });
      router.push('/dashboard');

    } catch (error: any) {
      toast({
        variant: 'destructive',
        title: 'Signup Failed',
        description: error.message || 'Could not create your account. Please try again.',
      });
      setLoading(false);
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
