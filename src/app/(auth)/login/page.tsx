
'use client';

import { useFormStatus } from 'react-dom';
import React, { useState } from 'react';
import Link from 'next/link';
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
      className="w-full bg-[#7C3AED] hover:bg-[#6B46C1]"
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
        className="pr-10 focus:border-[#7C3AED]"
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
    <main className="relative flex min-h-dvh w-full items-center justify-center p-4">
       <div
          className="absolute inset-0 bg-cover bg-center"
          style={{ backgroundImage: "url('https://placehold.co/1920x1080.png')" }}
          data-ai-hint="warehouse logistics"
       />
       <div className="absolute inset-0 bg-background/80 backdrop-blur-sm" />
      <div className="relative z-10 w-full max-w-sm rounded-xl border bg-card/70 p-6 shadow-2xl backdrop-blur-lg sm:p-8">
          <div className="mb-8 flex flex-col items-center text-center">
              <Link href="/" className="mb-4 flex items-center gap-3 text-2xl font-bold">
                  <InvochatLogo className="h-8 w-8" />
                  <h1 className="text-foreground">InvoChat</h1>
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
              <Label htmlFor="email" className="text-card-foreground">Email</Label>
              <Input id="email" name="email" type="email" placeholder="you@company.com" required autoComplete="email" className="focus:border-[#7C3AED]"/>
            </div>

            <div className="space-y-2">
               <div className="flex items-center justify-between">
                  <Label htmlFor="password" className="text-card-foreground">Password</Label>
                  <Link href="#" className="text-sm font-medium text-primary hover:underline">
                      Forgot password?
                  </Link>
               </div>
              <PasswordInput id="password" name="password" required />
            </div>
            
            <div className="flex items-center">
              <Checkbox id="remember-me" name="remember-me" />
              <Label htmlFor="remember-me" className="ml-2 font-normal leading-none text-muted-foreground">
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
    </main>
  );
}
