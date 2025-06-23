
'use client';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useToast } from '@/hooks/use-toast';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState, useEffect } from 'react';
import { useAuth } from '@/context/auth-context';
import { Skeleton } from '@/components/ui/skeleton';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { setupCompanyAndUserProfile } from '@/app/actions';
import { Separator } from '@/components/ui/separator';

type CompanyChoice = 'create' | 'join';

export default function SignupPage() {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [companyChoice, setCompanyChoice] = useState<CompanyChoice>('create');
  const [companyName, setCompanyName] = useState('');
  const [inviteCode, setInviteCode] = useState('');
  
  const [isSubmitting, setIsSubmitting] = useState(false);
  const router = useRouter();
  const { toast } = useToast();
  const { signup, user, userProfile, loading: authLoading, getIdToken } = useAuth();

  useEffect(() => {
    // This effect handles redirection if user is already logged in.
    if (!authLoading && user && userProfile) {
        router.push('/dashboard');
    }
  }, [user, userProfile, authLoading, router]);

  const handleSignup = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsSubmitting(true);
    
    const companyNameOrCode = companyChoice === 'create' ? companyName : inviteCode;
    if (!companyNameOrCode) {
        toast({ variant: 'destructive', title: 'Missing Information', description: 'Please provide a company name or invite code.' });
        setIsSubmitting(false);
        return;
    }

    try {
      // Step 1: Create Firebase user
      const userCredential = await signup(email, password);
      
      // onAuthStateChanged will fire, but we need the token from the *new* user to set up the profile.
      if (!userCredential.user) {
        throw new Error("User creation failed, please try again.");
      }
      const idToken = await userCredential.user.getIdToken();

      // Step 2: Set up company and user profile in Supabase
      const result = await setupCompanyAndUserProfile({
        idToken,
        companyChoice,
        companyNameOrCode,
      });

      if (result.success && result.profile) {
        toast({ title: 'Account Created!', description: `Welcome to ${result.profile.company?.name}!`});
        // The AuthContext's onAuthStateChanged listener will handle fetching the new profile
        // and the layout will handle the redirect.
      } else {
        throw new Error(result.error || 'An unknown error occurred during setup.');
      }

    } catch (error: any) {
      console.error("Signup Error:", error);
      let description = "Could not create your account. Please try again.";
      if(error.code) { // Handle Firebase Auth errors
          switch(error.code) {
              case 'auth/email-already-in-use':
                  description = 'This email is already in use. Please try logging in instead.';
                  break;
              case 'auth/weak-password':
                  description = 'Your password is too weak. Please use at least 6 characters.';
                  break;
              case 'auth/invalid-email':
                  description = 'The email address is not valid.';
                  break;
              default:
                  description = error.message;
          }
      } else if (error.message) { // Handle custom errors from server actions
        description = error.message;
      }
      toast({
        variant: 'destructive',
        title: 'Signup Failed',
        description: description,
      });
    } finally {
      setIsSubmitting(false);
    }
  };
  
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
            <Label htmlFor="email">Email</Label>
            <Input id="email" type="email" placeholder="you@company.com" value={email} onChange={(e) => setEmail(e.target.value)} required />
          </div>
          <div className="space-y-2">
            <Label htmlFor="password">Password</Label>
            <Input id="password" type="password" placeholder="•••••••• (min. 6 characters)" value={password} onChange={(e) => setPassword(e.target.value)} required />
          </div>

          <Separator className="my-4" />

          <div>
            <RadioGroup
                defaultValue="create"
                className="grid grid-cols-2 gap-4"
                onValueChange={(value: CompanyChoice) => setCompanyChoice(value)}
            >
                <div>
                    <RadioGroupItem value="create" id="create" className="peer sr-only" />
                    <Label htmlFor="create" className="flex flex-col items-center justify-between rounded-md border-2 border-muted bg-popover p-4 hover:bg-accent hover:text-accent-foreground peer-data-[state=checked]:border-primary [&:has([data-state=checked])]:border-primary">
                        Create Company
                    </Label>
                </div>
                 <div>
                    <RadioGroupItem value="join" id="join" className="peer sr-only" />
                    <Label htmlFor="join" className="flex flex-col items-center justify-between rounded-md border-2 border-muted bg-popover p-4 hover:bg-accent hover:text-accent-foreground peer-data-[state=checked]:border-primary [&:has([data-state=checked])]:border-primary">
                        Join Company
                    </Label>
                </div>
            </RadioGroup>
          </div>

          {companyChoice === 'create' ? (
              <div className="space-y-2">
                  <Label htmlFor="companyName">Company Name</Label>
                  <Input 
                      id="companyName" 
                      placeholder="Your Company, Inc."
                      value={companyName}
                      onChange={(e) => setCompanyName(e.target.value)}
                      required
                  />
              </div>
          ) : (
              <div className="space-y-2">
                  <Label htmlFor="inviteCode">Invite Code</Label>
                  <Input
                      id="inviteCode"
                      placeholder="Enter 6-digit code"
                      value={inviteCode}
                      onChange={(e) => setInviteCode(e.target.value.toUpperCase())}
                      required
                  />
              </div>
          )}

        </CardContent>
        <CardFooter className="flex flex-col gap-4">
          <Button type="submit" className="w-full" disabled={isSubmitting}>
            {isSubmitting ? 'Creating Account...' : 'Sign Up & Continue'}
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
