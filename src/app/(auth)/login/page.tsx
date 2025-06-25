
'use client';

import { useFormStatus } from 'react-dom';
import React, { useState } from 'react';
import Link from 'next/link';
import Image from 'next/image';
import { Eye, EyeOff, AlertTriangle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Alert, AlertDescription, AlertTitle } from '@/components/ui/alert';
import { Checkbox } from '@/components/ui/checkbox';
import { InvochatLogo } from '@/components/invochat-logo';
import { login } from '@/app/(auth)/actions';

function SubmitButton() {
  const { pending } = useFormStatus();

  return (
    <Button 
      type="submit" 
      disabled={pending} 
      className="w-full"
    >
      {pending ? 'Signing in...' : 'Sign In'}
    </Button>
  );
}

const PasswordInput = ({ id, name, required }: { id: string, name: string, required?: boolean }) => {
  const [showPassword, setShowPassword] = useState(false);
  return (
    <div className="relative">
      <Input
        id={id}
        name={name}
        type={showPassword ? 'text' : 'password'}
        placeholder="••••••••"
        required={required}
        className="pr-10"
        autoComplete="current-password"
      />
      <Button
        type="button"
        variant="ghost"
        size="icon"
        className="absolute right-1 top-1/2 h-7 w-7 -translate-y-1/2 text-muted-foreground hover:bg-transparent"
        onClick={() => setShowPassword(prev => !prev)}
        aria-label={showPassword ? 'Hide password' : 'Show password'}
        tabIndex={-1}
      >
        {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
      </Button>
    </div>
  );
};

export default function LoginPage({ searchParams }: { searchParams?: { error?: string } }) {
  return (
    <main className="grid min-h-dvh w-full lg:grid-cols-2">
      <div className="flex items-center justify-center p-6 sm:p-8">
        <div className="w-full max-w-md">
            <div className="mb-8 flex flex-col items-center text-center">
                <Link href="/" className="mb-4 flex items-center gap-3 text-2xl font-bold">
                    <InvochatLogo className="h-8 w-8" />
                    <h1>InvoChat</h1>
                </Link>
                <p className="text-muted-foreground">Inventory Intelligence Made Simple</p>
            </div>

            <form action={login} className="space-y-4">
              {searchParams?.error && (
                <Alert variant="destructive">
                  <AlertTriangle className="h-4 w-4" />
                  <AlertTitle>Login Failed</AlertTitle>
                  <AlertDescription>{searchParams.error}</AlertDescription>
                </Alert>
              )}
              
              <div className="space-y-2">
                <Label htmlFor="email">Email</Label>
                <Input id="email" name="email" type="email" placeholder="you@company.com" required autoComplete="email"/>
              </div>

              <div className="space-y-2">
                 <div className="flex items-center justify-between">
                    <Label htmlFor="password">Password</Label>
                    <Link href="#" className="text-sm font-medium text-primary hover:underline">
                        Forgot password?
                    </Link>
                 </div>
                <PasswordInput id="password" name="password" required />
              </div>
              
              <div className="flex items-center">
                <Checkbox id="remember-me" name="remember-me" />
                <Label htmlFor="remember-me" className="ml-2 font-normal leading-none">
                  Remember me
                </Label>
              </div>

              <SubmitButton />
            </form>
            
            <div className="mt-6 text-center text-sm text-muted-foreground">
              New to InvoChat?{' '}
              <Link href="/signup" className="font-semibold text-primary hover:underline">
                Sign up
              </Link>
            </div>

             <div className="mt-8 text-center text-xs text-muted-foreground">
                <Link href="#" className="hover:underline">Terms of Service</Link>
                <span className="mx-2">·</span>
                <Link href="#" className="hover:underline">Privacy Policy</Link>
            </div>
        </div>
      </div>
      <div className="relative hidden bg-primary lg:flex">
        <Image
            src="https://placehold.co/1200x900.png"
            alt="Warehouse inventory being managed on a computer"
            data-ai-hint="warehouse inventory"
            fill
            className="object-cover opacity-20"
        />
        <div className="relative z-10 m-auto max-w-lg p-8 text-primary-foreground">
            <blockquote className="space-y-2">
                <p className="text-2xl font-semibold">
                    "InvoChat has been a game-changer. We cut our dead stock by 40% in the first quarter and now have a real-time pulse on our entire operation."
                </p>
                <footer className="text-lg">— Sarah Johnson, Warehouse Manager</footer>
            </blockquote>
        </div>
      </div>
    </main>
  );
}
