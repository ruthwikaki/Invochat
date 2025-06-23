
'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useAuth } from '@/context/auth-context';
import { useRouter } from 'next/navigation';
import { DatawiseLogo } from '@/components/datawise-logo';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import Link from 'next/link';

const signupSchema = z.object({
  companyName: z.string().min(2, { message: 'Company name is required' }),
  email: z.string().email({ message: 'Invalid email address' }),
  password: z.string().min(6, { message: 'Password must be at least 6 characters' }),
});

type SignupFormData = z.infer<typeof signupSchema>;

export default function SignupPage() {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const { signUpWithEmail } = useAuth();
  const router = useRouter();

  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<SignupFormData>({
    resolver: zodResolver(signupSchema),
  });

  const handleSignUp = async (data: SignupFormData) => {
    setLoading(true);
    setError(null);
    try {
      await signUpWithEmail(data.email, data.password, data.companyName);
      router.push('/dashboard');
    } catch (err: any) {
      console.error(err);
      setError(err.message || 'An unexpected error occurred. Please try again.');
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
          <form onSubmit={handleSubmit(handleSignUp)} className="space-y-4">
            {error && (
              <p className="rounded-md bg-destructive/10 p-3 text-center text-sm text-destructive">
                {error}
              </p>
            )}
            <div className="space-y-1">
              <Label htmlFor="companyName">Company Name</Label>
              <Input
                id="companyName"
                type="text"
                placeholder="Your Company Inc."
                {...register('companyName')}
                disabled={loading}
              />
              {errors.companyName && <p className="text-sm text-destructive">{errors.companyName.message}</p>}
            </div>
             <div className="space-y-1">
              <Label htmlFor="email">Email</Label>
              <Input
                id="email"
                type="email"
                placeholder="m@example.com"
                {...register('email')}
                disabled={loading}
              />
              {errors.email && <p className="text-sm text-destructive">{errors.email.message}</p>}
            </div>
            <div className="space-y-1">
              <Label htmlFor="password">Password</Label>
              <Input
                id="password"
                type="password"
                {...register('password')}
                disabled={loading}
              />
              {errors.password && <p className="text-sm text-destructive">{errors.password.message}</p>}
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
