
'use client';
import { AppSidebar } from '@/components/app-sidebar';
import { SidebarProvider } from '@/components/ui/sidebar';
import { useAuth } from '@/context/auth-context';
import { useRouter } from 'next/navigation';
import { useEffect } from 'react';
import { Skeleton } from '@/components/ui/skeleton';

function AppLoadingScreen() {
  return (
    <div className="flex h-dvh w-full">
      <div className="hidden md:flex flex-col h-full w-64 border-r p-4 gap-4">
        <Skeleton className="h-10 w-3/4" />
        <Skeleton className="h-8 w-full" />
        <Skeleton className="h-8 w-full" />
        <Skeleton className="h-8 w-full" />
        <div className="flex-grow" />
        <Skeleton className="h-8 w-full" />
        <Skeleton className="h-8 w-full" />
      </div>
      <div className="flex-1 p-8">
        <Skeleton className="h-12 w-1/3 mb-8" />
        <div className="grid gap-4 md:grid-cols-2 lg:grid-cols-4">
            <Skeleton className="h-32" />
            <Skeleton className="h-32" />
            <Skeleton className="h-32" />
            <Skeleton className="h-32" />
        </div>
      </div>
    </div>
  )
}

export default function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const { user, userProfile, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    // This effect handles all redirection logic once the auth state is resolved.
    if (loading) {
      return; // Do nothing while loading.
    }

    if (!user) {
      router.replace('/login');
    } else if (!userProfile) {
      // If user is authenticated but has no profile, they need to complete setup.
      router.replace('/company-setup');
    }
  }, [user, userProfile, loading, router]);

  // This is the gatekeeper. It shows a loading screen until the auth context
  // has finished loading the user and their profile. This prevents rendering
  // the app in a partial state and causing incorrect redirects.
  if (loading || !user || !userProfile) {
    return <AppLoadingScreen />;
  }

  // Only when auth is fully resolved and profile exists, render the main app.
  return (
    <SidebarProvider>
      <div className="flex h-dvh w-full bg-background">
        <AppSidebar />
        <main className="flex flex-1 flex-col overflow-y-auto">
          {children}
        </main>
      </div>
    </SidebarProvider>
  );
}
