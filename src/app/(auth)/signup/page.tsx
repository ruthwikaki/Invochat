
'use client';

import { useFormStatus } from 'react-dom';
import { Card, CardContent, CardDescription, CardFooter, CardHeader, CardTitle } from '@/components/ui/card';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { useAuth } from '@/context/auth-context';
import { useToast } from '@/hooks/use-toast';
import Link from 'next/link';
import { useRouter } from 'next/navigation';
import { useState, useEffect } from 'react';
import { signup as signupAction } from '@/app/(auth)/actions';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { AlertTriangle, Loader2 } from 'lucide-react';
import { PasswordInput } from '@/components/auth/PasswordInput';
import { CSRF_FORM_NAME, getCookie, CSRF_COOKIE_NAME } from '@/lib/csrf-client';

function SubmitButton({ disabled }: { disabled?: boolean }) {
    const { pending } = useFormStatus();
    return (
      <Button type="submit" className="w-full h-12 text-base" disabled={disabled || pending}>
        {pending ? <Loader2 className="animate-spin" /> : 'Create Account'}
      </Button>
    );
}

export default function SignupPage({ searchParams }: { searchParams?: { error?: string }}) {
    const [error, setError] = useState(searchParams?.error);
    const [csrfToken, setCsrfToken] = useState<string | null>(null);

    useEffect(() => {
        setCsrfToken(getCookie(CSRF_COOKIE_NAME));
    }, []);
    
    useEffect(() => {
        setError(searchParams?.error);
        if (searchParams?.error) {
            const url = new URL(window.location.href);
            url.searchParams.delete('error');
            window.history.replaceState({}, '', url.toString());
        }
    }, [searchParams?.error]);

    const handleInteraction = () => {
        if (error) setError(undefined);
    };

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
                    <CardTitle className="text-2xl text-slate-200">Create Your Account</CardTitle>
                    <CardDescription className="text-slate-400">
                        Get started with AI-powered inventory intelligence.
                    </CardDescription>
                </CardHeader>
                <CardContent className="p-0">
                     <form action={signupAction} className="grid gap-4" onChange={handleInteraction}>
                        {csrfToken && <input type="hidden" name={CSRF_FORM_NAME} value={csrfToken} />}
                        <div className="grid gap-2">
                            <Label htmlFor="companyName" className="text-slate-300">Company Name</Label>
                            <Input
                                id="companyName"
                                name="companyName"
                                type="text"
                                placeholder="Your Company Inc."
                                required
                                className="bg-slate-800/50 border-slate-600 text-white placeholder:text-slate-400 focus:ring-primary focus:border-transparent"
                            />
                        </div>
                        <div className="grid gap-2">
                            <Label htmlFor="email" className="text-slate-300">Email</Label>
                            <Input
                                id="email"
                                name="email"
                                type="email"
                                placeholder="you@company.com"
                                required
                                className="bg-slate-800/50 border-slate-600 text-white placeholder:text-slate-400 focus:ring-primary focus:border-transparent"
                            />
                        </div>
                        <div className="grid gap-2">
                            <Label htmlFor="password" className="text-slate-300">Password</Label>
                            <PasswordInput
                                id="password"
                                name="password"
                                placeholder="••••••••"
                                required
                                minLength={8}
                            />
                            <p className="text-xs text-slate-400 px-1">
                                Must be at least 8 characters.
                            </p>
                        </div>
                        <div className="grid gap-2">
                            <Label htmlFor="confirmPassword" className="text-slate-300">Confirm Password</Label>
                            <PasswordInput
                                id="confirmPassword"
                                name="confirmPassword"
                                placeholder="••••••••"
                                required
                                minLength={8}
                            />
                        </div>
                        {error && (
                        <Alert variant="destructive" className="bg-red-500/10 border-red-500/30 text-red-400">
                            <AlertTriangle className="h-4 w-4" />
                            <AlertDescription>{error}</AlertDescription>
                        </Alert>
                        )}
                        <SubmitButton disabled={!csrfToken} />
                    </form>
                    <div className="mt-4 text-center text-sm text-slate-400">
                        Already have an account?{' '}
                        <Link href="/login" className="underline text-primary/90 hover:text-primary">
                        Sign in
                        </Link>
                    </div>
                </CardContent>
            </Card>
        </div>
    );
}
