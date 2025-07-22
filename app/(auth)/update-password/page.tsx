import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { InvoChatLogo } from '@/components/invochat-logo';
import { UpdatePasswordForm } from '@/components/auth/UpdatePasswordForm';
import Link from 'next/link';

export default function UpdatePasswordPage({
  searchParams,
}: {
  searchParams?: { [key: string]: string | string[] | undefined };
}) {
  const error = typeof searchParams?.error === 'string' ? searchParams.error : null;
    
  return (
    <div className="flex items-center justify-center min-h-screen bg-background">
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
            <CardTitle className="text-2xl text-slate-200">Create a New Password</CardTitle>
            <CardDescription className="text-slate-400">
              Enter a new password for your account below.
            </CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            <UpdatePasswordForm 
              error={error}
            />
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
