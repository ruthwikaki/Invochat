
import { SignupForm } from '@/components/auth/SignupForm';
import { InvoChatLogo } from '@/components/invochat-logo';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import Link from 'next/link';

export default function SignupPage({
  searchParams,
}: {
  searchParams?: { [key: string]: string | string[] | undefined };
}) {
  const error = typeof searchParams?.error === 'string' ? searchParams.error : null;

  return (
    <div className="relative w-full max-w-md overflow-hidden rounded-2xl border border-border/50 bg-slate-900/80 p-4 text-white shadow-2xl backdrop-blur-lg">
      <div className="absolute inset-0 -z-10 bg-gradient-to-br from-slate-900 via-primary/10 to-slate-900" />
      <Card className="w-full border-none bg-transparent p-8 space-y-6">
        <CardHeader className="p-0 text-center">
          <Link href="/" className="mb-4 flex items-center justify-center gap-3">
            <InvoChatLogo className="h-10 w-10 text-primary" />
            <h1 className="bg-gradient-to-r from-primary to-violet-400 bg-clip-text text-4xl font-bold tracking-tight text-transparent">ARVO</h1>
          </Link>
          <CardTitle className="text-2xl text-slate-200">Create an Account</CardTitle>
          <CardDescription className="text-slate-400">
            Get started with AI-powered inventory management.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
          <SignupForm error={error} />
          <div className="mt-4 text-center text-sm text-slate-400">
            Already have an account?{' '}
            <Link href="/login" className="underline hover:text-primary">
              Sign in
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
