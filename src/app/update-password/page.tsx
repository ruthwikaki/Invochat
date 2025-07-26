
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { InvoChatLogo } from '@/components/invochat-logo';
import { UpdatePasswordForm } from '@/components/auth/UpdatePasswordForm';
import Link from 'next/link';

export default async function UpdatePasswordPage({
  searchParams,
}: {
  searchParams: { [key: string]: string | string[] | undefined };
}) {
  const error = typeof searchParams?.error === 'string' ? searchParams.error : null;
    
  return (
    <div className="flex items-center justify-center min-h-screen bg-background">
      <div className="relative w-full max-w-md overflow-hidden rounded-2xl border bg-card/80 p-4 shadow-2xl backdrop-blur-lg">
          <div className="absolute inset-0 -z-10">
              <div className="absolute inset-0 bg-gradient-to-br from-background via-primary/10 to-background" />
          </div>
        <Card className="w-full bg-transparent border-none p-8 space-y-6">
          <CardHeader className="p-0 text-center">
            <Link href="/" className="flex justify-center items-center gap-3 mb-4">
              <InvoChatLogo className="h-10 w-10 text-primary" />
              <h1 className="text-4xl font-bold tracking-tight bg-gradient-to-r from-primary to-purple-400 bg-clip-text text-transparent">ARVO</h1>
            </Link>
            <CardTitle className="text-2xl">Create a New Password</CardTitle>
            <CardDescription className="text-muted-foreground">
              Enter a new password for your account below.
            </CardDescription>
          </CardHeader>
          <CardContent className="p-0">
            <UpdatePasswordForm error={error} />
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
