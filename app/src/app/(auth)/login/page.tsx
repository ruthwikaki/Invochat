
'use client';

import Link from 'next/link';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { InvoChatLogo } from '@/components/invochat-logo';
import { LoginForm } from '@/components/auth/LoginForm';
import { useToast } from '@/hooks/use-toast';
import { useEffect } from 'react';
import { useSearchParams } from 'next/navigation';

export default function LoginPage() {
  const searchParams = useSearchParams();
  const error = searchParams.get('error');
  const message = searchParams.get('message');
  const { toast } = useToast();

  useEffect(() => {
    if (message) {
      toast({ title: 'Success', description: message });
      const url = new URL(window.location.href);
      url.searchParams.delete('message');
      window.history.replaceState({}, '', url.toString());
    }
  }, [message, toast]);

  return (
    <div className="relative w-full max-w-md overflow-hidden bg-slate-900 text-white p-4 rounded-2xl shadow-2xl border border-slate-700/50">
      <div className="absolute inset-0 -z-10">
        <div className="absolute inset-0 bg-gradient-to-br from-slate-900 via-primary/10 to-slate-900" />
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_80%_at_50%_-20%,rgba(79,70,229,0.3),rgba(255,255,255,0))]" />
      </div>
      <Card className="w-full bg-transparent border-none p-8 space-y-6">
        <CardHeader className="p-0 text-center">
            <Link href="/" className="flex justify-center items-center gap-3 mb-4">
              <InvoChatLogo className="h-10 w-10 text-primary" />
              <h1 className="text-4xl font-bold tracking-tight bg-gradient-to-r from-primary to-violet-400 bg-clip-text text-transparent">ARVO</h1>
            </Link>
          <CardTitle className="text-2xl text-slate-200">Welcome Back</CardTitle>
          <CardDescription className="text-slate-400">
            Sign in to access your inventory dashboard.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <LoginForm initialError={error} />
          <div className="mt-6 text-center text-sm">
            <span className="text-slate-400">Don't have an account? </span>
            <Link href="/signup" className="font-medium text-primary hover:underline">
              Sign up
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
