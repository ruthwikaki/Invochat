'use client';

import { useState } from 'react';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/context/auth-context';
import { useToast } from '@/hooks/use-toast';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Loader2 } from 'lucide-react';
import { getErrorMessage } from '@/lib/error-handler';
import { InvoChatLogo } from '@/components/invochat-logo';


export default function SignupPage() {
  const { supabase } = useAuth();
  const router = useRouter();
  const { toast } = useToast();
  const [loading, setLoading] = useState(false);

  const handleSignup = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setLoading(true);
    const formData = new FormData(event.currentTarget);
    const email = formData.get('email') as string;
    const password = formData.get('password') as string;
    const confirmPassword = formData.get('confirmPassword') as string;

    if (password !== confirmPassword) {
        toast({ variant: 'destructive', title: 'Error', description: 'Passwords do not match.' });
        setLoading(false);
        return;
    }

    const { error } = await supabase.auth.signUp({
      email,
      password,
    });

    if (error) {
      toast({
        variant: 'destructive',
        title: 'Signup Failed',
        description: getErrorMessage(error),
      });
    } else {
      toast({
        title: 'Success!',
        description: 'Please check your email for a verification link.',
      });
      router.push('/login');
    }
    setLoading(false);
  };

  return (
    <div className="flex items-center justify-center min-h-screen">
        <Card className="w-full max-w-md">
            <CardHeader className="text-center">
                 <Link href="/" className="flex items-center justify-center gap-2 mb-4">
                    <InvoChatLogo className="h-10 w-10 text-primary" />
                    <span className="text-2xl font-semibold">ARVO</span>
                </Link>
                <CardTitle className="text-2xl">Create Account</CardTitle>
                <CardDescription>Sign up to get started with ARVO</CardDescription>
            </CardHeader>
            <form onSubmit={handleSignup}>
                <CardContent className="space-y-4">
                    <div className="space-y-2">
                        <Label htmlFor="email">Email</Label>
                        <Input 
                        id="email"
                        name="email"
                        type="email" 
                        placeholder="you@company.com" 
                        required 
                        disabled={loading}
                        />
                    </div>
                    <div className="space-y-2">
                        <Label htmlFor="password">Password</Label>
                        <Input 
                        id="password"
                        name="password"
                        type="password" 
                        placeholder="Enter your password"
                        required 
                        disabled={loading}
                        />
                    </div>
                    <div className="space-y-2">
                        <Label htmlFor="confirmPassword">Confirm Password</Label>
                        <Input 
                        id="confirmPassword"
                        name="confirmPassword"
                        type="password" 
                        placeholder="Confirm your password"
                        required 
                        disabled={loading}
                        />
                    </div>
                </CardContent>
                <CardFooter className="flex flex-col gap-4">
                    <Button type="submit" className="w-full" disabled={loading}>
                        {loading && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                        Create Account
                    </Button>
                    <p className="text-center text-sm text-muted-foreground">
                        Already have an account?{' '}
                        <Link href="/login" className="font-medium text-primary hover:underline">
                        Sign in
                        </Link>
                    </p>
                </CardFooter>
            </form>
        </Card>
    </div>
  );
}
