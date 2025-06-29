'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { useAuth } from '@/context/auth-context';
import { Skeleton } from '@/components/ui/skeleton';

function FullPageLoader() {
    return (
        <div className="flex h-dvh w-full items-center justify-center bg-background p-8">
            <div className="w-full max-w-md space-y-4">
                <Skeleton className="h-10 w-3/4" />
                <Skeleton className="h-8 w-1/2" />
                <Skeleton className="h-12 w-full" />
            </div>
      </div>
    )
}

export function ProtectedRoute({ children }: { children: React.ReactNode }) {
  const { user, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (!loading && !user) {
      router.push('/login');
    }
  }, [user, loading, router]);

  if (loading) {
    // Show a full-page loading skeleton to prevent layout shift
    return <FullPageLoader />;
  }

  if (user) {
    return <>{children}</>;
  }

  // Return a loader while redirecting
  return <FullPageLoader />;
}
