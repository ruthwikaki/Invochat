import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { InvoChatLogo } from '@/components/invochat-logo';
import { UpdatePasswordForm } from '@/components/auth/UpdatePasswordForm';
import { generateCSRFToken } from '@/lib/csrf';

export default function UpdatePasswordPage({
  searchParams,
}: {
  searchParams?: { [key: string]: string | string[] | undefined };
}) {
  const error = typeof searchParams?.error === 'string' ? searchParams.error : null;
  generateCSRFToken();
    
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center bg-slate-900 text-white p-4">
        <div className="absolute inset-0 -z-10">
            <div className="absolute inset-0 bg-gradient-to-br from-slate-900 via-primary/10 to-slate-900" />
            <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_80%_at_50%_-20%,rgba(79,70,229,0.3),rgba(255,255,255,0))]" />
        </div>
      <div className="mb-8 flex items-center gap-3 text-3xl font-bold">
        <InvoChatLogo className="h-10 w-10 text-primary" />
        <h1 className="text-4xl font-bold tracking-tight bg-gradient-to-r from-primary to-violet-400 bg-clip-text text-transparent">ARVO</h1>
      </div>
      <Card className="w-full max-w-md p-8 space-y-6 rounded-2xl shadow-2xl bg-slate-800/80 backdrop-blur-xl border border-slate-700/50">
        <CardHeader className="p-0 text-center">
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
  );
}
