
import Link from 'next/link';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { InvoChatLogo } from '@/components/invochat-logo';
import { LoginForm } from '@/components/auth/LoginForm';
import { Alert, AlertDescription } from '@/components/ui/alert';
import { generateCSRFToken } from '@/lib/csrf';

export default function LoginPage({
  searchParams,
}: {
  searchParams?: { [key: string]: string | string[] | undefined };
}) {
  const error = typeof searchParams?.error === 'string' ? searchParams.error : null;
  const message = typeof searchParams?.message === 'string' ? searchParams.message : null;
  const csrfToken = generateCSRFToken();

  return (
    <div className="relative flex items-center justify-center min-h-dvh w-full overflow-hidden bg-slate-900 text-white p-4">
      <div className="absolute inset-0 -z-10">
        <div className="absolute inset-0 bg-gradient-to-br from-slate-900 via-primary/10 to-slate-900" />
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_80%_at_50%_-20%,rgba(79,70,229,0.3),rgba(255,255,255,0))]" />
      </div>

      <Card className="w-full max-w-md p-8 space-y-6 rounded-2xl shadow-2xl bg-slate-800/80 backdrop-blur-xl border border-slate-700/50">
        <CardHeader className="p-0 text-center">
          <div className="flex justify-center items-center gap-3 mb-4">
            <InvoChatLogo className="h-10 w-10 text-primary" />
            <h1 className="text-4xl font-bold tracking-tight bg-gradient-to-r from-primary to-violet-400 bg-clip-text text-transparent">
              ARVO
            </h1>
          </div>
          <CardTitle className="text-xl font-semibold text-slate-200">Welcome to Intelligent Inventory</CardTitle>
          <CardDescription className="text-slate-400 mt-2 text-sm">Sign in to access AI-powered insights.</CardDescription>
        </CardHeader>
        
        <CardContent className="p-0">
          {message && (
              <Alert className="mb-4 bg-blue-500/10 border-blue-500/30 text-blue-300">
                  <AlertDescription>{message}</AlertDescription>
              </Alert>
          )}
          <LoginForm 
            error={error} 
            csrfToken={csrfToken}
          />
          <div className="mt-6 text-center text-sm text-slate-400">
            Don't have an account?{' '}
            <Link href="/signup" className="font-semibold text-primary/90 hover:text-primary transition-colors">
              Sign up
            </Link>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
