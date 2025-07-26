
import { LoginForm } from '@/components/auth/LoginForm';
import { InvoChatLogo } from '@/components/invochat-logo';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import Link from 'next/link';
import { generateCSRFToken } from '@/lib/csrf';

export default async function LoginPage({
  searchParams,
}: {
  searchParams?: { [key: string]: string | string[] | undefined };
}) {
  const error = typeof searchParams?.error === 'string' ? searchParams.error : null;
  const message = typeof searchParams?.message === 'string' ? searchParams.message : null;
  
  // Generate token on the server and pass it to the client component.
  const csrfToken = await generateCSRFToken();
    
  return (
     <div className="relative w-full max-w-md overflow-hidden rounded-2xl border bg-card/80 p-4 shadow-2xl backdrop-blur-lg">
      <div className="absolute inset-0 -z-10 bg-gradient-to-br from-background via-primary/10 to-background" />
      <Card className="w-full border-none bg-transparent p-8 space-y-6">
        <CardHeader className="p-0 text-center">
          <Link href="/" className="mb-4 flex items-center justify-center gap-3">
            <InvoChatLogo className="h-10 w-10 text-primary" />
            <h1 className="bg-gradient-to-r from-primary to-purple-400 bg-clip-text text-4xl font-bold tracking-tight text-transparent">ARVO</h1>
          </Link>
          <CardTitle className="text-2xl">Welcome Back</CardTitle>
          <CardDescription>
            Sign in to access your inventory dashboard.
          </CardDescription>
        </CardHeader>
        <CardContent className="p-0">
            {message && <p className="text-center text-sm text-success mb-4">{message}</p>}
            <LoginForm initialError={error} csrfToken={csrfToken} />
            <div className="mt-4 text-center text-sm text-muted-foreground">
              Don&apos;t have an account?{' '}
              <Link href="/signup" className="underline hover:text-primary">
                Sign up
              </Link>
            </div>
        </CardContent>
      </Card>
     </div>
  );
}

    