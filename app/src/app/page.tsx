'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/context/auth-context';
import { InvoChatLogo } from '@/components/invochat-logo';

export default function RootPage() {
  const { user, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!loading) {
      if (user) {
        router.push('/dashboard');
      } else {
        router.push('/login');
      }
    }
  }, [user, loading, router]);

  // Show a loading spinner while checking the auth state to prevent flashes of content.
  return (
    <div className="flex min-h-screen items-center justify-center bg-background">
      <div className="flex flex-col items-center space-y-4">
        <InvoChatLogo className="h-12 w-12" />
        <div className="flex items-center gap-2 text-muted-foreground">
            <div className="h-2 w-2 animate-pulse rounded-full bg-primary [animation-delay:-0.3s]"></div>
            <div className="h-2 w-2 animate-pulse rounded-full bg-primary [animation-delay:-0.15s]"></div>
            <div className="h-2 w-2 animate-pulse rounded-full bg-primary"></div>
        </div>
      </div>
    </div>
  );
}
