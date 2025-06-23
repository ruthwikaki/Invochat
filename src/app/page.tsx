
'use client';

import { useAuth } from '@/context/auth-context';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import { InvoChatLogo } from '@/components/invochat-logo';

function RootLoadingScreen() {
  return (
    <div className="flex h-dvh w-full flex-col items-center justify-center bg-muted/40 gap-4">
        <InvoChatLogo className="h-12 w-12" />
        <div className="flex items-center gap-2 text-muted-foreground">
            <div className="h-2 w-2 animate-pulse rounded-full bg-current [animation-delay:-0.3s]" />
            <div className="h-2 w-2 animate-pulse rounded-full bg-current [animation-delay:-0.15s]" />
            <div className="h-2 w-2 animate-pulse rounded-full bg-current" />
        </div>
    </div>
  )
}

export default function Home() {
  const { user, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!loading) {
      if (user) {
        router.replace('/dashboard');
      } else {
        router.replace('/auth/login');
      }
    }
  }, [user, loading, router]);

  // While the redirect is happening, show a loading screen.
  return <RootLoadingScreen />;
}
