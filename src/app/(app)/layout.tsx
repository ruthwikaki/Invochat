
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
    // This effect now ONLY handles redirection logic.
    // It waits until loading is completely finished.
    if (loading) {
      return;
    }

    // If loading is done and there's no user, go to login.
    if (!user) {
      router.replace('/login');
      return;
    }

    // If loading is done, user exists, but there is no company profile,
    // they MUST complete setup.
    if (user && !userProfile) {
      router.replace('/company-setup');
      return;
    }

  }, [user, userProfile, loading, router]);


  // This is the gatekeeper.
  // We show a loading screen as long as auth is loading.
  // If auth is done, but the user/profile isn't there yet,
  // we continue showing the loading screen while the useEffect above
  // handles the redirection. This prevents rendering the children
  // prematurely.
  if (loading || !user || !userProfile) {
    return <AppLoadingScreen />;
  }

  // Only when EVERYTHING is ready do we render the app.
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
