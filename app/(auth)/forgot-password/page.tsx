import Link from 'next/link';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { InvoChatLogo } from '@/components/invochat-logo';
import { CheckCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { ForgotPasswordForm } from '@/components/auth/ForgotPasswordForm';

export default function ForgotPasswordPage({
  searchParams,
}: {
  searchParams?: { [key: string]: string | string[] | undefined };
}) {
  const error = typeof searchParams?.error === 'string' ? searchParams.error : null;
  const success = searchParams?.success === 'true';
  
  return (
    <div className="flex items-center justify-center min-h-screen bg-background">
      {success ? (
        <div className="w-full max-w-sm mx-auto">
          <Card className="text-center">
            <CardHeader>
                <div className="mx-auto bg-success/10 p-3 rounded-full w-fit">
                    <CheckCircle className="h-8 w-8 text-success" />
                </div>
                <CardTitle className="mt-4">Check Your Email</CardTitle>
                <CardDescription>
                    If an account with that email exists, we've sent a link to reset your password.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <Button asChild className="w-full">
                    <Link href="/login">Back to Sign In</Link>
                </Button>
            </CardContent>
          </Card>
        </div>
      ) : (
        <div className="relative w-full max-w-md overflow-hidden bg-slate-900 text-white p-4 rounded-2xl shadow-2xl border border-slate-700/50">
            <div className="absolute inset-0 -z-10">
                <div className="absolute inset-0 bg-gradient-to-br from-slate-900 via-primary/10 to-slate-900" />
                <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_80%_at_50%_-20%,rgba(79,70,229,0.3),rgba(255,255,255,0))]" />
            </div>
          <Card className="w-full bg-transparent border-none p-8 space-y-6">
            <CardHeader className="p-0 text-center">
              <Link href="/" className="flex justify-center items-center gap-3 mb-4">
                  <InvoChatLogo className="h-10 w-10 text-primary" />
                  <h1 className="text-4xl font-bold tracking-tight bg-gradient-to-r from-primary to-violet-400 bg-clip-text text-transparent">InvoChat</h1>
              </Link>
              <CardTitle className="text-2xl text-slate-200">Forgot Password</CardTitle>
              <CardDescription className="text-slate-400">
                Enter your email and we'll send you a link to reset your password.
              </CardDescription>
            </CardHeader>
            <CardContent className="p-0">
              <ForgotPasswordForm error={error} />
              <div className="mt-4 text-center text-sm text-slate-400">
                Remembered your password?{' '}
                <Link href="/login" className="underline text-primary/90 hover:text-primary">
                  Sign in
                </Link>
              </div>
            </CardContent>
          </Card>
        </div>
      )}
    </div>
  );
}
